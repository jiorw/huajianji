import SwiftUI
import Photos
import UIKit

/// 全屏大图页，布局对齐「去留」：圆角大卡片浮在模糊背景上，
/// 顶栏 = 返回 / 进度条 / 分享，底栏 = 收藏 / 时间胶囊 / 撤销。
/// 手势：左滑上一张、右滑下一张、上滑删除、下滑返回（照片视频同一套）
struct PhotoViewerView: View {
    @ObservedObject var store: PhotoStore
    @Environment(\.dismiss) private var dismiss

    let startIndex: Int

    @StateObject private var playback = FeedPlayback()
    @StateObject private var cast = CastMonitor()

    @State private var index = 0
    @State private var drag: CGSize = .zero
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var lastPan: CGSize = .zero
    @State private var finished = false
    @State private var showInfo = false
    @State private var livePlaying = false
    @State private var toolsVisible = true
    @State private var shareFile: ShareFile?
    @State private var pendingExit = false
    @State private var fullscreenVideo = false

    /// sheet(item:) 要 Identifiable，URL 本身不是
    struct ShareFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    init(store: PhotoStore, startIndex: Int) {
        // 首帧就把 index 立到位：等 onAppear 再赋值的话，第一帧会先画 deck[0]，看着像闪错图
        self._store = ObservedObject(wrappedValue: store)
        self.startIndex = startIndex
        self._index = State(initialValue: startIndex)
    }

    private static let swipeThreshold: CGFloat = 96

    private var asset: PHAsset? { store.deck.indices.contains(index) ? store.deck[index] : nil }
    private var currentID: String { asset?.localIdentifier ?? "" }
    private var isVideo: Bool { asset?.mediaType == .video }
    private var isLive: Bool { asset?.mediaSubtypes.contains(.photoLive) ?? false }
    private var zoomed: Bool { zoom > 1.02 }

    /// 顶栏进度条：筛到第几张了
    private var progress: Double {
        guard store.deck.count > 0 else { return 0 }
        return Double(min(index + 1, store.deck.count)) / Double(store.deck.count)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 背景：当前照片放大高斯模糊 + 暗色渐变，卡片浮在上面
                BackdropView(asset: asset)
                    .overlay(
                        LinearGradient(colors: [.black.opacity(0.30),
                                                .black.opacity(0.55),
                                                .black.opacity(0.82)],
                                       startPoint: .top, endPoint: .bottom)
                            .allowsHitTesting(false)
                    )
                    .ignoresSafeArea()

                if isVideo {
                    videoLayer(size: geo.size)
                } else {
                    mediaCard(size: geo.size)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // 手势层铺满整屏：手指不在卡片上也照样能翻
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(dragGesture)
                    .simultaneousGesture(pinchGesture)
                    .onTapGesture(count: 2) { doubleTapped() }
                    .onTapGesture {
                        if fullscreenVideo {
                            exitFullscreenVideo()
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) { toolsVisible.toggle() }
                        }
                    }
                    .task(id: currentID) {
                        // 预取的缓存键必须和前台显示尺寸一模一样，否则翻页必未命中，
                        // 换图就黑屏转圈（上滑删除闪黑屏的元凶）
                        let box = Self.cardSize(in: geo.size)
                        for step in [1, 2] where store.deck.indices.contains(index + step) {
                            let next = store.deck[index + step]
                            if next.mediaType == .video { continue }
                            MediaCache.prefetch([next],
                                                size: Self.fittedSize(asset: next, in: box),
                                                mode: .fit, scale: 3)
                        }
                    }

                if isVideo {
                    // 视频工具列/全屏按钮必须在手势层上方，否则点不到；
                    // 并锁死宽度为屏幕宽，避免被挤出屏幕外
                    if !fullscreenVideo {
                        fullscreenPill(videoHeight: videoHeight(in: geo.size), size: geo.size)
                            .zIndex(9)
                            .opacity(toolsVisible ? 1 : 0)
                            .allowsHitTesting(toolsVisible)
                        videoTools(size: geo.size)
                            .zIndex(9)
                            .opacity(toolsVisible ? 1 : 0)
                            .allowsHitTesting(toolsVisible)
                        videoScrubber
                            .zIndex(9)
                            .opacity(toolsVisible ? 1 : 0)
                            .allowsHitTesting(toolsVisible)
                            .animation(.easeOut(duration: 0.2), value: toolsVisible)
                    }
                    VStack(spacing: 0) {
                        header
                        Spacer()
                        videoFooter
                    }
                    .zIndex(10)
                    .opacity(toolsVisible && !fullscreenVideo ? 1 : 0)
                    .allowsHitTesting(toolsVisible && !fullscreenVideo)
                    .animation(.easeOut(duration: 0.2), value: toolsVisible)
                } else {
                    VStack(spacing: 0) {
                        header
                        Spacer()
                        footer
                    }
                    .zIndex(10)
                    .opacity(toolsVisible && !zoomed ? 1 : 0)
                    .allowsHitTesting(toolsVisible && !zoomed)
                    .animation(.easeOut(duration: 0.2), value: toolsVisible)
                    .animation(.easeOut(duration: 0.2), value: zoomed)
                }
            }
        }
        .onChange(of: isVideo) { _, isV in
            if !isV { exitFullscreenVideo() }
        }
        .onAppear {
            reloadMedia()
        }
        .onChange(of: index) { _, _ in reloadMedia() }
        .onDisappear {
            playback.stop()
            exitFullscreenVideo()
            // 退出时把首页的游标对齐到看到的这张，回首页不会又从旧的那张开始
            if let asset { store.focus(asset) }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showInfo) {
            if let asset { PhotoInfoSheet(asset: asset) }
        }
        .sheet(item: $shareFile) { file in
            ShareSheet(items: [file.url])
        }
        .sheet(isPresented: $pendingExit) {
            PendingDeleteSheet(store: store,
                               onClose: { pendingExit = false },
                               onAbandon: {
                pendingExit = false
                dismiss()
            }, onDeleted: {
                pendingExit = false
                dismiss()
            })
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
            // 毛玻璃：背后的大图能透出模糊的光影
            .presentationBackground(.thinMaterial)
        }
        .sheet(isPresented: $finished) {
            BatchResultSheet(store: store) {
                finished = false
                store.endDemoIfActive()
                dismiss()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationBackground(.thinMaterial)
        }
    }

    private func reloadMedia() {
        zoom = 1
        lastZoom = 1
        pan = .zero
        lastPan = .zero
        drag = .zero
        livePlaying = false
        guard let asset else { return }
        if asset.mediaType == .video {
            playback.load(asset)
        } else {
            playback.stop()
        }
    }

    // MARK: - 卡片

    /// 圆角大卡片：按照片真实比例撑满可用区域（四周固定留白），居中浮在模糊背景上
    @ViewBuilder
    private func mediaCard(size: CGSize) -> some View {
        let box = Self.cardSize(in: size)
        ZStack {
            if let asset {
                if isLive {
                    LivePhotoView(asset: asset, playing: livePlaying)
                        .frame(width: box.width, height: box.height)
                        .clipShape(cardShape)
                        .shadow(color: .black.opacity(0.45), radius: 22, y: 10)
                        .overlay(alignment: .topTrailing) {
                            // 提示这是实况照片：长按播放
                            Text("实况")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .glassEffect(.regular.tint(.black.opacity(0.45)), in: Capsule())
                                .padding(14)
                                .opacity(livePlaying ? 0 : 1)
                        }
                        .rotationEffect(.degrees(Double(drag.width / 60)))
                        .offset(drag)
                        .onLongPressGesture(minimumDuration: 0.25, pressing: { pressing in
                            if pressing { store.bump(.light) }
                            livePlaying = pressing
                        }, perform: {})
                } else {
                    // 必须给出精确尺寸：只给 targetSize 的话视图会吃满整个提案，
                    // 卡片就会溢出屏幕、把底栏全盖住
                    let fit = Self.fittedSize(asset: asset, in: box)
                    if fit.width < box.width * 0.6 {
                        // 超长截图：宽度撑满卡片，纵向滚动看全图，不再缩成一条细条
                        let full = CGSize(width: box.width,
                                          height: box.width * CGFloat(asset.pixelHeight) / CGFloat(max(asset.pixelWidth, 1)))
                        ScrollView(.vertical, showsIndicators: true) {
                            MediaImageView(asset: asset,
                                           targetSize: CGSize(width: full.width,
                                                              height: min(full.height, 3500)),
                                           contentMode: .fit,
                                           requestScale: 1.5)
                                .frame(width: full.width, height: full.height)
                        }
                        .frame(width: box.width, height: box.height)
                        .clipShape(cardShape)
                        .shadow(color: .black.opacity(0.45), radius: 22, y: 10)
                    } else {
                        MediaImageView(asset: asset, targetSize: fit, contentMode: .fit)
                            .frame(width: fit.width, height: fit.height)
                            .clipShape(cardShape)
                            .shadow(color: .black.opacity(0.45), radius: 22, y: 10)
                            .scaleEffect(zoom)
                            .offset(x: pan.width, y: pan.height)
                            .rotationEffect(.degrees(zoomed ? 0 : Double(drag.width / 60)))
                            .offset(drag)
                    }
                }
            }
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
    }

    /// 左右各留 20pt，上下给顶栏底栏让位
    private static func cardSize(in size: CGSize) -> CGSize {
        CGSize(width: size.width - 40, height: size.height - 170)
    }

    /// 按照片像素比例把卡片缩放进可用区域，卡片边界 = 照片边界
    private static func fittedSize(asset: PHAsset, in box: CGSize) -> CGSize {
        let pw = CGFloat(max(asset.pixelWidth, 1))
        let ph = CGFloat(max(asset.pixelHeight, 1))
        var w = box.width
        var h = w * ph / pw
        if h > box.height {
            h = box.height
            w = h * pw / ph
        }
        return CGSize(width: w, height: h)
    }

    // MARK: - 视频页（去留式：全宽铺放 + 右侧工具 + 全屏观看）

    @ViewBuilder
    private func videoLayer(size: CGSize) -> some View {
        if fullscreenVideo {
            PlayerUIView(player: playback.player)
                .frame(width: size.width, height: size.height)
                .clipped()
                .ignoresSafeArea()
        } else {
            PlayerUIView(player: playback.player)
                .frame(width: size.width, height: videoHeight(in: size))
                .clipped()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func videoHeight(in size: CGSize) -> CGFloat {
        var h = size.width / max(videoAspect, 0.01)
        let maxH = size.height * 0.62
        if h > maxH { h = maxH }
        return h
    }

    private var videoAspect: CGFloat {
        guard let asset, asset.pixelWidth > 0 else { return 16.0 / 9.0 }
        return CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
    }

    private func fullscreenPill(videoHeight: CGFloat, size: CGSize) -> some View {
        Button { enterFullscreenVideo() } label: {
            Label("全屏观看", systemImage: "arrow.up.left.and.arrow.down.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .glassEffect(.regular.tint(.black.opacity(0.35)).interactive(), in: Capsule())
        .frame(width: size.width, height: size.height, alignment: .center)
        .offset(y: videoHeight / 2 + 26)
    }

    private func videoTools(size: CGSize) -> some View {
        VStack(spacing: 12) {
            circleButton(favorited ? "heart.fill" : "heart",
                         tint: favorited ? .red : .white) { favoriteTapped() }
            circleButton(playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                playback.toggleMute()
            }
            circleButton("trash", tint: .red) { commit(delete: true) }
            circleButton("arrow.uturn.backward",
                         tint: store.canUndo ? .white : .white.opacity(0.35)) { undoTapped() }
                .disabled(!store.canUndo)
        }
        .frame(width: size.width, height: size.height, alignment: .bottomTrailing)
        .padding(.trailing, 16)
        .padding(.bottom, 120)
    }

    private var videoFooter: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                if let asset {
                    Text(store.reviewTimeText(for: asset))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(TimeText.precise(asset.creationDate))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
    }

    private var videoProgress: Double {
        playback.duration > 0 ? min(max(playback.currentTime / playback.duration, 0), 1) : 0
    }

    private var videoScrubber: some View {
        Capsule()
            .fill(.white.opacity(0.25))
            .frame(height: 3)
            .overlay(alignment: .leading) {
                GeometryReader { g in
                    Capsule()
                        .fill(.white)
                        .frame(width: max(4, g.size.width * videoProgress))
                        .contentShape(Rectangle().inset(by: -12))
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            let p = min(max(value.location.x / max(g.size.width, 1), 0), 1)
                            playback.seek(to: p * playback.duration)
                        })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
    }

    private func enterFullscreenVideo() {
        fullscreenVideo = true
        VideoFullscreen.setLandscape(true)
    }

    private func exitFullscreenVideo() {
        guard fullscreenVideo else { return }
        fullscreenVideo = false
        VideoFullscreen.setLandscape(false)
    }

    // MARK: - 顶栏：返回 / 进度条 / 分享

    private var header: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                circleButton("chevron.left") { leaveViewer() }
                Spacer()
                circleButton("square.and.arrow.up") { shareTapped() }
            }
            // 一张张筛到哪了：短细线居中，别横贯整屏
            Capsule()
                .fill(.white.opacity(0.18))
                .frame(height: 3)
                .frame(maxWidth: 170)
                .overlay(alignment: .leading) {
                    GeometryReader { g in
                        let width = max(10, g.size.width * progress)
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.9)).frame(width: width)
                            Circle()
                                .fill(.white)
                                .frame(width: 8, height: 8)
                                .offset(x: width - 4)
                        }
                        .frame(width: g.size.width, height: g.size.height, alignment: .center)
                    }
                }
                .frame(maxWidth: .infinity)
                .animation(.spring(duration: 0.35, bounce: 0.2), value: index)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func circleButton(_ symbol: String, tint: Color = .white,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 46, height: 46)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .glassEffect(.regular.tint(.black.opacity(0.35)).interactive(), in: Circle())
    }

    // MARK: - 底栏：收藏 / 时间胶囊 / 撤销

    private var favorited: Bool {
        guard let asset else { return false }
        return store.isFavorite(asset.localIdentifier)
    }

    private func favoriteTapped() {
        guard let asset else { return }
        let added = store.toggleFavorite(asset)
        store.bump(added ? .medium : .light)
    }

    private func doubleTapped() {
        if isVideo {
            playback.toggleMute()
            return
        }
        switch store.doubleTapAction {
        case .zoom: toggleZoom()
        case .favorite: favoriteTapped()
        }
    }

    private var footer: some View {
        // 两端按钮固定死，中间胶囊再宽也挤不掉它们
        ZStack {
            HStack {
                circleButton(favorited ? "heart.fill" : "heart",
                             tint: favorited ? .red : .white) { favoriteTapped() }
                Spacer()
                circleButton("arrow.uturn.backward",
                             tint: store.canUndo ? .white : .white.opacity(0.35)) { undoTapped() }
                    .disabled(!store.canUndo)
            }
            HStack {
                Spacer()
                infoCapsule
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 18)
    }

    /// 中间的信息胶囊：拍摄时间 + 进度/待删，点开详情（对应原版那个 ⓘ）
    private var infoCapsule: some View {
        Button { showInfo = true } label: {
            HStack(spacing: 12) {
                VStack(spacing: 3) {
                    Text(asset.map { store.reviewTimeText(for: $0) } ?? "")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    HStack(spacing: 5) {
                        Text("\(min(index + 1, store.deck.count)) / \(store.deck.count)")
                            .contentTransition(.numericText(value: Double(min(index + 1, store.deck.count))))
                        if !store.queuedInBatch.isEmpty {
                            Text("待删 \(store.queuedInBatch.count)")
                                .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.42))
                        }
                    }
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                }
                Image(systemName: "info.circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .frame(height: 54)
            .frame(maxWidth: 300)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .glassEffect(.regular.tint(.black.opacity(0.35)).interactive(), in: Capsule())
        .animation(.snappy(duration: 0.3), value: index)
    }

    private func undoTapped() {
        guard store.canUndo else { return }
        store.undoLast()
        store.bump(.light)
        // undoLast 会把游标摆回被撤销那张的位置，直接跟过去
        index = min(store.cursor, max(store.deck.count - 1, 0))
    }

    /// 分享走原始文件：先把 PHAssetResource 落到临时目录再交给系统面板
    private func shareTapped() {
        guard let asset else { return }
        guard let resource = PHAssetResource.assetResources(for: asset).first else {
            store.errorMessage = "这张取不到原始文件，分享不了"
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(resource.originalFilename)
        try? FileManager.default.removeItem(at: url)
        PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: nil) { error in
            Task { @MainActor in
                if let error {
                    store.errorMessage = "分享没准备好：\(error.localizedDescription)"
                } else {
                    shareFile = ShareFile(url: url)
                }
            }
        }
    }

    // MARK: - 手势

    /// 放大状态下拖动=平移看图，未放大时拖动=翻页/删除
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if zoomed {
                    pan = CGSize(width: lastPan.width + value.translation.width,
                                 height: lastPan.height + value.translation.height)
                } else {
                    drag = value.translation
                }
            }
            .onEnded { value in
                if zoomed {
                    lastPan = pan
                    return
                }
                let projected = value.predictedEndTranslation
                let up = projected.height < -460 || value.translation.height < -Self.swipeThreshold * 1.4
                let right = projected.width > 520 || value.translation.width > Self.swipeThreshold * 1.4
                let left = projected.width < -520 || value.translation.width < -Self.swipeThreshold * 1.4
                let down = projected.height > 460 || value.translation.height > Self.swipeThreshold * 1.4

                // 照片和视频走同一套：左上一张 / 右下一张 / 上删除 / 下退回三卡首页
                if up { commit(delete: true) }
                else if right { commit(delete: false) }
                else if left { stepBack() }
                else if down { leaveViewer() }
                else { settle() }
            }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = min(max(lastZoom * value.magnification, 1), 5)
            }
            .onEnded { _ in
                lastZoom = zoom
                if zoom < 1.05 {
                    withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
                        zoom = 1
                        lastZoom = 1
                        pan = .zero
                        lastPan = .zero
                    }
                }
            }
    }

    private func toggleZoom() {
        withAnimation(.spring(duration: 0.45, bounce: 0.18)) {
            zoom = zoomed ? 1 : 2.6
            if zoomed { pan = .zero }
            lastZoom = zoom
            lastPan = pan
        }
    }

    private func settle() {
        withAnimation(.spring(duration: 0.45, bounce: 0.3)) { drag = .zero }
    }

    private func stepBack() {
        guard index > 0 else { settle(); return }
        settle()
        index -= 1
    }

    /// 手里还攥着待删的照片时不让直接走，先弹一张「有待删除的照片」
    private func leaveViewer() {
        guard !store.queuedInBatch.isEmpty else { dismiss(); return }
        settle()
        pendingExit = true
    }

    private func commit(delete: Bool) {
        guard let asset else { return }
        if fullscreenVideo { exitFullscreenVideo() }
        // 删除往上飞，下一张往右飞
        let target: CGSize = delete
            ? CGSize(width: drag.width, height: -1400)
            : CGSize(width: 900, height: drag.height)
        withAnimation(.easeOut(duration: 0.2)) { drag = target }
        if delete { store.bump(.heavy) }
        Task { @MainActor in
            // 飞行动画 0.2s，这里多留 60ms 余量，等动画彻底收尾再原子换图，
            // 否则旧图会有一帧弹回画面中央（上滑闪烁的元凶）
            try? await Task.sleep(for: .milliseconds(260))
            // 等飞行动画收尾后再同一个事务里换人：drag 归零 + index 前进同时生效，
            // 中间不会露出旧图或空白；下一张已经预取过，切过去就是即时的
            store.mark(delete ? .queued : .kept, asset: asset)
            drag = .zero
            if index + 1 < store.deck.count {
                index += 1
                if store.deck.indices.contains(index) { store.focus(store.deck[index]) }
            } else {
                finished = true
            }
        }
    }
}

/// 系统分享面板
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
