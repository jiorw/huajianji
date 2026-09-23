import SwiftUI
import Photos

struct RootView: View {
    @StateObject private var store = PhotoStore()
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var glass

    @State private var showAlbums = false
    @State private var toast: Toast?

    private struct Toast: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let canUndo: Bool
    }

    var body: some View {
        ZStack {
            BackdropView(asset: store.current)
                .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.10), .black.opacity(0.55), .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                header
                main
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(.snappy(duration: 0.35), value: store.tab)
                dock
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
        .preferredColorScheme(.dark)
        .task { store.requestAccess() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.flush() }
        }
        .sheet(isPresented: $showAlbums) {
            AlbumPickerSheet(store: store)
        }
        .overlay(alignment: .bottom) { toastLayer }
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
                    }
                }
            }
            Spacer()
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 主区域

    @ViewBuilder
    private var main: some View {
        if !store.writable {
            PermissionView(store: store)
        } else if store.tab == .stats {
            StatsView(store: store)
        } else {
            CardStackView(store: store) {
                toast = Toast(text: "已移入待删", canUndo: true)
            }
        }
    }

    // MARK: - 底部 Dock

    private var dock: some View {
        GlassEffectContainer(spacing: 46) {
            HStack(spacing: 10) {
                ForEach(RootTab.allCases) { item in
                    dockItem(item)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .padding(.top, 10)
    }

    private func dockItem(_ item: RootTab) -> some View {
        let selected = store.tab == item
        return Button {
            withAnimation(.snappy(duration: 0.35)) { store.tab = item }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: item.symbol)
                    .font(.system(size: 19, weight: .medium))
                Text(item.title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(selected ? Color(red: 0.44, green: 0.66, blue: 1.0) : .white)
            .frame(width: 76, height: 48)
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .glassEffect(
            selected ? .regular.tint(.blue.opacity(0.40)).interactive() : .regular.interactive(),
            in: .rect(cornerRadius: 24)
        )
        .glassEffectID("dock-\(item.rawValue)", in: glass)
    }

    // MARK: - 轻提示

    @ViewBuilder
    private var toastLayer: some View {
        if let toast {
            HStack(spacing: 14) {
                Text(toast.text)
                    .font(.subheadline.weight(.medium))
                if toast.canUndo, store.canUndo {
                    Button("撤销") {
                        store.undoLast()
                        self.toast = nil
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.blue)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
            .padding(.bottom, 100)
            .task(id: toast.id) {
                try? await Task.sleep(for: .seconds(2.6))
                if self.toast?.id == toast.id { self.toast = nil }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
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
