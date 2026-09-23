import SwiftUI
import Photos

/// 全屏放大筛选：上滑删除、右滑下一张，本组筛完弹结果页
struct PhotoViewerView: View {
    @ObservedObject var store: PhotoStore
    @Environment(\.dismiss) private var dismiss

    let startIndex: Int

    @State private var index = 0
    @State private var drag: CGSize = .zero
    @State private var finished = false

    private static let upThreshold: CGFloat = 110
    private static let rightThreshold: CGFloat = 110

    private var asset: PHAsset? { store.deck.indices.contains(index) ? store.deck[index] : nil }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.94).ignoresSafeArea()

                if let asset {
                    MediaImageView(asset: asset, targetSize: geo.size, contentMode: .fit)
                        .offset(x: drag.width, y: drag.height)
                        .scaleEffect(1 - min(abs(drag.height) / 4000, 0.08))
                        .rotationEffect(.degrees(Double(drag.width / 46)))
                        .gesture(swipe)
                        .id(asset.localIdentifier)
                }

                VStack(spacing: 0) {
                    header
                    Spacer()
                    legend
                        .padding(.bottom, 26)
                }
            }
            .overlay { wash }
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

    // MARK: - 顶栏

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

    private var legend: some View {
        HStack {
            Label("右滑 下一张", systemImage: "arrow.right")
            Spacer()
            Label("上滑 删除", systemImage: "arrow.up")
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.white.opacity(0.55))
        .padding(.horizontal, 34)
    }

    // MARK: - 手势

    private var swipe: some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                let up = value.translation.height < -Self.upThreshold
                    || value.predictedEndTranslation.height < -420
                let right = value.translation.width > Self.rightThreshold
                    || value.predictedEndTranslation.width > 520
                if up {
                    commit(delete: true)
                } else if right {
                    commit(delete: false)
                } else {
                    withAnimation(.spring(duration: 0.45, bounce: 0.3)) { drag = .zero }
                }
            }
    }

    private func commit(delete: Bool) {
        guard let asset else { return }
        let target: CGSize = delete
            ? CGSize(width: drag.width, height: -1400)
            : CGSize(width: 900, height: drag.height)
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

    // MARK: - 方向提示

    private enum Intent { case delete, next, none }

    private var intent: Intent {
        if drag.height < -50 && abs(drag.height) > abs(drag.width) { return .delete }
        if drag.width > 50 { return .next }
        return .none
    }

    @ViewBuilder
    private var wash: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Color.red.opacity(intent == .delete ? 0.5 : 0), .clear],
                           startPoint: .top, endPoint: .center)
            Spacer()
            LinearGradient(colors: [.clear, Color.green.opacity(intent == .next ? 0.35 : 0)],
                           startPoint: .center, endPoint: .bottom)
        }
        .allowsHitTesting(false)
    }
}
