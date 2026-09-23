import SwiftUI
import Photos

struct CardStackView: View {
    @ObservedObject var store: PhotoStore
    var zoom: Namespace.ID
    var onOpenViewer: (Int) -> Void

    @State private var offset: CGFloat = 0
    @State private var scale: CGFloat = 1

    private static let threshold: CGFloat = 70

    var body: some View {
        GeometryReader { geo in
            let card = Self.cardSize(in: geo.size)
            let layers = [store.card(at: 0), store.card(at: 1), store.card(at: 2)].compactMap { $0 }

            ZStack {
                if layers.isEmpty {
                    EmptyDeckView(store: store)
                } else {
                    ForEach(Array(layers.enumerated()).reversed(), id: \.element.localIdentifier) { index, asset in
                        face(asset, at: index, size: card)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay(alignment: .bottom) { pageHint(card: card) }
        }
    }

    // MARK: - 卡片

    @ViewBuilder
    private func face(_ asset: PHAsset, at index: Int, size: CGSize) -> some View {
        let front = index == 0
        let base = ZStack {
            Color.black.opacity(0.25)

            MediaImageView(asset: asset, targetSize: size)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 26))

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
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white, lineWidth: 5))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 10)
        .frame(width: size.width, height: size.height)

        if front {
            base
                .offset(x: offset, y: 0)
                .scaleEffect(scale)
                .rotationEffect(.degrees(Double(offset / 34)))
                .matchedTransitionSource(id: asset.localIdentifier, in: zoom)
                .onTapGesture { onOpenViewer(store.cursor) }
                .gesture(paging)
                .zIndex(3)
        } else {
            let left = index == 1
            base
                .offset(x: left ? -size.width * 0.54 : size.width * 0.52,
                        y: left ? -12 : 10)
                .rotationEffect(.degrees(left ? -9 : 10))
                .scaleEffect(0.94)
                .zIndex(Double(3 - index))
        }
    }

    /// 右滑 = 下一张，左滑 = 上一张；只用横向位移，带惯性
    private var paging: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = value.translation.width
                scale = 1 - min(abs(offset) / 1400, 0.06)
            }
            .onEnded { value in
                let projected = value.predictedEndTranslation.width
                if projected > Self.threshold * 2.2 || value.translation.width > 120 {
                    turnPage(forward: true)
                } else if projected < -Self.threshold * 2.2 || value.translation.width < -120 {
                    turnPage(forward: false)
                } else {
                    withAnimation(.spring(duration: 0.42, bounce: 0.28)) {
                        offset = 0
                        scale = 1
                    }
                }
            }
    }

    private func turnPage(forward: Bool) {
        let allowed = forward ? store.canGoNext : store.canGoPrevious
        let target: CGFloat = forward ? 520 : -520
        if allowed {
            withAnimation(.easeOut(duration: 0.2)) { offset = target }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                if forward { store.goNextPreview() } else { store.goPreviousPreview() }
                // 新到前面的卡片从另一侧回弹入场
                offset = -target
                scale = 0.93
                withAnimation(.spring(duration: 0.5, bounce: 0.3)) {
                    offset = 0
                    scale = 1
                }
            }
        } else {
            // 到头了：橡皮筋回弹
            withAnimation(.spring(duration: 0.5, bounce: 0.42)) {
                offset = forward ? 34 : -34
                scale = 1
            }
            withAnimation(.spring(duration: 0.4, bounce: 0.3).delay(0.12)) { offset = 0 }
        }
    }

    // MARK: - 底部页码

    @ViewBuilder
    private func pageHint(card: CGSize) -> some View {
        HStack(spacing: 10) {
            if store.canGoPrevious {
                Label("上一张", systemImage: "arrow.left")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            Text("\(store.cursor + 1) / \(store.deck.count)")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.7))
                .glassEffect(.regular.tint(.black.opacity(0.28)), in: .rect(cornerRadius: 12))
                .padding(.horizontal, 4)
            Spacer()
            if store.canGoNext {
                Label("下一张", systemImage: "arrow.right")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 6)
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
            Text(store.remainingCount > 0 ? "这一批发完了" : "整个相册都过了一遍")
                .font(.title3.weight(.semibold))
            Text("点下面的按钮继续发牌，或者去岁华簿清理待删照片。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button("再来 \(store.currentBatchSize) 张") { store.dealNewDeck() }
                .buttonStyle(.glassProminent)
        }
        .padding(28)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
        .padding(.horizontal, 12)
    }
}
