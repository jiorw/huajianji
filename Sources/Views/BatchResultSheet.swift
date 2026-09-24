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
                            Button {
                                store.bump(.light)
                                withAnimation(.snappy(duration: 0.25)) {
                                    store.unmark(asset)
                                    reload()
                                }
                            } label: {
                                MediaImageView(asset: asset, targetSize: CGSize(width: 110, height: 110))
                                    .frame(height: 110)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(.white.opacity(0.18), lineWidth: 1))
                            }
                            .buttonStyle(PressableStyle(scale: 0.92))
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

/// 大图页带着待删要退出时拦一道：照原版那张「有待删除的照片」
struct PendingDeleteSheet: View {
    @ObservedObject var store: PhotoStore
    var onClose: () -> Void
    var onAbandon: () -> Void
    var onDeleted: () -> Void

    @State private var queued: [PHAsset] = []

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("有待删除的照片")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)

                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Circle())
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 10)

            Text("点一张缩略图可以反悔，它会回到牌堆里")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)

            if queued.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(.green)
                    Text("都反悔完了，没有要删的了")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)],
                              alignment: .leading, spacing: 12) {
                        ForEach(queued, id: \.localIdentifier) { asset in
                            Button {
                                store.bump(.light)
                                withAnimation(.snappy(duration: 0.25)) {
                                    store.unmark(asset)
                                    reload()
                                }
                            } label: {
                                MediaImageView(asset: asset, targetSize: CGSize(width: 110, height: 110))
                                    .frame(height: 112)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .overlay(alignment: .bottomTrailing) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 24))
                                            .foregroundStyle(.green, .black.opacity(0.55))
                                            .padding(7)
                                    }
                            }
                            .buttonStyle(PressableStyle(scale: 0.92))
                        }
                    }
                    .padding(.horizontal, 18)
                }
                .animation(.snappy(duration: 0.25), value: queued.count)
            }

            HStack(spacing: 14) {
                Button {
                    store.abandonBatch()
                    onAbandon()
                } label: {
                    Text("放弃，回到首页")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Capsule())

                Button {
                    Task {
                        await store.commitQueuedDeletions()
                        onDeleted()
                    }
                } label: {
                    Text("确认删除")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(.red.opacity(0.72)).interactive(), in: Capsule())
                .disabled(store.isCommitting)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
        .task { reload() }
    }

    private func reload() {
        var list: [PHAsset] = []
        PHAsset.fetchAssets(withLocalIdentifiers: store.queuedInBatch, options: nil)
            .enumerateObjects { asset, _, _ in list.append(asset) }
        queued = list
    }
}
