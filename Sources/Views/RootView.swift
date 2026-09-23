import SwiftUI
import Photos

struct RootView: View {
    @StateObject private var store = PhotoStore()
    @StateObject private var palette = BackdropPalette()
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var glass
    @Namespace private var zoom

    @State private var showAlbums = false
    @State private var showSettings = false
    @State private var viewer: ViewerRequest?

    private struct ViewerRequest: Identifiable {
        let assetID: String
        let index: Int
        var id: String { assetID }
    }

    var body: some View {
        ZStack {
            BackdropView(asset: store.current)
                .ignoresSafeArea()

            LinearGradient(
                colors: [palette.color, palette.color.opacity(0.72), Color.black.opacity(0.86)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.55), value: palette.color)

            VStack(spacing: 0) {
                header
                if store.demoMode {
                    Text("演示模式 · 确认删除也不会动相册里的文件")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassEffect(.regular.tint(.orange.opacity(0.55)), in: .rect(cornerRadius: 12))
                        .padding(.top, 8)
                }
                main
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(.spring(duration: 0.45, bounce: 0.2), value: store.tab)
                dock
            }
            .padding(.bottom, 6)
        }
        .preferredColorScheme(.dark)
        .task { store.requestAccess() }
        .onChange(of: store.current?.localIdentifier) { _, _ in
            palette.update(from: store.current)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.flush() }
        }
        .sheet(isPresented: $showAlbums) {
            AlbumPickerSheet(store: store)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(store: store)
        }
        .fullScreenCover(item: $viewer) { request in
            PhotoViewerView(store: store, startIndex: request.index)
                .navigationTransition(.zoom(sourceID: request.assetID, in: zoom))
        }
        .alert("出错了", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    // MARK: - 顶部胶囊

    private var header: some View {
        HStack {
            if store.writable, store.tab != .stats {
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 10) {
                        Button {
                            showAlbums = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .bold))
                                Text(store.albumTitle)
                                    .font(.system(size: 17, weight: .medium))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(height: 40)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.glass)

                        Text("\(store.deckRemaining)")
                            .font(.system(size: 14, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
                            .glassEffectID("remaining", in: glass)
                            .contentTransition(.numericText(value: Double(store.deckRemaining)))
                            .animation(.snappy, value: store.deckRemaining)

                        Button {
                            withAnimation(.spring(duration: 0.45, bounce: 0.22)) {
                                store.mode = store.mode == .blindBox ? .onThisDay : .blindBox
                            }
                        } label: {
                            Image(systemName: store.mode == .onThisDay ? "calendar.badge.clock" : "shuffle")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .glassEffect(store.mode == .onThisDay
                                     ? .regular.tint(.blue.opacity(0.45)).interactive()
                                     : .regular.interactive(),
                                     in: .rect(cornerRadius: 20))
                        .glassEffectID("mode", in: glass)
                        .animation(.snappy, value: store.mode)
                    }
                }
            }
            Spacer()
        }
        .padding(.top, 6)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 主区域

    @ViewBuilder
    private var main: some View {
        if !store.writable {
            PermissionView(store: store)
        } else if store.tab == .stats {
            StatsView(store: store, onOpenSettings: { showSettings = true })
        } else {
            CardStackView(store: store, zoom: zoom) { cursor in
                guard let asset = store.card(at: 0) else { return }
                viewer = ViewerRequest(assetID: asset.localIdentifier, index: cursor)
            }
        }
    }

    // MARK: - 底部 Dock（比之前放大 20%）

    private var dock: some View {
        GlassEffectContainer(spacing: 55) {
            HStack(spacing: 12) {
                ForEach(RootTab.allCases) { item in
                    dockItem(item)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .padding(.top, 10)
    }

    private func dockItem(_ item: RootTab) -> some View {
        let selected = store.tab == item
        return Button {
            withAnimation(.spring(duration: 0.45, bounce: 0.22)) { store.tab = item }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: item.symbol)
                    .font(.system(size: 23, weight: .medium))
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(selected ? Color(red: 0.44, green: 0.66, blue: 1.0) : .white)
            .frame(width: 91, height: 58)
            .contentShape(RoundedRectangle(cornerRadius: 29))
        }
        .buttonStyle(.plain)
        .glassEffect(
            selected ? .regular.tint(.blue.opacity(0.40)).interactive() : .regular.interactive(),
            in: .rect(cornerRadius: 29)
        )
        .glassEffectID("dock-\(item.rawValue)", in: glass)
    }
}

struct PermissionView: View {
    @ObservedObject var store: PhotoStore

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44))
                .foregroundStyle(.white)
            Text(headline)
                .font(.title3.weight(.semibold))
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button(action: act) {
                Text(actionTitle)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.glassProminent)
        }
        .padding(28)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
        .padding(.horizontal, 12)
    }

    private var headline: String {
        store.authorization == .notDetermined ? "需要相册权限" : "相册权限没开"
    }

    private var detail: String {
        switch store.authorization {
        case .limited:
            "当前是「有限访问」，只能看到你勾选的那几张照片。建议改成「完全访问」才能随机翻遍整个相册。"
        case .notDetermined:
            "朝花夕拾只在本地读取照片和视频，不会上传任何内容。"
        default:
            "请到系统设置里把照片权限打开，否则没法读取相册。"
        }
    }

    private var actionTitle: String {
        store.authorization == .notDetermined ? "允许访问" : "去系统设置"
    }

    private func act() {
        if store.authorization == .notDetermined {
            store.requestAccess()
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
