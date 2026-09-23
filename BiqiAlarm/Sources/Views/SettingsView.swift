import SwiftUI

// MARK: - 设置

struct SettingsView: View {
    @Environment(AlarmStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var showSoundPicker = false
    @State private var tryingKind: MissionKind?
    @State private var confirmClearAll = false

    /// @Environment 注入的 @Observable 不能直接写 $settings.xxx，统一走这里
    private func bind<T>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { newValue in
                settings[keyPath: keyPath] = newValue
                settings.save()
            }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackdrop(using: Palette.night) { Color.clear }
                ScrollView {
                    LazyVStack(spacing: 14) {
                        channelCard
                        defaultsCard
                        hardnessCard
                        tryCard
                        aboutCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 26)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) { Text("设置").fontWeight(.bold) }
            }
            .toolbarTitleDisplayMode(.inline)
            .task { await store.refreshAuthorization() }
        }
        .sheet(isPresented: $showSoundPicker) {
            SoundPickerSheet(choice: .builtIn(settings.defaultSound)) { picked in
                if case .builtIn(let file) = picked { settings.defaultSound = file }
                settings.save()
            }
        }
        .sheet(item: $tryingKind) { kind in
            MissionTrySheet(config: MissionConfig.default(kind))
        }
    }

    private var channelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "叫醒通道", note: "两条都开才稳妥")
            StatusRow(title: "本地通知",
                      value: store.notificationState == .granted ? "已开启" : "未开启",
                      good: store.notificationState == .granted) {
                Task { await store.requestNotificationPermission() }
            }
            if AlarmKitEngine.isSupported {
                StatusRow(title: "系统闹钟（AlarmKit）",
                          value: store.alarmKitState == .granted ? "已开启" : "未开启",
                          good: store.alarmKitState == .granted) {
                    Task { await store.requestAlarmKitPermission() }
                }
            }
            Text("说清楚一件事：iOS 上系统响铃界面的「停止」按钮是苹果给的，任何 App 都拦不住。"
                 + "所以必起的做法是——到点后不停发通知、不停放铃声，直到你打开 App 把使命做完。"
                 + "安卓那种彻底锁死，在 iOS 上做不到，这里用的是能做到的最强方案。")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.62))
        }
        .glassPanel(tint: Color.white.opacity(0.06))
    }

    private var defaultsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "新建闹钟的默认值")
            Button {
                showSoundPicker = true
            } label: {
                HStack {
                    Text("默认铃声")
                    Spacer()
                    Text(SoundCatalog.sound(named: settings.defaultSound)?.title ?? "数字闹铃")
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .font(.subheadline)
                .foregroundStyle(.white)
            }
            Divider().overlay(.white.opacity(0.1))
            HStack {
                Text("默认音量")
                Slider(value: bind(\.defaultVolume), in: 0.1...1).tint(Palette.accent)
                Text("\(Int(settings.defaultVolume * 100))%").font(.caption).foregroundStyle(.secondary)
            }
            .font(.subheadline)
            Picker("音量渐强", selection: bind(\.defaultFadeInSeconds)) {
                Text("关闭").tag(0)
                Text("10 秒").tag(10)
                Text("30 秒").tag(30)
                Text("60 秒").tag(60)
            }
            .pickerStyle(.menu)
            Picker("贪睡间隔", selection: bind(\.defaultSnoozeMinutes)) {
                ForEach(SnoozeConfig.allowedMinutes, id: \.self) { minute in
                    Text("\(minute) 分钟").tag(minute)
                }
            }
            .pickerStyle(.menu)
            Divider().overlay(.white.opacity(0.1))
            Toggle("深色玻璃背景", isOn: bind(\.themeDark))
            HStack {
                Text("睡前提醒")
                Spacer()
                Toggle("", isOn: bind(\.morningReminderOn)).labelsHidden()
            }
            .font(.subheadline)
            if settings.morningReminderOn {
                HStack(spacing: 10) {
                    Picker("时", selection: bind(\.morningReminderHour)) {
                        ForEach(0..<24, id: \.self) { value in
                            Text("\(value) 点").tag(value)
                        }
                    }
                    Picker("分", selection: bind(\.morningReminderMinute)) {
                        ForEach([0, 10, 15, 20, 30, 40, 45, 50], id: \.self) { value in
                            Text("\(value) 分").tag(value)
                        }
                    }
                }
                .pickerStyle(.menu)
                .font(.footnote)
            }
        }
        .glassPanel()
    }

    private var hardnessCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "狠一点", note: "原版收会员费的，这里全开")
            Toggle("必起模式：响铃期间不许把音量压到最小", isOn: bind(\.unbeatable))
            Toggle("绕开静音拨片", isOn: bind(\.ignoreSilenceSwitch))
            Toggle("响铃时屏幕常亮", isOn: bind(\.keepScreenOnWhileRinging))
            Toggle("显示励志句", isOn: bind(\.motivationalQuotes))
            if settings.motivationalQuotes {
                Picker("句子类别", selection: bind(\.quoteCategory)) {
                    Text("清晨打气").tag(0)
                    Text("爱自己").tag(1)
                    Text("念书").tag(2)
                }
                .pickerStyle(.menu)
                Text(MorningGreeting.quote(category: settings.quoteCategory))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Stepper(value: bind(\.snoozeBeforeMission), in: 0...5) {
                HStack {
                    Text("贪睡几次后强制做使命")
                    Spacer()
                    Text(settings.snoozeBeforeMission == 0 ? "不强制" : "\(settings.snoozeBeforeMission) 次后")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
            HStack {
                Text("起床有效窗口")
                Spacer()
                Picker("", selection: bind(\.wakeWindowMinutes)) {
                    ForEach([10, 20, 30, 60, 90], id: \.self) { minute in
                        Text("\(minute) 分钟").tag(minute)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
            }
            .font(.subheadline)
        }
        .glassPanel(tint: Color.red.opacity(0.12))
    }

    private var tryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "先试一次", note: "不用等到早上才知道自己会不会做")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                ForEach(MissionKind.allCases) { kind in
                    Button {
                        tryingKind = kind
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: kind.icon).foregroundStyle(Palette.accent)
                            Text(kind.title).font(.footnote.weight(.medium))
                            Spacer()
                        }
                        .foregroundStyle(.white)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(GlassCardButton(tint: Color.white.opacity(0.07), cornerRadius: 14))
                }
            }
        }
        .glassPanel()
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "关于")
            Text("必起闹钟 1.0").font(.subheadline.weight(.semibold))
            Text("功能按「使命闹钟」原版对齐：12 种起床使命、多使命连做、任务限时、贪睡限制、"
                 + "音量渐强、自动收起、防删、快速闹钟、睡眠声音、起床报告。"
                 + "原版的会员墙和广告位全部去掉，全部功能默认开放；不联网，数据只留在手机里。")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.68))
            Divider().overlay(.white.opacity(0.1))
            Button("清掉所有闹钟和记录", role: .destructive) { confirmClearAll = true }
                .font(.footnote)
        }
        .glassPanel()
        .alert("确定清空？", isPresented: $confirmClearAll) {
            Button("全清", role: .destructive) { wipe() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("闹钟、使命设置和起床记录都会删掉，不可恢复。")
        }
    }

    private func wipe() {
        for alarm in store.alarms {
            store.remove(alarm)
        }
        WakeLog.shared.clear()
        AlarmKitEngine.cancelAll()
    }
}

private struct StatusRow: View {
    let title: String
    let value: String
    let good: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: good ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(good ? Color.green : Color.orange)
            Text(title).font(.subheadline)
            Spacer()
            if good {
                Text(value).font(.caption).foregroundStyle(.secondary)
            } else {
                Button(value, action: action)
                    .font(.caption.weight(.semibold))
                    .glassChip(tint: Palette.accent.opacity(0.45))
            }
        }
    }
}

// MARK: - 快速闹钟（原版 quick_alarm）

struct QuickAlarmView: View {
    @Environment(AlarmStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var minutes = 10
    @State private var kind: MissionKind = .math
    @State private var done = false

    var body: some View {
        ZStack {
            GlassBackdrop(using: Palette.dawn) { Color.black.opacity(0.3) }
            VStack(spacing: 16) {
                SectionHeader(title: "快速闹钟", note: "小睡一下、做个饭、到点必须起来")
                Stepper(value: $minutes, in: 1...180) {
                    HStack {
                        Text("多久之后")
                        Spacer()
                        Text("\(minutes) 分钟").font(.title3.bold()).foregroundStyle(Palette.accent)
                    }
                    .font(.subheadline)
                }
                HStack(spacing: 10) {
                    ForEach([5, 10, 15, 20, 30, 60], id: \.self) { value in
                        Button("\(value)") { minutes = value }
                            .buttonStyle(.glass)
                            .tint(minutes == value ? Palette.accent : nil)
                    }
                }
                Menu {
                    ForEach(MissionKind.allCases) { option in
                        Button(option.title) { kind = option }
                    }
                } label: {
                    HStack {
                        Text("叫醒使命")
                        Spacer()
                        Label(kind.title, systemImage: kind.icon).foregroundStyle(Palette.accent)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white)
                }
                .glassPanel(cornerRadius: 18)

                MissionBigButton(title: "开始", systemImage: "bolt.fill", prominent: true) {
                    store.startQuickAlarm(minutes: minutes, mission: MissionConfig.default(kind))
                    dismiss()
                }
                .frame(maxWidth: 260)
                Text("会作为一条一次性闹钟加进列表，方便你反悔。")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(22)
            .glassPanel(tint: Color.black.opacity(0.35), cornerRadius: 30)
            .padding(22)
        }
    }
}
