import SwiftUI
import UIKit

enum RootTab: Hashable {
    case alarms, sleep, report, settings
}

struct RootView: View {
    @Environment(AlarmStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var tab: RootTab = .alarms
    @State private var quickAlarm = false
    @State private var editing: AlarmItem?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            GlassBackdrop(using: settings.backgroundGradient) { Color.clear }

            TabView(selection: $tab) {
                AlarmListView(openEditor: openEditor, openQuick: { quickAlarm = true })
                    .tabItem { Label("闹钟", systemImage: "alarm.fill") }
                    .tag(RootTab.alarms)

                SleepMusicView()
                    .tabItem { Label("睡眠", systemImage: "moon.stars.fill") }
                    .tag(RootTab.sleep)

                ReportView()
                    .tabItem { Label("报告", systemImage: "chart.line.uptrend.xyaxis") }
                    .tag(RootTab.report)

                SettingsView()
                    .tabItem { Label("设置", systemImage: "gearshape.fill") }
                    .tag(RootTab.settings)
            }

            if store.ringing != nil {
                RingingView()
                    .transition(.opacity)
            }
        }
        .tint(Palette.accent)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.handleTick() }
        }
        .onChange(of: store.ringing?.alarm.id) { _, alarmID in
            UIApplication.shared.isIdleTimerDisabled = alarmID != nil && settings.keepScreenOnWhileRinging
        }
        .sheet(item: $editing) { alarm in
            AlarmEditorView(alarm: alarm)
        }
        .sheet(isPresented: $quickAlarm) {
            QuickAlarmView()
        }
        .sheet(isPresented: deleteGateBinding) {
            DeleteGateView(cancel: { store.deleteGate = nil })
        }
        .overlay {
            if let error = store.lastError {
                ToastView(text: error) {
                    store.lastError = nil
                }
            }
        }
    }

    private func openEditor(_ alarm: AlarmItem) {
        editing = alarm
    }

    private var deleteGateBinding: Binding<Bool> {
        Binding(get: { store.deleteGate != nil },
                set: { if !$0 { store.deleteGate = nil } })
    }
}

// MARK: - 防删：删这条闹钟得先做一次使命

struct DeleteGateView: View {
    @Environment(AlarmStore.self) private var store
    let cancel: () -> Void

    private var target: AlarmItem? {
        guard let id = store.deleteGate else { return nil }
        return store.alarms.first { $0.id == id }
    }

    var body: some View {
        ZStack {
            GlassBackdrop(using: Palette.alert) { Color.black.opacity(0.45) }
            if let alarm = target {
                VStack(spacing: 12) {
                    Text("要删掉「\(alarm.displayName)」？")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("这条设了防删：做完下面这个使命才让删。")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                    MissionStage(config: alarm.missions.first ?? MissionConfig.default(.math)) {
                        store.remove(alarm)
                        store.deleteGate = nil
                    }
                }
                .padding(16)
            } else {
                VStack(spacing: 12) {
                    Text("找不到那条闹钟了").foregroundStyle(.white)
                    MissionBigButton(title: "关闭", prominent: true, action: cancel)
                        .frame(maxWidth: 200)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .overlay(alignment: .topTrailing) {
            Button("算了", action: cancel)
                .font(.footnote.weight(.semibold))
                .glassChip()
                .padding(16)
        }
    }
}

// MARK: - 轻提示

struct ToastView: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        VStack {
            Spacer()
            Text(text)
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassEffect(.regular.tint(Color.black.opacity(0.55)), in: Capsule())
                .padding(.bottom, 120)
        }
        .frame(maxWidth: .infinity)
        .onTapGesture(perform: dismiss)
        .task {
            try? await Task.sleep(for: .seconds(2.6))
            dismiss()
        }
    }
}
