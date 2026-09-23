import SwiftUI
import Photos
import UIKit

/// 全屏放大筛选：双击/捏合缩放，照片左右滑切换、上滑删除；视频上下滑切换并自动播放
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
    @State private var toolsVisible = false
    @State private var shareFile: ShareFile?

    /// sheet(item:) 要 Identifiable，URL 本身不是
    struct ShareFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    private static let swipeThreshold: CGFloat = 96

    private var asset: PHAsset? { store.deck.indices.contains(index) ? store.deck[index] : nil }
    private var currentID: String { asset?.localIdentifier ?? "" }
    private var isVideo: Bool { asset?.mediaType == .video }
    private var isLive: Bool { asset?.mediaSubtypes.contains(.photoLive) ?? false }
    private var zoomed: Bool { zoom > 1.02 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.95).ignoresSafeArea()

                mediaLayer(size: geo.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(dragGesture)
                    .onTapGesture(count: 2) { doubleTapped() }
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) { toolsVisible.toggle() }
                    }
                    .animation(.easeOut(duration: 0.26), value: currentID)
                    .task(id: currentID) {
                        // 提前把下一张按同样的缓存键拉好，翻过去就当帧出图，不闪空白
                        let next = index + 1 < store.deck.count ? store.deck[index + 1] : nil
                        if let next {
                            MediaCache.prefetch([next], size: geo.size, mode: .fit, scale: 3)
                        }
                    }

                VStack(spacing: 0) {
                    header
                    Spacer()
                    footer
                }

                sideTools
            }
        }
        .onAppear {
            index = startIndex
            reloadMedia()
        }
        .onChange(of: index) { _, _ in reloadMedia() }
        .onDisappear { playback.stop() }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showInfo) {
            if let asset { PhotoInfoSheet(asset: asset) }
        }
        .sheet(item: $shareFile) { file in
            ShareSheet(items: [file.url])
        }
        .sheet(isPresented: $finished) {
            BatchResultSheet(store: store) {
                finished = false
                dismiss()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
    }

    private func reloadMedia() {
        toolsVisible = false
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

    // MARK: - 画面层

    @ViewBuilder
    private func mediaLayer(size: CGSize) -> some View {
        if let asset {
            if isVideo {
                PlayerUIView(player: playback.player)
                    .offset(drag)
            } else if isLive {
                LivePhotoView(asset: asset, playing: livePlaying)
                    .offset(drag)
                    .onLongPressGesture(minimumDuration: 0.25, pressing: { pressing in
                        livePlaying = pressing
                    }, perform: {})
            } else {
                MediaImageView(asset: asset, targetSize: size, contentMode: .fit)
                    .id(asset.localIdentifier)
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
                    .scaleEffect(zoom)
                    .offset(x: drag.width + pan.width, y: drag.height + pan.height)
                    .rotationEffect(.degrees(zoomed ? 0 : Double(drag.width / 46)))
                    .simultaneousGesture(pinchGesture)
            }
        }
    }

    // MARK: - 顶栏

    private var header: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.glass)

            Spacer(minLength: 6)

            HStack(spacing: 8) {
                Text("\(min(index + 1, store.deck.count)) / \(store.deck.count)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Circle().fill(store.queuedInBatch.isEmpty
                             ? Color.white.opacity(0.3) : Color.red)
                    .frame(width: 6, height: 6)
                Text("待删 \(store.queuedInBatch.count)")
                    .font(.caption)
                    .foregroundStyle(store.queuedInBatch.isEmpty
                                     ? Color.white.opacity(0.55) : Color.red)
            }
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))

            Spacer(minLength: 6)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .opacity(zoomed ? 0 : 1)
    }

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
        switch store.doubleTapAction {
        case .zoom: toggleZoom()
        case .favorite: favoriteTapped()
        }
    }

    /// 右侧竖排的透明玻璃工具列，和原版一样四个：收藏 / 分享 / 删除 / 撤销
    private var sideTools: some View {
        VStack(spacing: 12) {
            tool(favorited ? "heart.fill" : "heart",
                 tint: favorited ? .red : .white) { favoriteTapped() }

            tool("square.and.arrow.up", tint: .white.opacity(0.92)) { shareTapped() }

            tool("trash", tint: .red) { commit(delete: true) }

            tool("arrow.uturn.backward", tint: .white.opacity(0.92),
                 enabled: store.canUndo) { undoTapped() }

            if isVideo {
                tool(playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                     tint: .white.opacity(0.92)) { playback.toggleMute() }
            }

            if toolsVisible {
                RoutePickerButton()
                    .frame(width: 46, height: 46)
                    .glassEffect(.regular.tint(.black.opacity(0.42)).interactive(), in: Circle())
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.25), value: toolsVisible)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, 16)
        .padding(.bottom, 200)
        .opacity(zoomed ? 0 : 1)
        .allowsHitTesting(!zoomed)
    }

    private func tool(_ symbol: String, tint: Color, enabled: Bool = true,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 46, height: 46)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(.black.opacity(0.42)).interactive(), in: Circle())
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
    }

    private func undoTapped() {
        guard store.canUndo else { return }
        store.undoLast()
        store.bump(.light)
        if index > 0 { index -= 1 }
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

    // MARK: - 底栏

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let asset {
                // 左下角时间行，点一下才展开详情（对应原版那个 ⌄）
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.reviewTimeText(for: asset))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                    HStack(spacing: 5) {
                        Text(store.timeFormat == .relative
                             ? TimeText.precise(asset.creationDate)
                             : TimeText.since(asset.creationDate))
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.trailing, 14)
                .contentShape(Rectangle())
                .onTapGesture { showInfo = true }
            }
            HStack {
                Label(isLive ? "长按 播放实况" : "左滑 上一张",
                      systemImage: isLive ? "livephoto" : "arrow.left")
                Spacer()
                Label("右滑 下一张 · 上滑 删除 · 下滑 返回", systemImage: "arrow.up.arrow.down")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 34)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(zoomed ? 0 : 1)
        .animation(.easeOut(duration: 0.2), value: zoomed)
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
                else if down { dismiss() }
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

    private func commit(delete: Bool) {
        guard let asset else { return }
        // 删除往上飞，下一张往右飞
        let target: CGSize = delete
            ? CGSize(width: drag.width, height: -1400)
            : CGSize(width: 900, height: drag.height)
        withAnimation(.easeOut(duration: 0.22)) { drag = target }
        if delete { store.bump(.heavy) }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            store.mark(delete ? .queued : .kept, asset: asset)
            drag = .zero
            if index + 1 < store.deck.count {
                index += 1
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
