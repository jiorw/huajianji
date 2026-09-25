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
            .contentShape(Rectangle())
            .gesture(paging)
            .task(id: "\(store.cursor)-\(store.card(at: 0)?.localIdentifier ?? "")") {
                // 只提前预取两张，预取太多会和当前这张抢 PhotoKit 的解码额度
                let ahead = [store.card(at: 1), store.card(at: 2)].compactMap { $0 }
                MediaCache.prefetch(ahead, size: card)
            }
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
                .zIndex(3)
        } else {
            // 扇形：后卡缩小一点、往两侧摊开并微微外旋（数值按原版截图像素量出来的）
            let left = index == 1
            base
                .offset(x: left ? -size.width * 0.47 : size.width * 0.47,
                        y: left ? -14 : 8)
                .rotationEffect(.degrees(left ? -7 : 7.5))
                .scaleEffect(0.88)
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

    /// 一段式翻页：飞出去 -> 后卡晋升为前卡，不再从另一侧滑回来
    private func turnPage(forward: Bool) {
        let allowed = forward ? store.canGoNext : store.canGoPrevious
        guard allowed else {
            withAnimation(.spring(duration: 0.4, bounce: 0.35)) { offset = forward ? 24 : -24 }
            withAnimation(.spring(duration: 0.32, bounce: 0.28).delay(0.09)) { offset = 0 }
            return
        }
        let target: CGFloat = forward ? 440 : -440
        withAnimation(.easeOut(duration: 0.17)) { offset = target }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(170))
            withAnimation(.spring(duration: 0.34, bounce: 0.16)) {
                offset = 0
                scale = 1
                if forward { store.goNextPreview() } else { store.goPreviousPreview() }
            }
        }
    }

    // MARK: - 尺寸

    private static func cardSize(in size: CGSize) -> CGSize {
        let width = min(size.width * 0.50, 240)
        return CGSize(width: width, height: min(width * 1.28, size.height * 0.62))
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
            Text(store.remainingCount > 0 ? "这一批发完了"
                 : store.contentFilter == .all ? "整个相册都过了一遍"
                 : "「\(store.contentFilter.title)」这一类里没有可筛的了")
                .font(.title3.weight(.semibold))
            Text(store.remainingCount > 0 ? "正在发下一组…"
                 : "点下面的按钮继续发牌，或者去岁华簿清理待删照片。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            if store.remainingCount == 0 {
                Button("再来 \(store.currentBatchSize) 张") { store.dealNewDeck() }
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(28)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
        .padding(.horizontal, 12)
        .onAppear {
            // 演示模式一组走完自动关闭；普通模式有存货就自动续一批
            if store.demoMode {
                store.endDemo()
            } else if store.remainingCount > 0 {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    store.dealNewDeck()
                }
            }
        }
    }
}
