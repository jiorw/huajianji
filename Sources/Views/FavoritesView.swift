import SwiftUI
import Photos

/// 收藏列表：网格浏览，点开放大，长按取消收藏
struct FavoritesView: View {
    @ObservedObject var store: PhotoStore
    @Environment(\.dismiss) private var dismiss

    @State private var assets: [PHAsset] = []
    @State private var focused: FocusItem?

    private struct FocusItem: Identifiable {
        let asset: PHAsset
        var id: String { asset.localIdentifier }
    }

    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 8)]

    var body: some View {
        NavigationStack {
            Group {
                if assets.isEmpty {
                    ContentUnavailableView("还没有收藏",
                                           systemImage: "heart",
                                           description: Text("在全屏看图时点右上角的心形，就能把这张留下来。"))
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(assets, id: \.localIdentifier) { asset in
                                Button {
                                    focused = FocusItem(asset: asset)
                                } label: {
                                    MediaImageView(asset: asset, targetSize: CGSize(width: 130, height: 170))
                                        .frame(height: 170)
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                        .overlay(alignment: .bottomTrailing) {
                                            if asset.mediaType == .video {
                                                Image(systemName: "play.fill")
                                                    .font(.caption)
                                                    .foregroundStyle(.white)
                                                    .padding(6)
                                                    .background(.black.opacity(0.45), in: Circle())
                                                    .padding(6)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("取消收藏", role: .destructive) {
                                        _ = store.toggleFavorite(asset)
                                        reload()
                                    }
                                }
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .navigationTitle("收藏 · \(assets.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .task { reload() }
        .fullScreenCover(item: $focused) { item in
            FavoritePreview(store: store, asset: item.asset) { focused = nil }
        }
    }

    private func reload() {
        assets = store.favoriteAssets()
    }
}

private struct FavoritePreview: View {
    @ObservedObject var store: PhotoStore
    let asset: PHAsset
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MediaImageView(asset: asset, targetSize: CGSize(width: 900, height: 1600), contentMode: .fit)
            VStack {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.glass)
                    Spacer()
                    Text(TimeText.since(asset.creationDate))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
}
