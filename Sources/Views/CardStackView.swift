import SwiftUI
import Photos

struct CardStackView: View {
    @ObservedObject var store: PhotoStore
    var onQueuedDelete: () -> Void

    @State private var drag: CGSize = .zero
    @State private var preview: PreviewItem?
    @Namespace private var glass

    private enum FlyOff { case down, right }
    private enum Intent { case delete, next }

    private struct PreviewItem: Identifiable {
        let asset: PHAsset
        var id: String { asset.localIdentifier }
    }

    private static let threshold: CGFloat = 96

    var body: some View {
        GeometryReader { geo in
            let card = Self.cardSize(in: geo.size)
            let layers = [store.card(at: 0), store.card(at: 1), store.card(at: 2)].compactMap { $0 }

            ZStack {
                if !layers.isEmpty {
                    ForEach(Array(layers.enumerated()).reversed(), id: \.element.localIdentifier) { offset, asset in
                        face(asset, at: offset, size: card, front: offset == 0)
                    }
                    .frame(width: card.width, height: card.height)
                } else {
                    EmptyDeckView(store: store)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay(alignment: .bottom) { hintChips }
            .overlay { deleteWash }
        }
        .fullScreenCover(item: $preview) { item in
            VideoPreview(asset: item.asset)
                .ignoresSafeArea()
        }
    }

    // MARK: - 单张卡片

    @ViewBuilder
    private func face(_ asset: PHAsset, at offset: Int, size: CGSize, front: Bool) -> some View {
        let base = ZStack {
            Color.black.opacity(0.25)

            MediaImageView(asset: asset, targetSize: size)
                .frame(width: size.width, height: size.height)
                .clipShape(.rect(cornerRadius: 26))

            if asset.mediaType == .video {
                VStack {
                    Spacer()
                    HStack {
                        Label(Self.durationText(asset.duration), systemImage: "play.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .glassEffect(.regular.tint(.black.opacity(0.35)))
                        Spacer()
                    }
                    .padding(12)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .strokeBorder(.white, lineWidth: 5)
        )
        .shadow(color: .black.opacity(0.35), radius: 16, y: 10)
        .frame(width: size.width, height: size.height)

        if front {
            base
                .offset(drag)
                .rotationEffect(.degrees(Double(drag.width / 22)))
                .gesture(dragGesture)
                .onTapGesture {
                    if asset.mediaType == .video { preview = PreviewItem(asset: asset) }
                }
                .zIndex(3)
        } else {
            let left = offset == 1
            base
                .offset(x: left ? -size.width * 0.54 : size.width * 0.52,
                        y: left ? -12 : 10)
                .rotationEffect(.degrees(left ? -9 : 10))
                .scaleEffect(0.94)
                .zIndex(Double(3 - offset))
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded(release)
    }

    private func release(_ value: DragGesture.Value) {
        let vertical = value.translation.height
        let horizontal = value.translation.width
        if vertical > Self.threshold, vertical > abs(horizontal) * 1.15 {
            fly(.down)
        } else if horizontal > Self.threshold {
            fly(.right)
        } else {
            withAnimation(.spring(duration: 0.35)) { drag = .zero }
        }
    }

    private func fly(_ direction: FlyOff) {
        guard store.current != nil else { return }
        withAnimation(.easeIn(duration: 0.22)) {
            drag = direction == .down
                ? CGSize(width: drag.width, height: 900)
                : CGSize(width: 640, height: drag.height)
        }
        let deleting = direction == .down
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(230))
            withAnimation(.snappy(duration: 0.3)) { drag = .zero }
            if deleting {
                store.mark(.queued)
                onQueuedDelete()
            } else {
                store.skip()
            }
        }
    }

    // MARK: - 手势提示（Liquid Glass）

    private var intent: Intent? {
        if drag.height > 60, drag.height > abs(drag.width) { return .delete }
        if drag.width > 60 { return .next }
        return nil
    }

    @ViewBuilder
    private var hintChips: some View {
        GlassEffectContainer(spacing: 26) {
            HStack(spacing: 26) {
                if intent == .delete {
                    chip("移入待删", systemImage: "arrow.down.to.line", tint: .red, id: "delete")
                }
                if intent == .next {
                    chip("下一张", systemImage: "arrow.right", tint: .green, id: "next")
                }
            }
        }
        .padding(.bottom, 8)
    }

    private func chip(_ text: String, systemImage: String, tint: Color, id: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular.tint(tint).interactive())
            .glassEffectID(id, in: glass)
            .glassEffectTransition(.materialize)
    }

    private var deleteWash: some View {
        LinearGradient(
            colors: [.clear, Color.red.opacity(intent == .delete ? 0.42 : 0)],
            startPoint: .center,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    private static func cardSize(in size: CGSize) -> CGSize {
        let width = min(size.width * 0.66, 330)
        return CGSize(width: width, height: min(width * 1.42, size.height * 0.82))
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        let seconds = total % 60
        return seconds < 10 ? "\(total / 60):0\(seconds)" : "\(total / 60):\(seconds)"
    }
}

struct EmptyDeckView: View {
    @ObservedObject var store: PhotoStore

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text(store.remainingCount > 0 ? "这一批筛完了" : "整个相册都过了一遍")
                .font(.title3.weight(.semibold))
            Text("点下面的按钮继续发牌，或者去统计页清理待删照片。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button("再来 20 张") { store.dealNewDeck() }
                .buttonStyle(.glassProminent)
        }
        .padding(28)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
        .padding(.horizontal, 12)
    }
}
