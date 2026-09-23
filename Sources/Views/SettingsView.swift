import SwiftUI
import Photos

struct SettingsView: View {
    @ObservedObject var store: PhotoStore
    @Environment(\.dismiss) private var dismiss

    @State private var albums: [AlbumEntry] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("每组数量") {
                    Stepper(value: $store.photoBatchSize, in: 5...60, step: 5) {
                        LabeledContent("照片每组", value: "\(store.photoBatchSize) 张")
                    }
                    Stepper(value: $store.videoBatchSize, in: 5...40, step: 1) {
                        LabeledContent("视频每组", value: "\(store.videoBatchSize) 个")
                    }
                    Text("改完立刻重新发一组，浏览记录不会丢。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("浏览范围") {
                    Button {
                        store.albumID = nil
                    } label: {
                        row("所有照片", selected: store.albumID == nil)
                    }
                    ForEach(albums.filter { !$0.id.isEmpty }) { album in
                        Button {
                            store.albumID = album.id
                        } label: {
                            row(album.title, selected: store.albumID == album.id)
                        }
                    }
                }

                Section {
                    Text("朝花夕拾只在本机读取相册，不联网、不上传，浏览记录存在 App 自己的沙盒里。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } footer: {
                    EmptyView()
                }
            }
            .navigationTitle("设置")
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

    private func row(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title).foregroundStyle(.primary)
            Spacer()
            if selected {
                Image(systemName: "checkmark").foregroundStyle(.tint)
            }
        }
    }
}
