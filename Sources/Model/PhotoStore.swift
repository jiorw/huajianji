import Foundation
import Photos

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
    case videos
    case stats

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .photos: "照片"
        case .videos: "视频"
        case .stats: "统计"
        }
    }

    var symbol: String {
        switch self {
        case .photos: "photo.on.rectangle.angled"
        case .videos: "play.rectangle.fill"
        case .stats: "chart.bar.xaxis"
        }
    }

    var mediaType: PHAssetMediaType? {
        switch self {
        case .photos: .image
        case .videos: .video
        case .stats: nil
        }
    }
}

struct AlbumEntry: Identifiable, Hashable {
    let id: String
    let title: String
    let estimatedCount: Int

    static func == (lhs: AlbumEntry, rhs: AlbumEntry) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@MainActor
final class PhotoStore: NSObject, ObservableObject {

    static let deckSize = 20

    @Published private(set) var authorization: PHAuthorizationStatus = .notDetermined
    @Published private(set) var deck: [PHAsset] = []
    @Published private(set) var cursor: Int = 0
    @Published private(set) var reviewedCount = 0
    @Published private(set) var queuedCount = 0
    @Published private(set) var deletedCount = 0
    @Published private(set) var remainingCount = 0
    @Published private(set) var libraryCount = 0
    @Published private(set) var canUndo = false
    @Published private(set) var isCommitting = false
    @Published private(set) var stats = CleanupStats()
    @Published var errorMessage: String?

    @Published var tab: RootTab = .photos {
        didSet {
            guard oldValue != tab, tab.mediaType != nil else { return }
            refreshLibrary(redeal: true)
        }
    }

    /// nil 表示「所有照片」
    @Published var albumID: String? {
        didSet {
            guard oldValue != albumID else { return }
            refreshLibrary(redeal: true)
        }
    }

    private enum Keys {
        static let verdicts = "zhaohuaxishi.verdicts.v1"
        static let stats = "zhaohuaxishi.stats.v1"
    }

    private let defaults = UserDefaults.standard
    private var fetchResult: PHFetchResult<PHAsset>?
    private var verdicts: [String: Verdict] = [:]
    private var undoStack: [String] = []
    private var batchMarked: [String] = []
    private var kindOf: [String: String] = [:]
    private var tabReviewed = 0
    private var persistTask: Task<Void, Never>?
    private var registered = false

    var writable: Bool {
        authorization == .authorized || authorization == .limited
    }

    var albumTitle: String {
        guard let albumID,
              let collection = PHAssetCollection.fetchAssetCollections(
                  withLocalIdentifiers: [albumID], options: nil).firstObject,
              let name = collection.localizedTitle, !name.isEmpty else {
            return tab.title
        }
        return name
    }

    var current: PHAsset? { card(at: 0) }

    /// 本批 20 张里还剩几张没筛
    var deckRemaining: Int { max(0, deck.count - cursor) }

    func card(at offset: Int) -> PHAsset? {
        let index = cursor + offset
        return deck.indices.contains(index) ? deck[index] : nil
    }

    override init() {
        super.init()
        if let data = defaults.data(forKey: Keys.verdicts),
           let saved = try? JSONDecoder().decode([String: Verdict].self, from: data) {
            verdicts = saved
        }
        if let data = defaults.data(forKey: Keys.stats),
           let saved = try? JSONDecoder().decode(CleanupStats.self, from: data) {
            stats = saved
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
        let options = fetchOptions()
        if let albumID,
           let collection = PHAssetCollection.fetchAssetCollections(
               withLocalIdentifiers: [albumID], options: nil).firstObject {
            return PHAsset.fetchAssets(in: collection, options: options)
        }
        return PHAsset.fetchAssets(with: options)
    }

    private func refreshLibrary(redeal: Bool) {
        guard writable else { return }
        fetchResult = currentFetchResult()
        recountTabReviewed()
        if redeal {
            deal()
        } else {
            pruneDeck()
        }
        refreshCounts()
    }

    /// 只统计当前这个 tab（照片 / 视频）里已经筛过的数量
    private func recountTabReviewed() {
        guard let result = fetchResult else {
            tabReviewed = 0
            return
        }
        var count = 0
        result.enumerateObjects { asset, _, _ in
            if self.verdicts[asset.localIdentifier] != nil { count += 1 }
        }
        tabReviewed = count
    }

    /// 从相册里随机发一批，数量最多 deckSize 张
    func dealNewDeck() {
        deal()
    }

    private func deal() {
        guard let result = fetchResult, result.count > 0 else {
            deck = []
            cursor = 0
            refreshCounts()
            return
        }
        var picked: [PHAsset] = []
        var taken = Set<String>()
        var attempts = 0
        let ceiling = result.count
        while picked.count < Self.deckSize, attempts < Self.deckSize * 50 {
            attempts += 1
            let asset = result.object(at: Int.random(in: 0..<ceiling))
            let id = asset.localIdentifier
            guard verdicts[id] == nil, !taken.contains(id) else { continue }
            taken.insert(id)
            picked.append(asset)
        }
        // 库里剩下的不多了，随机试不出来就顺序补齐
        if picked.count < Self.deckSize {
            for index in 0..<ceiling {
                if picked.count >= Self.deckSize { break }
                let asset = result.object(at: index)
                let id = asset.localIdentifier
                guard verdicts[id] == nil, !taken.contains(id) else { continue }
                taken.insert(id)
                picked.append(asset)
            }
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

    /// 本批里被标记待删、但还没真正删除的
    var queuedInBatch: [String] {
        batchMarked.filter { verdicts[$0] == .queued }
    }

    /// 统计页用：把全部待删标记退回，不删任何东西
    func discardAllQueued() {
        let snapshot = verdicts
        for (id, verdict) in snapshot where verdict == .queued {
            verdicts.removeValue(forKey: id)
            if let kind = kindOf.removeValue(forKey: id), let current = stats.reviewed[kind] {
                stats.reviewed[kind] = max(0, current - 1)
            }
            tabReviewed = max(0, tabReviewed - 1)
        }
        undoStack.removeAll()
        batchMarked = []
        writeToDisk()
        refreshCounts()
    }

    /// 放弃：本批待删标记全部退回，不删任何东西，直接再来一组
    func abandonBatch() {
        for id in batchMarked where verdicts[id] == .queued {
            verdicts.removeValue(forKey: id)
            if let kind = kindOf.removeValue(forKey: id), let current = stats.reviewed[kind] {
                stats.reviewed[kind] = max(0, current - 1)
            }
            tabReviewed = max(0, tabReviewed - 1)
        }
        undoStack.removeAll()
        batchMarked = []
        writeToDisk()
        refreshCounts()
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
        let id = asset.localIdentifier
        guard verdicts[id] == nil else { return }
        verdicts[id] = verdict
        undoStack.append(id)
        batchMarked.append(id)
        let kind = StatKind(asset: asset).rawValue
        kindOf[id] = kind
        stats.reviewed[kind, default: 0] += 1
        tabReviewed += 1
        schedulePersist()
        refreshCounts()
    }

    func undoLast() {
        guard let id = undoStack.popLast() else { return }
        verdicts.removeValue(forKey: id)
        batchMarked.removeAll { $0 == id }
        if let kind = kindOf.removeValue(forKey: id), let current = stats.reviewed[kind] {
            stats.reviewed[kind] = max(0, current - 1)
        }
        tabReviewed = max(0, tabReviewed - 1)
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
        let ids = verdicts.compactMap { $0.value == .queued ? $0.key : nil }
        guard !ids.isEmpty, !isCommitting else { return }
        isCommitting = true
        defer {
            isCommitting = false
            flush()
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
            for id in ids { verdicts[id] = .deleted }
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

    // MARK: - 相册列表

    nonisolated func albums() -> [AlbumEntry] {
        var list = [AlbumEntry(id: "", title: "所有照片", estimatedCount: 0)]
        let result = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        result.enumerateObjects { collection, _, _ in
            let title = collection.localizedTitle ?? "未命名相簿"
            let count = collection.estimatedAssetCount
            list.append(AlbumEntry(id: collection.localIdentifier, title: title, estimatedCount: count))
        }
        return list
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
        reviewedCount = verdicts.count
        libraryCount = fetchResult?.count ?? 0
        remainingCount = max(0, libraryCount - tabReviewed)
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
    }
}

extension PhotoStore: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in self.refreshLibrary(redeal: false) }
    }
}
