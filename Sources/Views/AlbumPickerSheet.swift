import SwiftUI
import Photos

struct AlbumPickerSheet: View {
    @ObservedObject var store: PhotoStore
    @Environment(\.dismiss) private var dismiss

    @State private var albums: [AlbumEntry] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(albums) { album in
                    Button {
                        store.albumID = album.id.isEmpty ? nil : album.id
                        dismiss()
                    } label: {
                        HStack {
                            Text(album.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if isSelected(album) {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            .navigationTitle("选择相册")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task {
                if albums.isEmpty { albums = store.albums() }
            }
        }
    }

    private func isSelected(_ album: AlbumEntry) -> Bool {
        album.id.isEmpty ? store.albumID == nil : store.albumID == album.id
    }
}
