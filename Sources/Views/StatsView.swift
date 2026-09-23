import SwiftUI

struct StatsView: View {
    @ObservedObject var store: PhotoStore

    @State private var confirmCommit = false
    @State private var confirmReset = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                GlassEffectContainer(spacing: 14) {
                    VStack(spacing: 14) {
                        HStack(spacing: 14) {
                            tile("已筛选", value: store.reviewedCount, symbol: "checkmark.circle.fill")
                            tile("待删除", value: store.queuedCount, symbol: "trash.circle.fill", tint: .red)
                        }
                        HStack(spacing: 14) {
                            tile("已删除", value: store.deletedCount, symbol: "xmark.circle.fill")
                            tile("未筛选", value: store.remainingCount, symbol: "hourglass")
                        }
                    }
                }

                VStack(spacing: 12) {
                    Button {
                        confirmCommit = true
                    } label: {
                        Label("立即删除待删的 \(store.queuedCount) 张", systemImage: "trash")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.red)
                    .disabled(store.queuedCount == 0 || store.isCommitting)

                    HStack(spacing: 12) {
                        Button {
                            store.undoLast()
                        } label: {
                            Label("撤销", systemImage: "arrow.uturn.backward")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.glass)
                        .disabled(!store.canUndo)

                        Button {
                            store.dealNewDeck()
                        } label: {
                            Label("重新发牌", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.glass)
                    }

                    Button {
                        confirmReset = true
                    } label: {
                        Label("重置筛选记录", systemImage: "exclamationmark.arrow.circlepath")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                    .tint(.orange)
                }
                .padding(18)
                .glassEffect(.regular, in: .rect(cornerRadius: 28))

                Text("下滑只会把照片放进入待删队列，相册不会有任何变化；点「立即删除」才会真的删除。删掉的照片还能在系统相册的「最近删除」里找回 30 天。所有记录都存在本机。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
        .confirmationDialog(
            "真的删除这 \(store.queuedCount) 张？",
            isPresented: $confirmCommit,
            titleVisibility: .visible
        ) {
            Button("从相册删除", role: .destructive) {
                Task { await store.commitQueuedDeletions() }
            }
            Button("再想想", role: .cancel) {}
        } message: {
            Text("删除后会进入系统相册的「最近删除」，30 天内还能找回。")
        }
        .confirmationDialog("确定重置？", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("重置筛选记录", role: .destructive) { store.resetProgress() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只清空「哪些看过 / 哪些待删」的记录，不会删除任何照片。")
        }
    }

    private func tile(_ label: String, value: Int, symbol: String, tint: Color = .white) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(tint)
            Text("\(value)")
                .font(.system(size: 26, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText(value: Double(value)))
                .animation(.snappy, value: value)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}
