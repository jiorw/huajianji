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

    private static let swipeThreshold: CGFloat = 96

    private var asset: PHAsset? { store.deck.indices.contains(index) ? store.deck[index] : nil }
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

                VStack(spacing: 0) {
                    header
                    Spacer()
                    navRow
                    footer
                }
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

    private var navRow: some View {
        HStack(spacing: 6) {
            tool("chevron.left", tint: .white.opacity(index > 0 ? 0.95 : 0.28)) { stepBack() }
                .disabled(index == 0)
            tool("trash", tint: .red) { commit(delete: true) }
            tool("chevron.right", tint: .white.opacity(0.95)) { commit(delete: false) }

            Spacer(minLength: 4)

            tool("info.circle", tint: .white.opacity(0.9)) { showInfo = true }

            Button { favoriteTapped() } label: {
                Image(systemName: favorited ? "heart.fill" : "heart")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(favorited ? Color.red : .white)
                    .frame(width: 38, height: 38)
                    .scaleEffect(favorited ? 1.12 : 1)
                    .animation(.spring(duration: 0.35, bounce: 0.5), value: favorited)
            }
            .buttonStyle(.glass)

            if isVideo {
                tool(playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                     tint: .white.opacity(0.9)) { playback.toggleMute() }
            }

            if toolsVisible {
                RoutePickerButton()
                    .frame(width: 38, height: 38)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 19))
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.25), value: toolsVisible)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .opacity(zoomed ? 0 : 1)
    }

    private func tool(_ symbol: String, tint: Color,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
        }
        .buttonStyle(.glass)
    }

    // MARK: - 底栏

    private var footer: some View {
        VStack(spacing: 10) {
            if let asset {
                Text(store.reviewTimeText(for: asset))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text(store.timeFormat == .relative
                     ? TimeText.precise(asset.creationDate)
                     : TimeText.since(asset.creationDate))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }
            HStack {
                if isVideo {
                    Label("上滑 下一个", systemImage: "arrow.up")
                    Spacer()
                    Label("右滑 删除", systemImage: "trash")
                } else if isLive {
                    Label("长按 播放实况", systemImage: "livephoto")
                    Spacer()
                    Label("右滑 下一张 · 上滑 删除", systemImage: "arrow.up.right")
                } else {
                    Label("左滑 上一张", systemImage: "arrow.left")
                    Spacer()
                    Label("右滑 下一张 · 上滑 删除", systemImage: "arrow.up.right")
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 34)
        .padding(.bottom, 26)
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

                if isVideo {
                    if up { commit(delete: false) }
                    else if down { stepBack() }
                    else if right { commit(delete: true) }
                    else { settle() }
                } else {
                    if up { commit(delete: true) }
                    else if right { commit(delete: false) }
                    else if left { stepBack() }
                    else { settle() }
                }
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
        // 照片：删除往上飞、下一张往右飞；视频反过来（上滑是下一个，右滑是删除）
        let flyUp = delete != isVideo
        let target: CGSize = flyUp
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
