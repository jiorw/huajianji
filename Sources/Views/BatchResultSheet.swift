import SwiftUI
import Photos

/// 一组 20 张筛完之后的结算页
struct BatchResultSheet: View {
    @ObservedObject var store: PhotoStore
    var onDone: () -> Void

    @State private var queued: [PHAsset] = []

    private var headline: String {
        var parts = ["\(store.deck.count) 张里留下 \(store.keptInBatch) 张"]
        if !queued.isEmpty { parts.append("\(queued.count) 张待删") }
        if let oldest = store.deck.compactMap(\.creationDate).min() {
            parts.append("最久的一张 \(TimeText.since(oldest))")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 20) {
            ConfettiView()
                .frame(height: 150)
                .padding(.top, 4)

            VStack(spacing: 8) {
                Text("这一组翻完了")
                    .font(.title2.weight(.bold))
                Text(headline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            if queued.isEmpty {
                ContentUnavailableView("干干净净", systemImage: "checkmark.circle",
                                       description: Text("这一组里没有你想删的照片，直接再来一组。"))
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                        ForEach(queued, id: \.localIdentifier) { asset in
                            MediaImageView(asset: asset, targetSize: CGSize(width: 110, height: 110))
                                .frame(height: 110)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(.white.opacity(0.18), lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 18)
                }
            }

            HStack(spacing: 14) {
                Button {
                    store.abandonBatch()
                    onDone()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 18, weight: .semibold))
                        Text("放弃 · 再来一组")
                            .font(.footnote.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.glass)

                Button {
                    Task {
                        await store.commitQueuedDeletions()
                        onDone()
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 18, weight: .semibold))
                        Text("确认删除 \(queued.count) 张")
                            .font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.glassProminent)
                .tint(.red)
                .disabled(store.isCommitting)
            }
            .padding(.horizontal, 18)

            Text("确认删除会真的从相册移除，之后还能在系统相册「最近删除」里找回 30 天。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 26)
                .padding(.bottom, 18)
        }
        .task { reload() }
        .onChange(of: store.queuedInBatch.count) { _, _ in reload() }
    }

    private func reload() {
        let ids = store.queuedInBatch
        guard !ids.isEmpty else {
            queued = []
            return
        }
        var list: [PHAsset] = []
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            .enumerateObjects { asset, _, _ in list.append(asset) }
        queued = list
    }
}
