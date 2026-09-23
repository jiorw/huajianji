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
        case .photo: "照片"
        case .screenshot: "截屏"
        case .video: "视频"
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

/// 分类累计：查看数 / 删除数 / 腾出字节数
struct CleanupStats: Codable {
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
        case .photos: "花间册"
        case .screenshots: "碎影集"
        case .editing: "花影染"
        case .videos: "流光卷"
        case .stats: "岁华簿"
        }
    }

    var symbol: String {
        switch self {
        case .photos: "photo.on.rectangle.angled"
        case .screenshots: "crop.fill"
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

enum BrowseMode: String, CaseIterable, Identifiable {
    case blindBox
    case onThisDay

    var id: String { rawValue }
    var title: String {
        switch self {
        case .blindBox: "随机盲盒"
        case .onThisDay: "回到那天"
        }
    }
}

enum TimeFormat: String, CaseIterable, Identifiable {
    case relative
    case absolute

    var id: String { rawValue }
    var title: String {
        switch self {
        case .relative: "距今"
        case .absolute: "具体日期"
        }
    }
}

enum DoubleTapAction: String, CaseIterable, Identifiable {
    case zoom
    case favorite

    var id: String { rawValue }
    var title: String {
        switch self {
        case .zoom: "放大"
        case .favorite: "收藏"
        }
    }
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
            guard oldValue != tab, tab.mediaType != nil else { return }
            refreshLibrary(redeal: true)
        }
    }

    @Published var mode: BrowseMode {
        didSet {
            guard oldValue != mode else { return }
            defaults.set(mode.rawValue, forKey: Keys.mode)
            refreshLibrary(redeal: true)
        }
    }

    /// 演示模式：走完全流程但不真的删文件
    @Published var demoMode: Bool {
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

    @Published var timeFormat: TimeFormat {
        didSet {
            guard oldValue != timeFormat else { return }
            defaults.set(timeFormat.rawValue, forKey: Keys.timeFormat)
        }
    }

    /// 按用户在设置里选的口径显示拍摄时间
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
    }

    private let defaults = UserDefaults.standard
    private var fetchResult: PHFetchResult<PHAsset>?
    private var verdicts: [String: Verdict] = [:]
    private var undoStack: [String] = []
    private var batchMarked: [String] = []
    private var kindOf: [String: String] = [:]
    /// 当前分类下还没筛过的资源在 fetchResult 里的下标，发牌时直接从这里取
    private var candidates: [Int] = []
    private var tabTotal = 0
    private var persistTask: Task<Void, Never>?
    private var registered = false

    var writable: Bool {
        authorization == .authorized || authorization == .limited
    }

    var current: PHAsset? { card(at: 0) }

    /// 本批 20 张里还剩几张没筛
    var deckRemaining: Int { max(0, deck.count - cursor) }

    func card(at offset: Int) -> PHAsset? {
        let index = cursor + offset
        return deck.indices.contains(index) ? deck[index] : nil
    }

    /// 震动反馈，设置里可以整体关掉
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
        super.init()
        if let data = defaults.data(forKey: Keys.verdicts),
           let saved = try? JSONDecoder().decode([String: Verdict].self, from: data) {
            // 旧版本记录不分栏，键里没有 "|" 前缀，认不出来就直接丢掉重来一组
            verdicts = saved.filter { $0.key.contains("|") }
        }
        if let data = defaults.data(forKey: Keys.stats),
           let saved = try? JSONDecoder().decode(CleanupStats.self, from: data) {
            stats = saved
        }
        if let ids = defaults.stringArray(forKey: Keys.favorites) {
            favoriteIDs = Set(ids)
        }
    }

    // MARK: - 收藏

    func isFavorite(_ id: String) -> Bool { favoriteIDs.contains(id) }

    @discardableResult
    func toggleFavorite(_ asset: PHAsset) -> Bool {
        let id = asset.localIdentifier
        if favoriteIDs.contains(id) {
            favoriteIDs.remove(id)
        } else {
            favoriteIDs.insert(id)
        }
        writeToDisk()
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

    // MARK: - 统计读数

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

    // MARK: - 权限

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

    // MARK: - 批次

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
        fetchResult = currentFetchResult()
        rebuildCandidates()
        if redeal {
            deal()
        } else {
            pruneDeck()
        }
        refreshCounts()
    }

    /// 照片栏 = 所有图片（含截图）；截图栏 = 只有截图；视频栏 = 只有视频
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
        guard verdicts[vkey(asset.localIdentifier)] == nil, matchesTab(asset) else { return false }
        guard mode == .onThisDay else { return true }
        guard let date = asset.creationDate else { return false }
        let calendar = Calendar.current
        let now = calendar.dateComponents([.year, .month, .day], from: Date())
        let then = calendar.dateComponents([.year, .month, .day], from: date)
        return now.month == then.month && now.day == then.day && (then.year ?? 0) < (now.year ?? 0)
    }

    /// 一遍扫完当前分类的可选池，避免每次发牌都全库试探
    private func rebuildCandidates() {
        guard let result = fetchResult else {
            candidates = []
            tabTotal = 0
            return
        }
        var matching = 0
        var fresh: [Int] = []
        result.enumerateObjects { asset, index, _ in
            guard self.matchesTab(asset) else { return }
            matching += 1
            if self.verdicts[self.vkey(asset.localIdentifier)] == nil { fresh.append(index) }
        }
        tabTotal = matching
        if mode == .onThisDay {
            fresh = fresh.filter { eligible(result.object(at: $0)) }
        }
        candidates = fresh
    }

    /// 从相册里随机发一批，数量最多 deckSize 张
    func dealNewDeck() {
        deal()
    }

    /// 从候选池里随机取一组，取走的从池子里摘掉，下一组不会重复
    private func deal() {
        guard let result = fetchResult, !candidates.isEmpty else {
            deck = []
            cursor = 0
            refreshCounts()
            return
        }
        let wanted = min(currentBatchSize, candidates.count)
        var picked: [PHAsset] = []
        picked.reserveCapacity(wanted)
        for _ in 0..<wanted {
            let slot = Int.random(in: 0..<candidates.count)
            picked.append(result.object(at: candidates.remove(at: slot)))
        }
        deck = picked
        cursor = 0
        batchMarked = []
        refreshCounts()
    }

    // MARK: - 首页预览翻页（不产生任何标记）

    var canGoPrevious: Bool { cursor > 0 }
    var canGoNext: Bool { cursor + 1 < deck.count }

    func goNextPreview() {
        guard canGoNext else { return }
        cursor += 1
    }

    func goPreviousPreview() {
        guard canGoPrevious else { return }
        cursor -= 1
    }

    func focus(_ asset: PHAsset) {
        if let position = deck.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) {
            cursor = position
        }
    }

    /// 浏览记录按栏分开存：同一张截图在照片栏和截图栏各算各的
    private func vkey(_ assetID: String) -> String { "\(tab.rawValue)|\(assetID)" }

    private static func realID(from key: String) -> String {
        guard let index = key.firstIndex(of: "|") else { return key }
        return String(key[key.index(after: index)...])
    }

    /// 本批里被标记待删、但还没真正删除的（返回真实 localIdentifier）
    var queuedInBatch: [String] {
        batchMarked.compactMap { verdicts[$0] == .queued ? Self.realID(from: $0) : nil }
    }

    /// 本批里选择保留的张数
    var keptInBatch: Int {
        batchMarked.filter { verdicts[$0] == .kept }.count
    }

    /// 统计页用：把全部待删标记退回，不删任何东西
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
        rebuildCandidates()
        refreshCounts()
    }

    /// 放弃：本批待删标记全部退回，不删任何东西，直接再来一组
    func abandonBatch() {
        for key in batchMarked where verdicts[key] == .queued {
            verdicts.removeValue(forKey: key)
            if let kind = kindOf.removeValue(forKey: key), let current = stats.reviewed[kind] {
                stats.reviewed[kind] = max(0, current - 1)
            }
        }
        undoStack.removeAll()
        batchMarked = []
        writeToDisk()
        rebuildCandidates()
        deal()
    }

    private func pruneDeck() {
        guard !deck.isEmpty else { return }
        let alive = PHAsset.fetchAssets(
            withLocalIdentifiers: deck.map(\.localIdentifier), options: nil)
        var ids = Set<String>()
        alive.enumerateObjects { asset, _, _ in ids.insert(asset.localIdentifier) }
        deck = deck.filter { ids.contains($0.localIdentifier) }
        cursor = min(cursor, max(deck.count - 1, 0))
        if deck.isEmpty { deal() }
    }

    // MARK: - 筛选

    /// 全屏筛选页标记一张：.queued 待删 / .kept 看过保留
    func mark(_ verdict: Verdict, asset: PHAsset) {
        let key = vkey(asset.localIdentifier)
        guard verdicts[key] == nil else { return }
        verdicts[key] = verdict
        undoStack.append(key)
        batchMarked.append(key)
        let kind = StatKind(asset: asset).rawValue
        kindOf[key] = kind
        stats.reviewed[kind, default: 0] += 1
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
        schedulePersist()
        refreshCounts()
    }

    /// 把待删队列提交给系统相册，之后仍可在「最近删除」找回 30 天
    func commitQueuedDeletions() async {
        let keys = verdicts.compactMap { $0.value == .queued ? $0.key : nil }
        let ids = keys.map(Self.realID)
        guard !ids.isEmpty, !isCommitting else { return }
        isCommitting = true
        defer {
            isCommitting = false
            flush()
        }
        if demoMode {
            // 演示模式：只记账，不碰相册
            for key in keys { verdicts[key] = .deleted }
            undoStack.removeAll()
            refreshLibrary(redeal: true)
            return
        }
        do {
            // 删除前先取回类型和占用体积，删完就读不到了
            let targets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
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
            refreshLibrary(redeal: true)
        } catch {
            errorMessage = "删除没有生效：\(error.localizedDescription)"
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
        writeToDisk()
        refreshLibrary(redeal: true)
    }

    // MARK: - 记录导出 / 导入（自签没有 CloudKit 权限，用文件搬）

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
            .appendingPathComponent("花间集记录-\(Self.stamp()).json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            errorMessage = "导出失败：\(error.localizedDescription)"
            return nil
        }
    }

    func importBackup(from url: URL) {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(BackupPayload.self, from: data) else {
            errorMessage = "这个文件不是花间集导出的记录"
            return
        }
        verdicts = payload.verdicts
        stats = payload.stats
        favoriteIDs = Set(payload.favorites)
        undoStack.removeAll()
        batchMarked = []
        writeToDisk()
        refreshLibrary(redeal: true)
        errorMessage = "已导入 \(payload.verdicts.count) 条浏览记录"
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        return f.string(from: Date())
    }

    // MARK: - 计数与持久化

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

    /// 退到后台时调用，别把攒着的进度丢了
    func flush() {
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
        Task { @MainActor in self.refreshLibrary(redeal: false) }
    }
}
