import SwiftUI
import Photos

/// 使用统计：照片 / 截屏 / 视频 分类累计 + 腾出空间 + 重置
struct StatsView: View {
    @ObservedObject var store: PhotoStore
    var onOpenSettings: () -> Void
    var onOpenMemory: (MemoryGroup) -> Void

    @State private var confirmReset = false
    @State private var showFavorites = false
    @State private var memories: [MemoryGroup] = []

    private let cardColor = Color(red: 0.105, green: 0.105, blue: 0.115)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center) {
                    Text("岁华簿")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button(action: onOpenSettings) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.glass)
                }
                .padding(.top, 8)

                memoryCard

                ForEach(StatKind.allCases, id: \.self) { kind in
                    categoryCard(kind)
                }

                freedCard

                favoritesCard

                if store.queuedCount > 0 {
                    pendingCard
                }

                resetCard
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .task {
            memories = await Task.detached(priority: .userInitiated) {
                PhotoStore.memoryGroups()
            }.value
        }
        .sheet(isPresented: $showFavorites) {
            FavoritesView(store: store)
        }
        .confirmationDialog("确定重置？", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("重置浏览记录", role: .destructive) { store.resetProgress() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("清空「看过 / 删过 / 腾出多少空间」的累计数字，不会动相册里的任何文件。")
        }
    }

    // MARK: - 朝花夕拾：往年今天

    @ViewBuilder
    private var memoryCard: some View {
        if !memories.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Label("昔年今日", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white.opacity(0.82))
                    Spacer()
                    Text("\(memories.count) 个年份")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(memories) { group in
                    memoryRow(group)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardColor, in: RoundedRectangle(cornerRadius: 22))
        }
    }

    private func memoryRow(_ group: MemoryGroup) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(group.yearsAgo) 年前")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                Text(verbatim: "\(group.year) · \(group.assets.count >= 60 ? "60+" : "\(group.assets.count)") 张")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 62, alignment: .leading)

            ForEach(group.assets.prefix(4), id: \.localIdentifier) { asset in
                MediaImageView(asset: asset, targetSize: CGSize(width: 56, height: 56))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpenMemory(group) }
    }

    // MARK: - 分类卡

    private func categoryCard(_ kind: StatKind) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(kind.title, systemImage: kind.symbol)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 8) {
                metric("查看", symbol: "eye.fill", tint: Color(red: 0.36, green: 0.5, blue: 1.0),
                       value: "\(store.reviewedCount(kind))")
                metric("删除", symbol: "trash.fill", tint: Color(red: 1.0, green: 0.35, blue: 0.35),
                       value: "\(store.deletedCount(kind))")
                metric("清理", symbol: "externaldrive.fill", tint: Color(red: 0.45, green: 0.9, blue: 0.4),
                       value: Self.text(store.freedBytes(kind)))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 22))
    }

    private func metric(_ title: String, symbol: String, tint: Color, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 腾出空间

    private var freedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("腾出空间", systemImage: "internaldrive")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(Self.text(store.totalFreedBytes))
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)

            Capsule()
                .fill(Color.white.opacity(0.12))
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    // 量这条自己的宽度：containerRelativeFrame 量到的是整屏，会顶出卡片
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(StatKind.allCases, id: \.self) { kind in
                                let share = store.share(of: kind)
                                if share > 0.001 {
                                    Capsule()
                                        .fill(barColor(kind))
                                        .frame(width: max(0, geo.size.width * share - 2))
                                }
                            }
                        }
                    }
                    .clipShape(Capsule())
                }

            HStack(spacing: 14) {
                ForEach(StatKind.allCases, id: \.self) { kind in
                    HStack(spacing: 5) {
                        Circle().fill(barColor(kind)).frame(width: 7, height: 7)
                        Text(kind.title)
                        Text("\(Int((store.share(of: kind) * 100).rounded()))%")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .foregroundStyle(.white)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 22))
    }

    private func barColor(_ kind: StatKind) -> Color {
        switch kind {
        case .photo: Color(red: 0.36, green: 0.5, blue: 1.0)
        case .screenshot: Color(red: 1.0, green: 0.35, blue: 0.35)
        case .video: Color(red: 0.45, green: 0.9, blue: 0.4)
        }
    }

    // MARK: - 收藏

    private var favoritesCard: some View {
        Button {
            showFavorites = true
        } label: {
            HStack {
                Label("收藏", systemImage: "heart.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color(red: 1.0, green: 0.35, blue: 0.45))
                Spacer()
                Text("\(store.favoriteIDs.count) 张")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(cardColor, in: RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 待确认删除

    private var pendingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("有 \(store.queuedCount) 张待确认删除", systemImage: "tray.full")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button {
                    store.discardAllQueued()
                } label: {
                    Text("放弃").frame(maxWidth: .infinity).padding(.vertical, 5)
                }
                .buttonStyle(.glass)

                Button {
                    Task { await store.commitQueuedDeletions() }
                } label: {
                    Text("立即删除")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.glassProminent)
                .tint(.red)
                .disabled(store.isCommitting)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 22))
    }

    // MARK: - 重置

    private var resetCard: some View {
        Button {
            confirmReset = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("重置浏览记录")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("浏览了 \(store.totalReviewed) 个项目，其中 \(store.totalDeleted) 个已删除。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(cardColor, in: RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }

    private static func text(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0字节" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
