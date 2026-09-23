import SwiftUI

// MARK: - 闹钟列表（原版 Home / Alarm 页）

struct AlarmListView: View {
    @Environment(AlarmStore.self) private var store
    @Environment(AppSettings.self) private var settings
    let openEditor: (AlarmItem) -> Void
    let openQuick: () -> Void
    let glass: Namespace.ID

    @State private var draft: AlarmItem?
    @State private var greeting = ""
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    header
                    permissionBanner
                    nextCard

                    if store.sortedAlarms.isEmpty {
                        emptyCard
                    } else {
                        ForEach(Array(store.sortedAlarms.enumerated()), id: \.element.id) { index, alarm in
                            AlarmRow(alarm: alarm, open: { openEditor(alarm) }, glass: glass)
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 20)
                                .animation(GlassMotion.settle.delay(Double(index) * 0.06), value: appeared)
                        }
                    }

                    Spacer(minLength: 80)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottomTrailing) {
                Button {
                    draft = store.newAlarm()
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.bold())
                        .foregroundStyle(.black.opacity(0.85))
                        .frame(width: 58, height: 58)
                        .contentShape(Circle())
                }
                .buttonStyle(GlassPillButton(tint: Palette.accent))
                .matchedTransitionSource(id: "add", in: glass)
                .padding(.trailing, 22)
                .padding(.bottom, 26)
            }
        }
        .onAppear {
            greeting = MorningGreeting.text()
            appeared = true
        }
        .sheet(item: $draft) { alarm in
            AlarmEditorView(alarm: alarm)
                .navigationTransition(.zoom(sourceID: "add", in: glass))
                .presentationBackground(.clear)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("必起闹钟 · 不做使命别想关")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
            Button(action: openQuick) {
                Image(systemName: "bolt.fill")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .contentShape(Circle())
            }
            .buttonStyle(GlassPillButton(tint: Palette.accent.opacity(0.55)))
            .matchedTransitionSource(id: "quick", in: glass)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var permissionBanner: some View {
        if store.notificationState != .granted || store.alarmKitState == .denied {
            VStack(alignment: .leading, spacing: 10) {
                Label("叫醒通道没全开", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(store.notificationState == .granted
                     ? "通知已开，但系统闹钟被拒绝：专注模式 / 静音拨片下可能不响。"
                     : "通知被关掉的话，闹钟只能在 App 开着的时候响，等于没设。")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
                GlassBar {
                    Button("开通知") {
                        Task { await store.requestNotificationPermission() }
                    }
                    .buttonStyle(.glass)
                    if AlarmKitEngine.isSupported {
                        Button("开系统闹钟") {
                            Task { await store.requestAlarmKitPermission() }
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Palette.accent)
                    }
                }
            }
            .glassPanel(tint: Color.orange.opacity(0.28))
        }
    }

    @ViewBuilder
    private var nextCard: some View {
        if let next = store.nextAlarm {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("下一个闹钟").font(.caption).foregroundStyle(.white.opacity(0.65))
                    Text(next.timeTitle)
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text("\(next.displayName) · \(next.nextFireText)")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(next.countDownText(to: next.nextFireDate() ?? Date()))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    if !next.missions.isEmpty {
                        Text(next.missions.map { $0.kind.title }.joined(separator: " + "))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .glassPanel(tint: Palette.cool.opacity(0.22), cornerRadius: 30)
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "alarm")
                .font(.system(size: 46))
                .foregroundStyle(.white.opacity(0.5))
            Text("还没有闹钟").foregroundStyle(.white)
            Text("点右下角的 + 加一个，记得配使命。")
                .font(.footnote).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .glassPanel(tint: Color.white.opacity(0.05))
    }
}

// MARK: - 单行闹钟

private struct AlarmRow: View {
    @Environment(AlarmStore.self) private var store
    let alarm: AlarmItem
    let open: () -> Void
    let glass: Namespace.ID

    @State private var confirmDelete = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(alarm.timeTitle)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(alarm.enabled ? .white : .white.opacity(0.4))
                    if alarm.enabled {
                        Text(alarm.nextFireText)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    Toggle("", isOn: binding)
                        .labelsHidden()
                        .tint(Palette.accent)
                }
                HStack(spacing: 6) {
                    Text(alarm.label.isEmpty ? "闹钟" : alarm.label)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(alarm.repeatOption.symbolTitle)
                        .font(.caption2)
                        .glassChip(tint: Color.white.opacity(0.08))
                }
                if !alarm.missions.isEmpty {
                    FlowChips(items: alarm.missions.map { "\($0.kind.title) \($0.summary)" })
                }
                if alarm.requiresMissionToDelete {
                    Label("删这条也要先做使命", systemImage: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(Palette.accent)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(GlassCardButton(
            tint: alarm.enabled ? Color.white.opacity(0.10) : Color.white.opacity(0.04)))
        .matchedTransitionSource(id: alarm.id.uuidString, in: glass)
        .contextMenu {
            Button("复制", systemImage: "doc.on.doc") { store.duplicate(alarm) }
            Button("删除", systemImage: "trash", role: .destructive) { requestDelete() }
        }
        .alert("删掉「\(alarm.displayName)」？", isPresented: $confirmDelete) {
            Button("删", role: .destructive) { store.remove(alarm) }
            Button("取消", role: .cancel) {}
        }
    }

    private var binding: Binding<Bool> {
        Binding(get: { alarm.enabled }, set: { store.setEnabled($0, for: alarm) })
    }

    private func requestDelete() {
        if alarm.requiresMissionToDelete {
            store.deleteGate = alarm.id
        } else {
            confirmDelete = true
        }
    }
}

// MARK: - 小工具

struct FlowChips: View {
    let items: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items.prefix(3), id: \.self) { item in
                Text(item)
                    .font(.caption2)
                    .lineLimit(1)
                    .glassChip(tint: Palette.accent.opacity(0.28))
            }
            if items.count > 3 {
                Text("+\(items.count - 3)").font(.caption2).foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
    }
}

enum MorningGreeting {
    static func text(date: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<9: return "早上好"
        case 9..<12: return "该动了"
        case 12..<14: return "中午好"
        case 14..<18: return "下午好"
        case 18..<23: return "晚上好"
        default: return "还醒着？"
        }
    }

    private static let pools: [[String]] = [PhraseBook.morning, PhraseBook.love, PhraseBook.study]

    static func quote(category: Int, date: Date = Date()) -> String {
        let pool = pools.indices.contains(category) ? pools[category] : PhraseBook.morning
        let index = Calendar.current.component(.day, from: date) % pool.count
        return pool[index]
    }
}
