import SwiftUI
import Photos
import UIKit

/// 全屏放大筛选：双击/捏合缩放，照片左右滑切换、上滑删除；视频上下滑切换并自动播放
struct PhotoViewerView: View {
    @ObservedObject var store: PhotoStore
    @Environment(\.dismiss) private var dismiss

    let startIndex: Int

    @StateObject private var playback = FeedPlayback()

    @State private var index = 0
    @State private var drag: CGSize = .zero
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var lastPan: CGSize = .zero
    @State private var finished = false
    @State private var showInfo = false
    @State private var livePlaying = false

    private static let swipeThreshold: CGFloat = 96

    private var asset: PHAsset? { store.deck.indices.contains(index) ? store.deck[index] : nil }
    private var isVideo: Bool { asset?.mediaType == .video }
    private var isLive: Bool { asset?.mediaSubtypes.contains(.photoLive) ?? false }
    private var zoomed: Bool { zoom > 1.02 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.95).ignoresSafeArea()

                if let asset {
                    if isVideo {
                        PlayerUIView(player: playback.player)
                            .offset(drag)
                            .gesture(dragGesture)
                            .id(asset.localIdentifier)
                    } else if isLive {
                        LivePhotoView(asset: asset, playing: livePlaying)
                            .offset(drag)
                            .gesture(dragGesture)
                            .onLongPressGesture(minimumDuration: 0.25, pressing: { pressing in
                                livePlaying = pressing
                            }, perform: {})
                            .id(asset.localIdentifier)
                    } else {
                        MediaImageView(asset: asset, targetSize: geo.size, contentMode: .fit)
                            .scaleEffect(zoom)
                            .offset(x: drag.width + pan.width,
                                    y: drag.height + pan.height)
                            .rotationEffect(.degrees(zoomed ? 0 : Double(drag.width / 46)))
                            .gesture(dragGesture)
                            .simultaneousGesture(pinchGesture)
                            .onTapGesture(count: 2) { toggleZoom() }
                            .id(asset.localIdentifier)
                    }
                }

                VStack(spacing: 0) {
                    header
                    Spacer()
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

    // MARK: - 顶栏

    private var header: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.glass)

            Spacer(minLength: 4)

            VStack(spacing: 3) {
                Text("\(min(index + 1, store.deck.count)) / \(store.deck.count)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text("待删 \(store.queuedInBatch.count)")
                    .font(.caption2)
                    .foregroundStyle(store.queuedInBatch.isEmpty ? Color.white.opacity(0.55) : Color.red)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))

            Spacer(minLength: 4)

            if isVideo {
                Button { playback.toggleMute() } label: {
                    Image(systemName: playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.glass)
            }

            Button { showInfo = true } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.glass)

            Button { favoriteTapped() } label: {
                Image(systemName: favorited ? "heart.fill" : "heart")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(favorited ? Color.red : .white)
                    .frame(width: 38, height: 38)
                    .scaleEffect(favorited ? 1.12 : 1)
                    .animation(.spring(duration: 0.35, bounce: 0.5), value: favorited)
            }
            .buttonStyle(.glass)
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
        let generator = UIImpactFeedbackGenerator(style: added ? .medium : .light)
        generator.impactOccurred()
    }

    // MARK: - 底栏

    private var footer: some View {
        VStack(spacing: 10) {
            if let asset {
                Text(TimeText.since(asset.creationDate))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text(TimeText.precise(asset.creationDate))
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
        if delete {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
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
