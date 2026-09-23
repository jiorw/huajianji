import SwiftUI
import Photos

/// 全屏放大筛选：双击/捏合缩放，照片左右滑切换、上滑删除；视频上下滑切换
struct PhotoViewerView: View {
    @ObservedObject var store: PhotoStore
    @Environment(\.dismiss) private var dismiss

    let startIndex: Int

    @State private var index = 0
    @State private var drag: CGSize = .zero
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var lastPan: CGSize = .zero
    @State private var finished = false

    private static let swipeThreshold: CGFloat = 96

    private var asset: PHAsset? { store.deck.indices.contains(index) ? store.deck[index] : nil }
    private var isVideo: Bool { asset?.mediaType == .video }
    private var zoomed: Bool { zoom > 1.02 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.95).ignoresSafeArea()

                if let asset {
                    MediaImageView(asset: asset, targetSize: geo.size, contentMode: .fit)
                        .scaleEffect(zoom)
                        .offset(x: drag.width + pan.width,
                                y: drag.height + pan.height)
                        .rotationEffect(.degrees(zoomed ? 0 : Double(drag.width / 46)))
                        .gesture(zoomed ? panGesture : swipeGesture)
                        .simultaneousGesture(pinchGesture)
                        .onTapGesture(count: 2) { toggleZoom(in: geo.size) }
                        .id(asset.localIdentifier)
                        .animation(.spring(duration: 0.45, bounce: 0.24), value: index)
                }

                VStack(spacing: 0) {
                    header
                    Spacer()
                    footer
                }
            }
        }
        .onAppear { index = startIndex }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $finished) {
            BatchResultSheet(store: store) {
                finished = false
                dismiss()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
    }

    // MARK: - 顶栏 / 底栏

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.glass)

            Spacer()

            VStack(spacing: 3) {
                Text("\(min(index + 1, store.deck.count)) / \(store.deck.count)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text("待删 \(store.queuedInBatch.count)")
                    .font(.caption2)
                    .foregroundStyle(store.queuedInBatch.isEmpty ? Color.white.opacity(0.55) : Color.red)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))

            Spacer()

            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

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

    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                let projected = value.predictedEndTranslation
                let up = projected.height < -460 || value.translation.height < -Self.swipeThreshold * 1.4
                let right = projected.width > 520 || value.translation.width > Self.swipeThreshold * 1.4
                let left = projected.width < -520 || value.translation.width < -Self.swipeThreshold * 1.4
                let down = projected.height > 460 || value.translation.height > Self.swipeThreshold * 1.4

                if isVideo {
                    if up { commit(delete: false, forward: true) }
                    else if down { stepBack() }
                    else if right { commit(delete: true, forward: true) }
                    else { settle() }
                } else {
                    if up { commit(delete: true, forward: true) }
                    else if right { commit(delete: false, forward: true) }
                    else if left { stepBack() }
                    else { settle() }
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                pan = CGSize(width: lastPan.width + value.translation.width,
                             height: lastPan.height + value.translation.height)
            }
            .onEnded { _ in lastPan = pan }
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

    private func toggleZoom(in size: CGSize) {
        withAnimation(.spring(duration: 0.45, bounce: 0.18)) {
            if zoomed {
                zoom = 1
                pan = .zero
            } else {
                zoom = 2.6
            }
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

    private func commit(delete: Bool, forward: Bool) {
        guard let asset else { return }
        let target: CGSize = delete
            ? CGSize(width: drag.width, height: isVideo ? drag.height : -1400)
            : CGSize(width: isVideo ? drag.width : 900, height: isVideo ? -1400 : drag.height)
        withAnimation(.easeOut(duration: 0.22)) { drag = target }
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
