import SwiftUI
import Photos

struct SettingsView: View {
    @ObservedObject var store: PhotoStore
    @Environment(\.dismiss) private var dismiss

    @State private var albums: [AlbumEntry] = []
    @State private var backupURL: URL?
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            Form {
                Section("会员") {
                    LabeledContent("状态", value: "Pro · 终身已解锁")
                    Text("这份构建没有内购、没有每日额度限制，所有功能直接可用。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("回顾方式") {
                    Picker("模式", selection: $store.mode) {
                        ForEach(BrowseMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Text(store.mode == .onThisDay
                         ? "只抽往年今天的照片，一次翻到同一天不同年份的自己。"
                         : "整个相册里随机抽，不知道会遇见哪一张。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("每组数量") {
                    Stepper(value: $store.photoBatchSize, in: 5...60, step: 5) {
                        LabeledContent("照片每组", value: "\(store.photoBatchSize) 张")
                    }
                    Stepper(value: $store.videoBatchSize, in: 5...40, step: 1) {
                        LabeledContent("视频每组", value: "\(store.videoBatchSize) 个")
                    }
                }

                Section("每日提醒") {
                    Toggle("每天提醒我来翻一组", isOn: $store.reminderOn)
                    if store.reminderOn {
                        DatePicker("提醒时间", selection: reminderTime, displayedComponents: .hourAndMinute)
                    }
                    Text("通知在本地排期，不经过任何服务器。自签安装有时会被系统限制，收不到就在设置里关掉再开一次。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("演示模式") {
                    Toggle("只演示，不真的删除", isOn: $store.demoMode)
                    Text("打开后走完整流程，但确认删除时不会动相册里的任何文件，统计数字也不计入。")
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

                Section("记录") {
                    if let backupURL {
                        ShareLink(item: backupURL) {
                            Label("分享导出的记录文件", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button {
                        backupURL = store.exportBackup()
                    } label: {
                        Label("导出浏览记录", systemImage: "arrow.down.doc")
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label("从文件导入", systemImage: "arrow.up.doc")
                    }
                    Text("自签安装拿不到 CloudKit 权限，所以同步靠这个 JSON 文件：旧机导出、新机导入，收藏和浏览进度就都过来了。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Text("朝花夕拾只在本机读取相册，不联网、不上传，所有记录存在 App 自己的沙盒里。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.json],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { store.importBackup(from: url) }
                case .failure(let error):
                    store.errorMessage = "读取文件失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = store.reminderHour
                components.minute = store.reminderMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                store.reminderHour = components.hour ?? store.reminderHour
                store.reminderMinute = components.minute ?? store.reminderMinute
            }
        )
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
