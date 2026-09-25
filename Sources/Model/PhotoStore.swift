import Foundation
import Photos
import UIKit

enum Verdict: String, Codable {
    case kept
    case queued
    case deleted
}

enum StatKind: String, CaseIterable, Codable {
    case photo
    case screenshot
    case video

    var title: String {
        switch self {
        case .photo: "鑺遍棿鍐?
        case .screenshot: "纰庡奖闆?
        case .video: "娴佸厜鍗?
        }
    }

    var symbol: String {
        switch self {
        case .photo: "photo"
        case .screenshot: "camera.viewfinder"
        case .video: "play.circle"
        }
    }

    init(asset: PHAsset) {
        if asset.mediaType == .video {
            self = .video
        } else if asset.mediaSubtypes.contains(.photoScreenshot) {
            self = .screenshot
        } else {
            self = .photo
        }
    }
}

/// 鍒嗙被绱锛氭煡鐪嬫暟 / 鍒犻櫎鏁?/ 鑵惧嚭瀛楄妭鏁?struct CleanupStats: Codable {
    var reviewed: [String: Int] = [:]
    var deleted: [String: Int] = [:]
    var bytes: [String: Int64] = [:]
}

enum RootTab: Int, CaseIterable, Identifiable {
    case photos
    case screenshots
    case editing
    case videos
    case stats

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .photos: "鑺遍棿鍐?
        case .screenshots: "纰庡奖闆?
        case .editing: "鑺卞奖鏌?
        case .videos: "娴佸厜鍗?
        case .stats: "宀佸崕绨?
        }
    }

    var symbol: String {
        switch self {
        case .photos: "photo.on.rectangle.angled"
        case .screenshots: "camera.viewfinder"
        case .editing: "camera.filters"
        case .videos: "play.rectangle.fill"
        case .stats: "chart.bar.xaxis"
        }
    }

    var mediaType: PHAssetMediaType? {
        switch self {
        case .photos, .screenshots: .image
        case .videos: .video
        case .editing, .stats: nil
        }
    }
}

/// 褰撳墠鏍忛噷鍐嶆寜鍐呭绫诲瀷绛涗竴閬嶏紝瀵瑰簲鍘熺増椤堕儴涓嬫媺鑿滃崟閭ｅ嚑椤?enum ContentFilter: String, CaseIterable, Identifiable {
    case all
    case screenshot
    case selfie
    case live
    case animated
    case tall

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "鐓х墖"
        case .screenshot: "鎴睆"
        case .selfie: "鑷媿"
        case .live: "瀹炲喌"
        case .animated: "鍔ㄥ浘"
        case .tall: "闀垮浘"
        }
    }

    var symbol: String {
        switch self {
        case .all: "photo"
        case .screenshot: "camera.viewfinder"
        case .selfie: "person.crop.square"
        case .live: "livephoto"
        case .animated: "film"
        case .tall: "rectangle.portrait"
        }
    }

    func matches(_ asset: PHAsset) -> Bool {
        switch self {
        case .all:
            return true
        case .screenshot:
            return asset.mediaSubtypes.contains(.photoScreenshot)
        case .selfie:
            return false   // 鐢?PhotoStore 鏌ヨ嚜鎷嶆櫤鑳界浉鍐岋紝瑙?isSelfie(_:)
        case .live:
            return asset.mediaSubtypes.contains(.photoLive)
        case .animated:
            return asset.playbackStyle == .imageAnimated
        case .tall:
            return asset.pixelWidth > 0 && asset.pixelHeight >= asset.pixelWidth * 2
        }
    }
}

enum BrowseMode: String, CaseIterable, Identifiable {
    case blindBox
    case onThisDay

    var id: String { rawValue }
    var title: String {
        switch self {
        case .blindBox: "闅忔満鐩茬洅"
        case .onThisDay: "鍥炲埌閭ｅぉ"
        }
    }
}

enum TimeFormat: String, CaseIterable, Identifiable {
    case relative
    case absolute

    var id: String { rawValue }
    var title: String {
        switch self {
        case .relative: "璺濅粖"
        case .absolute: "鍏蜂綋鏃ユ湡"
        }
    }
}

enum DoubleTapAction: String, CaseIterable, Identifiable {
    case zoom
    case favorite

    var id: String { rawValue }
    var title: String {
        switch self {
        case .zoom: "鏀惧ぇ"
        case .favorite: "鏀惰棌"
        }
    }
}

/// 鏈濊姳澶曟嬀锛氬線骞翠粖澶╂媿鐨勪笢瑗匡紝鎸夊勾浠藉垎缁?struct MemoryGroup: Identifiable {
    let year: Int
    let assets: [PHAsset]
    var id: Int { year }
}

@MainActor
final class PhotoStore: NSObject, ObservableObject {

    static let deckSize = 20

    @Published var photoBatchSize: Int {
        didSet {
            guard oldValue != photoBatchSize else { return }
            defaults.set(photoBatchSize, forKey: Keys.photoBatch)
            if tab != .videos { deal() }
        }
    }

    @Published var videoBatchSize: Int {
        didSet {
            guard oldValue != videoBatchSize else { return }
            defaults.set(videoBatchSize, forKey: Keys.videoBatch)
            if tab == .videos { deal() }
        }
    }

    var currentBatchSize: Int { tab == .videos ? videoBatchSize : photoBatchSize }

    @Published private(set) var authorization: PHAuthorizationStatus = .notDetermined
    @Published private(set) var deck: [PHAsset] = []
    @Published private(set) var cursor: Int = 0
    @Published private(set) var queuedCount = 0
    @Published private(set) var deletedCount = 0
    @Published private(set) var remainingCount = 0
    @Published private(set) var libraryCount = 0
    @Published private(set) var canUndo = false
    @Published private(set) var isCommitting = false
    @Published private(set) var stats = CleanupStats()
    @Published private(set) var favoriteIDs: Set<String> = []
    @Published var errorMessage: String?

    @Published var tab: RootTab = .photos {
        didSet {
            guard oldValue != tab else { return }
            pendingHistoryReset = true
            // 绂诲紑鏃ф爮锛氬姩杩囩収鐗囧氨浣滃簾瀹冪殑瀛樻。锛堜笅娆″彂鏂扮墝锛夛紝娌″姩杩囧氨鍘熸牱瀛樻。
            if oldValue.mediaType != nil {
                if actedSinceEntry {
                    deckArchive[oldValue] = nil
                } else {
                    deckArchive[oldValue] = (deck, cursor, deckHistory)
                }
                actedSinceEntry = false
            }
            guard tab.mediaType != nil else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                if let saved = deckArchive[tab] {
                    // 鎭㈠瀛樻。锛氳繖鏍忎笂娆℃槸浠€涔堟牱灏辫繕鏄粈涔堟牱锛岀収鐗囧叏鍦ㄧ紦瀛橀噷锛岀鍒囦笉闂?                    deck = saved.deck
                    cursor = saved.cursor
                    deckHistory = saved.history
                    actedSinceEntry = false
                    if let pool = pools[poolKey] {
                        tabTotal = pool.total
                        candidates = pool.candidates
                    } else {
                        rebuildCandidates()
                    }
                    refreshCounts()
                    pruneDeck()
                } else {
                    refreshLibrary(redeal: true)
                }
            }
        }
    }

    @Published var mode: BrowseMode {
        didSet {
            guard oldValue != mode else { return }
            defaults.set(mode.rawValue, forKey: Keys.mode)
            invalidateAllPools()
            refreshLibrary(redeal: true)
        }
    }

    /// 椤堕儴涓嬫媺鑿滃崟閫夌殑鍐呭绫诲瀷锛屽彧鍦ㄥ浘鐗囨爮鐢熸晥
    @Published var contentFilter: ContentFilter = .all {
        didSet {
            guard oldValue != contentFilter else { return }
            invalidateCurrentPool()
            refreshLibrary(redeal: true)
        }
    }

    /// 婕旂ず妯″紡锛氳蛋瀹屽叏娴佺▼浣嗕笉鐪熺殑鍒犳枃浠?    @Published var demoMode: Bool {
        didSet {
            guard oldValue != demoMode else { return }
            defaults.set(demoMode, forKey: Keys.demo)
        }
    }

    @Published var reminderOn: Bool {
        didSet {
            guard oldValue != reminderOn else { return }
            defaults.set(reminderOn, forKey: Keys.reminderOn)
            Reminder.apply(on: reminderOn, hour: reminderHour, minute: reminderMinute)
        }
    }

    @Published var reminderHour: Int {
        didSet {
            guard oldValue != reminderHour else { return }
            defaults.set(reminderHour, forKey: Keys.reminderHour)
            if reminderOn { Reminder.apply(on: true, hour: reminderHour, minute: reminderMinute) }
        }
    }

    @Published var reminderMinute: Int {
        didSet {
            guard oldValue != reminderMinute else { return }
            defaults.set(reminderMinute, forKey: Keys.reminderMinute)
            if reminderOn { Reminder.apply(on: true, hour: reminderHour, minute: reminderMinute) }
        }
    }

    @Published var hapticsEnabled: Bool {
        didSet {
            guard oldValue != hapticsEnabled else { return }
            defaults.set(hapticsEnabled, forKey: Keys.haptics)
        }
    }

    @Published var doubleTapAction: DoubleTapAction {
        didSet {
            guard oldValue != doubleTapAction else { return }
            defaults.set(doubleTapAction.rawValue, forKey: Keys.doubleTap)
        }
    }

    @Published var showFPS: Bool {
        didSet {
            guard oldValue != showFPS else { return }
            defaults.set(showFPS, forKey: Keys.showFPS)
        }
    }

    @Published var timeFormat: TimeFormat {
        didSet {
            guard oldValue != timeFormat else { return }
            defaults.set(timeFormat.rawValue, forKey: Keys.timeFormat)
        }
    }

    /// 鎸夌敤鎴峰湪璁剧疆閲岄€夌殑鍙ｅ緞鏄剧ず鎷嶆憚鏃堕棿
    func reviewTimeText(for asset: PHAsset) -> String {
        timeFormat == .relative
            ? TimeText.since(asset.creationDate)
            : TimeText.precise(asset.creationDate)
    }

    private enum Keys {
        static let verdicts = "huajianji.verdicts.v1"
        static let stats = "huajianji.stats.v1"
        static let photoBatch = "huajianji.batch.photo"
        static let videoBatch = "huajianji.batch.video"
        static let favorites = "huajianji.favorites.v1"
        static let mode = "huajianji.mode"
        static let demo = "huajianji.demoMode"
        static let reminderOn = "huajianji.reminder.on"
        static let reminderHour = "huajianji.reminder.hour"
        static let reminderMinute = "huajianji.reminder.minute"
        static let haptics = "huajianji.haptics"
        static let doubleTap = "huajianji.doubleTap"
        static let timeFormat = "huajianji.timeFormat"
        static let showFPS = "huajianji.showFPS"
    }

    private let defaults = UserDefaults.standard
    private var fetchResult: PHFetchResult<PHAsset>?
    private var verdicts: [String: Verdict] = [:]
    private var undoStack: [String] = []
    /// 鏈€杩戝彂杩囩殑鍑犵粍锛涘乏婊戦€€鍒版湰缁勭涓€寮犳椂鐢ㄥ畠缈诲洖涓婁竴缁?    private var deckHistory: [[PHAsset]] = []
    /// 鎹㈡爮鍚庣疆浣嶏細涓嬩竴娆?deal 涓嶆竻鍘嗗彶鑰屾槸鎶婃棫鏍忛偅缁勪涪鎺夛紝閬垮厤宸︽粦涓插埌鍒殑鍐?    private var pendingHistoryReset = false
    private var batchMarked: [String] = []
    private var kindOf: [String: String] = [:]
    /// 鎹㈡爮瀛樻。锛氭病鍔ㄨ繃鐓х墖鐨勬爮鍒囧洖鏉ュ師鏍锋仮澶嶏紝涓嶅彂鏂扮墝
    private var deckArchive: [RootTab: (deck: [PHAsset], cursor: Int, history: [[PHAsset]])] = [:]
    /// 鏈杩涙爮鍚庢湁娌℃湁鍋氳繃鏍囪绫诲姩浣?    private var actedSinceEntry = false
    /// 褰撳墠鍒嗙被涓嬭繕娌＄瓫杩囩殑璧勬簮 id锛屽彂鐗屾椂鐩存帴浠庤繖閲岄殢鏈烘娊銆?    /// 瀛?id 涓嶅瓨涓嬫爣锛歅HFetchResult 浼氶殢鐩稿唽鍙樺寲鑷繁鏇存柊锛屼笅鏍囦細閿欎綅
    private var candidates: [String] = []
    private var tabTotal = 0
    /// 姣忎釜鍒嗙被鐨勬睜瀛愬拰鎶撳彇缁撴灉閮界紦瀛橈紝鍒囨爮涓嶅啀鍏ㄥ簱閲嶆壂锛涙睜瀛愯繕瑕佹寜鍐呭绫诲瀷鍒嗗紑
    private struct Pool { let total: Int; var candidates: [String] }
    private var pools: [String: Pool] = [:]
    private var fetchCache: [Int: PHFetchResult<PHAsset>] = [:]
    private var selfieIDs: Set<String>?
    private var poolKey: String { "\(tab.rawValue)|\(contentFilter.rawValue)" }
    private var persistTask: Task<Void, Never>?
    private var registered = false

    var writable: Bool {
        authorization == .authorized || authorization == .limited
    }

    var current: PHAsset? { card(at: 0) }

    /// 鏈壒 20 寮犻噷杩樺墿鍑犲紶娌＄瓫
    var deckRemaining: Int { max(0, deck.count - cursor) }

    func card(at offset: Int) -> PHAsset? {
        let index = cursor + offset
        return deck.indices.contains(index) ? deck[index] : nil
    }

    /// 闇囧姩鍙嶉锛岃缃噷鍙互鏁翠綋鍏虫帀
    func bump(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    override init() {
        let stored = UserDefaults.standard
        photoBatchSize = stored.object(forKey: Keys.photoBatch) as? Int ?? Self.deckSize
        videoBatchSize = stored.object(forKey: Keys.videoBatch) as? Int ?? Self.deckSize
        mode = BrowseMode(rawValue: stored.string(forKey: Keys.mode) ?? "") ?? .blindBox
        demoMode = stored.bool(forKey: Keys.demo)
        reminderOn = stored.bool(forKey: Keys.reminderOn)
        reminderHour = stored.object(forKey: Keys.reminderHour) as? Int ?? 20
        reminderMinute = stored.object(forKey: Keys.reminderMinute) as? Int ?? 30
        hapticsEnabled = stored.object(forKey: Keys.haptics) as? Bool ?? true
        doubleTapAction = DoubleTapAction(rawValue: stored.string(forKey: Keys.doubleTap) ?? "") ?? .zoom
        timeFormat = TimeFormat(rawValue: stored.string(forKey: Keys.timeFormat) ?? "") ?? .relative
        showFPS = stored.bool(forKey: Keys.showFPS)
        super.init()
        if let data = defaults.data(forKey: Keys.verdicts),
           let saved = try? JSONDecoder().decode([String: Verdict].self, from: data) {
            // 鏃х増鏈褰曚笉鍒嗘爮锛岄敭閲屾病鏈?"|" 鍓嶇紑锛岃涓嶅嚭鏉ュ氨鐩存帴涓㈡帀閲嶆潵涓€缁?            verdicts = saved.filter { $0.key.contains("|") }
        }
        if let data = defaults.data(forKey: Keys.stats),
           let saved = try? JSONDecoder().decode(CleanupStats.self, from: data) {
            stats = saved
        }
        if let ids = defaults.stringArray(forKey: Keys.favorites) {
            favoriteIDs = Set(ids)
        }
    }

    // MARK: - 鏀惰棌

    func isFavorite(_ id: String) -> Bool { favoriteIDs.contains(id) }

    @discardableResult
    func toggleFavorite(_ asset: PHAsset) -> Bool {
        let id = asset.localIdentifier
        if favoriteIDs.contains(id) {
            favoriteIDs.remove(id)
        } else {
            favoriteIDs.insert(id)
        }
        schedulePersist()
        return favoriteIDs.contains(id)
    }

    func favoriteAssets() -> [PHAsset] {
        guard !favoriteIDs.isEmpty else { return [] }
        var list: [PHAsset] = []
        PHAsset.fetchAssets(withLocalIdentifiers: Array(favoriteIDs), options: nil)
            .enumerateObjects { asset, _, _ in list.append(asset) }
        return list.sorted {
            ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast)
        }
    }

    // MARK: - 鏈濊姳澶曟嬀锛堝線骞翠粖澶╋級

    /// 涓€骞翠竴鏉℃煡璇氦缁?PhotoKit 杩囨护锛屾瘮鍏ㄥ簱鎵竴閬嶄究瀹滃緱澶氾紱鏀惧埌鍚庡彴绾跨▼璋?    nonisolated static func memoryGroups() -> [MemoryGroup] {
        let calendar = Calendar.current
        let today = calendar.dateComponents([.month, .day], from: Date())
        let thisYear = calendar.component(.year, from: Date())
        var groups: [MemoryGroup] = []
        for year in stride(from: thisYear - 1, through: max(2007, thisYear - 15), by: -1) {
            var components = today
            components.year = year
            guard let start = calendar.date(from: components),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@",
                                            start as NSDate, end as NSDate)
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            var list: [PHAsset] = []
            PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in
                if list.count < 60 { list.append(asset) }
            }
            if !list.isEmpty { groups.append(MemoryGroup(year: year, assets: list)) }
        }
        return groups
    }

    /// 鎶婃煇骞寸殑銆屼粖澶┿€嶅綋鎴愪竴缁勭墝鎽婂紑锛岀洿鎺ヨ繘澶у浘椤电炕
    func showMemory(_ assets: [PHAsset]) {
        guard !assets.isEmpty else { return }
        deck = assets
        cursor = 0
        batchMarked = []
        undoStack.removeAll()
        refreshCounts()
    }

    // MARK: - 缁熻璇绘暟

    func reviewedCount(_ kind: StatKind) -> Int { stats.reviewed[kind.rawValue] ?? 0 }
    func deletedCount(_ kind: StatKind) -> Int { stats.deleted[kind.rawValue] ?? 0 }
    func freedBytes(_ kind: StatKind) -> Int64 { stats.bytes[kind.rawValue] ?? 0 }

    var totalReviewed: Int { StatKind.allCases.reduce(0) { $0 + reviewedCount($1) } }
    var totalDeleted: Int { StatKind.allCases.reduce(0) { $0 + deletedCount($1) } }
    var totalFreedBytes: Int64 { StatKind.allCases.reduce(Int64(0)) { $0 + freedBytes($1) } }

    func share(of kind: StatKind) -> Double {
        let total = totalFreedBytes
        guard total > 0 else { return 0 }
        return Double(freedBytes(kind)) / Double(total)
    }

    // MARK: - 鏉冮檺

    func requestAccess() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        apply(status)
        guard status == .notDetermined else { return }
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] granted in
            Task { @MainActor in self?.apply(granted) }
        }
    }

    private func apply(_ status: PHAuthorizationStatus) {
        guard status != authorization else { return }
        authorization = status
        guard writable else {
            fetchResult = nil
            deck = []
            return
        }
        if !registered {
            PHPhotoLibrary.shared().register(self)
            registered = true
        }
        refreshLibrary(redeal: true)
    }

    // MARK: - 鎵规

    private func fetchOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        if let type = tab.mediaType {
            options.predicate = NSPredicate(format: "mediaType == %d", Int32(type.rawValue))
        }
        return options
    }

    private func currentFetchResult() -> PHFetchResult<PHAsset> {
        PHAsset.fetchAssets(with: fetchOptions())
    }

    private func refreshLibrary(redeal: Bool) {
        guard writable else { return }
        let fetchKey = tab.rawValue
        let result: PHFetchResult<PHAsset>
        if let cached = fetchCache[fetchKey] {
            result = cached
        } else {
            result = currentFetchResult()
            fetchCache[fetchKey] = result
        }
        fetchResult = result
        if let pool = pools[poolKey] {
            tabTotal = pool.total
            candidates = pool.candidates
        } else {
            rebuildCandidates()
        }
        if redeal {
            deal()
        } else {
            pruneDeck()
        }
        refreshCounts()
    }

    /// 鐓х墖鏍?= 鎵€鏈夊浘鐗囷紙鍚埅鍥撅級锛涙埅鍥炬爮 = 鍙湁鎴浘锛涜棰戞爮 = 鍙湁瑙嗛
    private func matchesTab(_ asset: PHAsset) -> Bool {
        let isShot = asset.mediaSubtypes.contains(.photoScreenshot)
        switch tab {
        case .photos: return asset.mediaType == .image
        case .screenshots: return isShot
        case .videos: return asset.mediaType == .video
        case .editing, .stats: return false
        }
    }

    private func eligible(_ asset: PHAsset) -> Bool {
        guard verdicts[vkey(asset.localIdentifier)] == nil else { return false }
        if tab != .videos, !filterMatches(asset) { return false }
        guard mode == .onThisDay else { return true }
        return isOnThisDay(asset)
    }

    private func filterMatches(_ asset: PHAsset) -> Bool {
        contentFilter == .selfie ? isSelfie(asset) : contentFilter.matches(asset)
    }

    /// 鑷媿娌℃湁 mediaSubtype 鍙垽锛屽彧鑳芥煡绯荤粺銆岃嚜鎷嶃€嶆櫤鑳界浉鍐岋紝鍙栦竴娆＄紦瀛樹綇
    private func isSelfie(_ asset: PHAsset) -> Bool {
        if selfieIDs == nil {
            var ids = Set<String>()
            PHAssetCollection.fetchAssetCollections(with: .smartAlbum,
                                                    subtype: .smartAlbumSelfPortraits,
                                                    options: nil)
                .enumerateObjects { collection, _, _ in
                    PHAsset.fetchAssets(in: collection, options: nil)
                        .enumerateObjects { item, _, _ in ids.insert(item.localIdentifier) }
                }
            selfieIDs = ids
        }
        return selfieIDs?.contains(asset.localIdentifier) ?? false
    }

    private func isOnThisDay(_ asset: PHAsset) -> Bool {
        guard let date = asset.creationDate else { return false }
        let calendar = Calendar.current
        let now = calendar.dateComponents([.year, .month, .day], from: Date())
        let then = calendar.dateComponents([.year, .month, .day], from: date)
        return now.month == then.month && now.day == then.day && (then.year ?? 0) < (now.year ?? 0)
    }

    /// 涓€閬嶆壂瀹屽綋鍓嶅垎绫荤殑鍙€夋睜锛岄伩鍏嶆瘡娆″彂鐗岄兘鍏ㄥ簱璇曟帰
    private func rebuildCandidates() {
        guard let result = fetchResult else {
            candidates = []
            tabTotal = 0
            return
        }
        var matching = 0
        var fresh: [String] = []
        result.enumerateObjects { asset, _, _ in
            guard self.matchesTab(asset) else { return }
            matching += 1
            if self.eligible(asset) { fresh.append(asset.localIdentifier) }
        }
        tabTotal = matching
        candidates = fresh
        pools[poolKey] = Pool(total: matching, candidates: fresh)
    }

    /// 鐩稿唽鍐呭鎴栫瓫閫夊彛寰勫彉浜嗭細鍏ㄩ儴浣滃簾
    private func invalidateAllPools() {
        pools.removeAll()
        fetchCache.removeAll()
        selfieIDs = nil
    }

    /// 鍙湁褰撳墠鍒嗙被鐨勬睜瀛愰渶瑕侀噸绠?    private func invalidateCurrentPool() {
        pools[poolKey] = nil
    }

    /// 浠庣浉鍐岄噷闅忔満鍙戜竴鎵癸紝鏁伴噺鏈€澶?deckSize 寮?    func dealNewDeck() {
        deal()
    }

    /// 浠庡€欓€夋睜閲岄殢鏈哄彇涓€缁勶紝鍙栬蛋鐨勪粠姹犲瓙閲屾憳鎺夛紝涓嬩竴缁勪笉浼氶噸澶?    private func deal() {
        guard !candidates.isEmpty else {
            deck = []
            cursor = 0
            if pendingHistoryReset { deckHistory.removeAll(); pendingHistoryReset = false }
            refreshCounts()
            return
        }
        let wanted = min(currentBatchSize, candidates.count)
        var picked: [String] = []
        picked.reserveCapacity(wanted)
        for _ in 0..<wanted {
            picked.append(candidates.remove(at: Int.random(in: 0..<candidates.count)))
        }
        // 鍙瓨 id锛屽彇鐗屾椂鎵嶆崲鎴?PHAsset锛岀浉鍐屽彉鍔ㄥ悗涓嶄細鎷垮埌閿欎綅鐨勯偅寮?        var byID: [String: PHAsset] = [:]
        PHAsset.fetchAssets(withLocalIdentifiers: picked, options: nil)
            .enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }
        // 鎹㈢粍鍓嶆妸鏃х粍鐣欎竴浠斤紝宸︽粦閫€鍒扮涓€寮犳椂杩樿兘缈诲洖鍘?        if pendingHistoryReset {
            deckHistory.removeAll()
            pendingHistoryReset = false
        } else if !deck.isEmpty {
            deckHistory.append(deck)
            if deckHistory.count > 8 { deckHistory.removeFirst() }
        }
        deck = picked.compactMap { byID[$0] }
        cursor = 0
        batchMarked = []
        pools[poolKey] = Pool(total: tabTotal, candidates: candidates)
        refreshCounts()
    }

    // MARK: - 棣栭〉棰勮缈婚〉锛堜笉浜х敓浠讳綍鏍囪锛?
    var canGoPrevious: Bool { cursor > 0 || !deckHistory.isEmpty }
    var canGoNext: Bool { cursor + 1 < deck.count }

    func goNextPreview() {
        guard canGoNext else { return }
        cursor += 1
    }

    /// 鍦ㄦ湰缁勯噷灏卞線鍥為€€锛涘凡缁忛€€鍒扮涓€寮犲氨缈诲洖涓婁竴缁勶紝鎺ョ潃浠庨偅寮犵户缁€€锛?    /// 杩欐牱宸︽粦鍦ㄤ换浣曟椂鍊欓兘鏈夊弽棣堬紝涓嶄細鍙樻垚銆屽彧鑳藉彸婊戙€?    func goPreviousPreview() {
        guard canGoPrevious else { return }
        if cursor > 0 {
            cursor -= 1
            return
        }
        guard let previous = deckHistory.popLast() else { return }
        deckHistory.append(deck)          // 褰撳墠杩欑粍鍘嬪洖鍘伙紝鍙虫粦杩樿兘鍐嶅洖鏉?        deck = previous
        cursor = max(previous.count - 1, 0)
    }

    func focus(_ asset: PHAsset) {
        if let position = deck.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) {
            cursor = position
        }
    }

    /// 娴忚璁板綍鎸夋爮鍒嗗紑瀛橈細鍚屼竴寮犳埅鍥惧湪鐓х墖鏍忓拰鎴浘鏍忓悇绠楀悇鐨?    private func vkey(_ assetID: String) -> String { "\(tab.rawValue)|\(assetID)" }

    private static func realID(from key: String) -> String {
        guard let index = key.firstIndex(of: "|") else { return key }
        return String(key[key.index(after: index)...])
    }

    /// 鏈壒閲岃鏍囪寰呭垹銆佷絾杩樻病鐪熸鍒犻櫎鐨勶紙杩斿洖鐪熷疄 localIdentifier锛?    var queuedInBatch: [String] {
        batchMarked.compactMap { verdicts[$0] == .queued ? Self.realID(from: $0) : nil }
    }

    /// 鏈壒閲岄€夋嫨淇濈暀鐨勫紶鏁?    var keptInBatch: Int {
        batchMarked.filter { verdicts[$0] == .kept }.count
    }

    /// 缁熻椤电敤锛氭妸鍏ㄩ儴寰呭垹鏍囪閫€鍥烇紝涓嶅垹浠讳綍涓滆タ
    func discardAllQueued() {
        let snapshot = verdicts
        for (key, verdict) in snapshot where verdict == .queued {
            verdicts.removeValue(forKey: key)
            if let kind = kindOf.removeValue(forKey: key), let current = stats.reviewed[kind] {
                stats.reviewed[kind] = max(0, current - 1)
            }
        }
        undoStack.removeAll()
        batchMarked = []
        writeToDisk()
        invalidateCurrentPool()
        refreshLibrary(redeal: false)
    }

    /// 鏀惧純锛氭湰鎵瑰緟鍒犳爣璁板叏閮ㄩ€€鍥烇紝涓嶅垹浠讳綍涓滆タ锛岀洿鎺ュ啀鏉ヤ竴缁?    func abandonBatch() {
        for key in batchMarked where verdicts[key] == .queued {
            verdicts.removeValue(forKey: key)
            if let kind = kindOf.removeValue(forKey: key), let current = stats.reviewed[kind] {
                stats.reviewed[kind] = max(0, current - 1)
            }
        }
        undoStack.removeAll()
        batchMarked = []
        writeToDisk()
        invalidateCurrentPool()
        refreshLibrary(redeal: true)
    }

    private func pruneDeck() {
        guard !deck.isEmpty else { return }
        let alive = PHAsset.fetchAssets(
            withLocalIdentifiers: deck.map(\.localIdentifier), options: nil)
        var ids = Set<String>()
        alive.enumerateObjects { asset, _, _ in ids.insert(asset.localIdentifier) }
        deck = deck.filter { ids.contains($0.localIdentifier) }
        cursor = min(cursor, max(deck.count - 1, 0))
        // 鍓╀笉鍒颁笁寮犳拺涓嶈捣鎵囧舰鍗″爢锛岀洿鎺ヨˉ鍙戞柊鐨勪竴鎵?        if deck.count < 3 { deal() }
    }

    // MARK: - 绛涢€?
    /// 鍏ㄥ睆绛涢€夐〉鏍囪涓€寮狅細.queued 寰呭垹 / .kept 鐪嬭繃淇濈暀
    func mark(_ verdict: Verdict, asset: PHAsset) {
        let key = vkey(asset.localIdentifier)
        guard verdicts[key] == nil else { return }
        verdicts[key] = verdict
        undoStack.append(key)
        batchMarked.append(key)
        let kind = StatKind(asset: asset).rawValue
        kindOf[key] = kind
        stats.reviewed[kind, default: 0] += 1
        actedSinceEntry = true
        schedulePersist()
        refreshCounts()
    }

    func undoLast() {
        guard let key = undoStack.popLast() else { return }
        verdicts.removeValue(forKey: key)
        batchMarked.removeAll { $0 == key }
        if let kind = kindOf.removeValue(forKey: key), let current = stats.reviewed[kind] {
            stats.reviewed[kind] = max(0, current - 1)
        }
        let id = Self.realID(from: key)
        if let position = deck.firstIndex(where: { $0.localIdentifier == id }) {
            cursor = position
        } else if let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject {
            deck.insert(asset, at: min(cursor, deck.count))
        }
        actedSinceEntry = true
        schedulePersist()
        refreshCounts()
    }

    /// 寰呭垹寮瑰眰閲岀偣鍗曞紶鍙嶆倲锛氭妸杩欎竴寮犱粠寰呭垹闃熷垪鎹炲洖鏉?    func unmark(_ asset: PHAsset) {
        let key = vkey(asset.localIdentifier)
        guard verdicts[key] == .queued else { return }
        verdicts.removeValue(forKey: key)
        batchMarked.removeAll { $0 == key }
        undoStack.removeAll { $0 == key }
        if let kind = kindOf.removeValue(forKey: key), let current = stats.reviewed[kind] {
            stats.reviewed[kind] = max(0, current - 1)
        }
        schedulePersist()
        refreshCounts()
        // 杩欏紶閲嶆柊鍙樺洖鍙娊锛屼箣鍚庡彂鐗岃繕鑳藉啀瑙佸埌瀹冿紱涓嶅姩褰撳墠杩欏壇鐗?        invalidateCurrentPool()
    }

    /// 鎶婂緟鍒犻槦鍒楁彁浜ょ粰绯荤粺鐩稿唽锛屼箣鍚庝粛鍙湪銆屾渶杩戝垹闄ゃ€嶆壘鍥?30 澶?    func commitQueuedDeletions() async {
        let keys = verdicts.compactMap { $0.value == .queued ? $0.key : nil }
        let ids = keys.map(Self.realID)
        guard !ids.isEmpty, !isCommitting else { return }
        isCommitting = true
        defer {
            isCommitting = false
            flush()
        }
        if demoMode {
            // 婕旂ず妯″紡锛氬彧璁拌处锛屼笉纰扮浉鍐?            for key in keys { verdicts[key] = .deleted }
            undoStack.removeAll()
            refreshLibrary(redeal: true)
            return
        }
        do {
            // 鍒犻櫎鍓嶅厛鍙栧洖绫诲瀷鍜屽崰鐢ㄤ綋绉紝鍒犲畬灏辫涓嶅埌浜?            let targets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            var pendingCount: [String: Int] = [:]
            var pendingBytes: [String: Int64] = [:]
            targets.enumerateObjects { asset, _, _ in
                let kind = StatKind(asset: asset).rawValue
                pendingCount[kind, default: 0] += 1
                pendingBytes[kind, default: 0] += Self.byteSize(of: asset)
            }
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(targets)
            }
            for key in keys { verdicts[key] = .deleted }
            favoriteIDs.subtract(ids)
            for (kind, count) in pendingCount { stats.deleted[kind, default: 0] += count }
            for (kind, bytes) in pendingBytes { stats.bytes[kind, default: 0] += bytes }
            undoStack.removeAll()
            // 鐩稿唽宸茬粡鍙樹簡锛岀紦瀛樼殑鎶撳彇缁撴灉鍜屾睜瀛愬叏閮ㄤ綔搴燂紝鍒瓑寮傛閫氱煡
            invalidateAllPools()
            refreshLibrary(redeal: true)
        } catch {
            errorMessage = "鍒犻櫎娌℃湁鐢熸晥锛歕(error.localizedDescription)"
        }
    }

    private static func byteSize(of asset: PHAsset) -> Int64 {
        PHAssetResource.assetResources(for: asset).reduce(Int64(0)) { total, resource in
            total + ((resource.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0)
        }
    }

    func resetProgress() {
        verdicts.removeAll()
        undoStack.removeAll()
        batchMarked = []
        kindOf.removeAll()
        stats = CleanupStats()
        invalidateAllPools()
        writeToDisk()
        refreshLibrary(redeal: true)
    }

    // MARK: - 璁板綍瀵煎嚭 / 瀵煎叆锛堣嚜绛炬病鏈?CloudKit 鏉冮檺锛岀敤鏂囦欢鎼級

    struct BackupPayload: Codable {
        var version = 1
        var exportedAt = Date()
        var verdicts: [String: Verdict]
        var stats: CleanupStats
        var favorites: [String]
    }

    func exportBackup() -> URL? {
        let payload = BackupPayload(verdicts: verdicts, stats: stats, favorites: Array(favoriteIDs))
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("鑺遍棿闆嗚褰?\(Self.stamp()).json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            errorMessage = "瀵煎嚭澶辫触锛歕(error.localizedDescription)"
            return nil
        }
    }

    func importBackup(from url: URL) {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(BackupPayload.self, from: data) else {
            errorMessage = "杩欎釜鏂囦欢涓嶆槸鑺遍棿闆嗗鍑虹殑璁板綍"
            return
        }
        verdicts = payload.verdicts
        stats = payload.stats
        favoriteIDs = Set(payload.favorites)
        undoStack.removeAll()
        batchMarked = []
        writeToDisk()
        refreshLibrary(redeal: true)
        errorMessage = "宸插鍏?\(payload.verdicts.count) 鏉℃祻瑙堣褰?
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        return f.string(from: Date())
    }

    // MARK: - 璁℃暟涓庢寔涔呭寲

    private func refreshCounts() {
        var queued = 0
        var deleted = 0
        for verdict in verdicts.values {
            if verdict == .queued { queued += 1 }
            if verdict == .deleted { deleted += 1 }
        }
        queuedCount = queued
        deletedCount = deleted
        libraryCount = tabTotal
        remainingCount = candidates.count
        canUndo = !undoStack.isEmpty
    }

    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.writeToDisk()
        }
    }

    /// 閫€鍒板悗鍙版椂璋冪敤锛屽埆鎶婃敀鐫€鐨勮繘搴︿涪浜?    func flush() {
        persistTask?.cancel()
        writeToDisk()
    }

    private func writeToDisk() {
        if let data = try? JSONEncoder().encode(verdicts) {
            defaults.set(data, forKey: Keys.verdicts)
        }
        if let data = try? JSONEncoder().encode(stats) {
            defaults.set(data, forKey: Keys.stats)
        }
        defaults.set(Array(favoriteIDs), forKey: Keys.favorites)
    }
}

extension PhotoStore: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            self.invalidateAllPools()
            self.refreshLibrary(redeal: false)
        }
    }
}
