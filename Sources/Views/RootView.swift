import SwiftUI
import Photos

struct RootView: View {
    @StateObject private var store = PhotoStore()
    @StateObject private var palette = BackdropPalette()
    @StateObject private var meter = FrameMeter()
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var glass
    @Namespace private var zoom

    @State private var showSettings = false
    @State private var showSplash = true
    @State private var viewer: ViewerRequest?

    private struct ViewerRequest: Identifiable {
        let assetID: String
        let index: Int
        var id: String { assetID }
    }

    var body: some View {
        ZStack {
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
                dock
            }
            .padding(.top, 6)
            .padding(.bottom, 14)
            .background {
                ZStack {
                    BackdropView(asset: store.current)
                    LinearGradient(
                        colors: [palette.color, palette.color.opacity(0.72), Color.black.opacity(0.86)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.55), value: palette.color)
            }

            if store.showFPS {
                VStack {
                    fpsChip
                    Spacer()
                }
                .padding(.top, 8)
                .zIndex(20)
            }

            if showSplash {
                SplashView {
                    withAnimation(.easeInOut(duration: 0.7)) { showSplash = false }
                    store.requestAccess()
                }
                .transition(.opacity.combined(with: .scale(scale: 1.05)))
                .zIndex(10)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: store.current?.localIdentifier) { _, _ in
            palette.update(from: store.current)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.flush() }
        }
        .onChange(of: store.showFPS) { _, on in
            if on { meter.start() } else { meter.stop() }
        }
        .onAppear { if store.showFPS { meter.start() } }
        .sheet(isPresented: $showSettings) {
            SettingsView(store: store)
                .presentationBackground(.black)
                .presentationDragIndicator(.hidden)
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

    private var fpsChip: some View {
        Text(String(format: "%.0f fps", meter.fps))
            .font(.system(size: 13, weight: .semibold).monospacedDigit())
            .foregroundStyle(meter.fps >= 55 ? .green : (meter.fps >= 40 ? .yellow : .red))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular.tint(.black.opacity(0.4)), in: .rect(cornerRadius: 16))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
    }

    // MARK: - 顶部胶囊

    private var header: some View {
        HStack {
            if store.writable, store.tab != .stats, store.tab != .editing {
                headerPill
            }
            Spacer()
        }
        .padding(.top, 6)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 胶囊：⌄ + 当前口径 + 剩余张数；图片栏点开是内容类型下拉，视频栏不给筛
    @ViewBuilder
    private var headerPill: some View {
        let label = HStack(spacing: 9) {
            if store.tab != .videos {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Text(store.tab == .videos ? store.tab.title
                                      : (store.contentFilter == .all ? store.tab.title : store.contentFilter.title))
                .font(.system(size: 17, weight: .medium))
            Text("\(store.deckRemaining)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(.white.opacity(0.20), in: Circle())
                .contentTransition(.numericText(value: Double(store.deckRemaining)))
                .animation(.snappy, value: store.deckRemaining)
        }
        .foregroundStyle(.white)
        .padding(.leading, 20)
        .padding(.trailing, 9)
        .frame(height: 44)
        .glassEffect(.regular, in: Capsule())

        if store.tab == .videos {
            label
        } else {
            Menu {
                Picker("内容类型", selection: $store.contentFilter) {
                    ForEach(ContentFilter.allCases) { filter in
                        Label(filter.title, systemImage: filter.symbol).tag(filter)
                    }
                }

                Divider()

                Menu {
                    ForEach([10, 15, 20, 30, 50], id: \.self) { size in
                        Button("\(size) 张") { store.photoBatchSize = size }
                    }
                } label: {
                    Label("调整每组数量", systemImage: "slider.horizontal.3")
                }
            } label: {
                label
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 主区域

    @ViewBuilder
    private var main: some View {
        if !store.writable {
            PermissionView(store: store)
        } else if store.tab == .stats {
            StatsView(store: store,
                      onOpenSettings: { showSettings = true },
                      onOpenMemory: { group in
                store.showMemory(group.assets)
                viewer = ViewerRequest(assetID: group.assets[0].localIdentifier, index: 0)
            })
        } else if store.tab == .editing {
            EditorView()
        } else {
            CardStackView(store: store, zoom: zoom) { cursor in
                guard let asset = store.card(at: 0) else { return }
                viewer = ViewerRequest(assetID: asset.localIdentifier, index: cursor)
            }
        }
    }

    // MARK: - 底部 Dock：一整条胶囊 + 一块会在条目之间形变的玻璃

    private static let dockItemWidth: CGFloat = 64
    private static let dockHeight: CGFloat = 58

    private var dock: some View {
        GlassEffectContainer(spacing: 8) {
            ZStack {
                Capsule().fill(Color.black.opacity(0.30))
                Capsule().strokeBorder(.white.opacity(0.13), lineWidth: 1)

                HStack(spacing: 0) {
                    ForEach(RootTab.allCases) { item in
                        dockItem(item)
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(height: Self.dockHeight)
        }
        .padding(.horizontal, 6)
        .padding(.top, 10)
        .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
    }

    private func dockItem(_ item: RootTab) -> some View {
        let selected = store.tab == item
        return Button {
            store.tab = item
        } label: {
            VStack(spacing: 5) {
                Image(systemName: item.symbol)
                    .font(.system(size: 20, weight: selected ? .semibold : .medium))
                Text(item.title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(selected ? Color(red: 0.44, green: 0.66, blue: 1.0) : .white.opacity(0.7))
            .frame(width: Self.dockItemWidth, height: Self.dockHeight - 8)
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        // 五个条目共用一个 glassEffectID：选中态换人时，系统把这块玻璃从旧条目
        // 形变过去（弹性、折射、合并都是系统算），而不是我们自己挪一个方块
        .glassEffect(selected ? .regular.tint(.black.opacity(0.26)).interactive() : nil,
                     in: RoundedRectangle(cornerRadius: 24))
        .glassEffectID("dock-selection", in: glass)
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
            "花间集只在本地读取照片和视频，不会上传任何内容。"
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
