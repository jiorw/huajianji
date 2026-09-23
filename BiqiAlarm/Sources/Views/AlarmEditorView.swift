import SwiftUI

// MARK: - 闹钟编辑页（原版 EditScreen / AlarmEditViewController）

struct AlarmEditorView: View {
    @Environment(AlarmStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var alarm: AlarmItem
    @State private var time: Date
    @State private var showSoundPicker = false
    @State private var missionDraft: MissionConfig?
    @State private var showMissionPicker = false
    @State private var confirmDelete = false

    init(alarm: AlarmItem) {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        var date = Calendar.current.date(from: components) ?? Date()
        date = Calendar.current.date(byAdding: .second, value: alarm.hour * 3600 + alarm.minute * 60,
                                     to: date) ?? date
        _alarm = State(initialValue: alarm)
        _time = State(initialValue: date)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackdrop(using: Palette.night) { Color.clear }
                ScrollView {
                    LazyVStack(spacing: 14) {
                        timeCard
                        labelCard
                        repeatCard
                        missionCard
                        snoozeCard
                        soundCard
                        disciplineCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 30)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.fontWeight(.bold).tint(Palette.accent)
                }
            }
        }
        .sheet(isPresented: $showSoundPicker) {
            SoundPickerSheet(choice: alarm.sound) { picked in
                alarm.sound = picked
            }
        }
        .sheet(isPresented: $showMissionPicker) {
            MissionPickerView(existing: alarm.missions) { picked in
                alarm.missions = picked
            }
        }
        .sheet(item: $missionDraft) { config in
            MissionConfigSheet(config: config) { updated in
                if let index = alarm.missions.firstIndex(where: { $0.id == updated.id }) {
                    alarm.missions[index] = updated
                }
            }
        }
        .alert("删掉这条闹钟？", isPresented: $confirmDelete) {
            Button("删", role: .destructive) {
                store.remove(alarm)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var hours: Int { Calendar.current.component(.hour, from: time) }
    private var minutes: Int { Calendar.current.component(.minute, from: time) }

    private var timeCard: some View {
        VStack(spacing: 10) {
            DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.wheel)
                .environment(\.locale, Locale(identifier: "zh_CN"))
            Text("每天要起几次就设几个，别指望一个闹钟管所有")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
        }
        .glassPanel(tint: Color.white.opacity(0.08), cornerRadius: 28)
    }

    private var labelCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "备注", note: "会在锁屏和响铃界面显示")
            TextField("比如：送孩子、晨跑、赶地铁", text: $alarm.label)
                .textFieldStyle(.plain)
                .padding(12)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)
        }
        .glassPanel()
    }

    private var repeatCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "重复")
            GlassEffectContainer(spacing: 8) {
                FlowlessRow(items: ["不重复", "每天", "工作日", "周末"],
                            selection: repeatShortcutBinding)
            }
            HStack(spacing: 8) {
                ForEach(Array(zip(RepeatOption.names.indices, RepeatOption.names)), id: \.0) { offset, name in
                    let day = offset + 1
                    Button {
                        toggle(day)
                    } label: {
                        Text(name)
                            .font(.footnote.weight(.semibold))
                            .frame(width: 38, height: 38)
                            .foregroundStyle(alarm.repeatOption.days.contains(day) ? .black : .white)
                    }
                    .buttonStyle(.glass)
                    .tint(alarm.repeatOption.days.contains(day) ? Palette.accent : nil)
                }
            }
        }
        .glassPanel()
    }

    private var repeatShortcutBinding: Binding<Int> {
        Binding {
            switch alarm.repeatOption {
            case .once: return 0
            case .everyday: return 1
            case .weekdays: return 2
            case .weekends: return 3
            case .days: return 4
            }
        } set: { value in
            switch value {
            case 0: alarm.repeatOption = .once
            case 1: alarm.repeatOption = .everyday
            case 2: alarm.repeatOption = .weekdays
            case 3: alarm.repeatOption = .weekends
            default: break
            }
        }
    }

    private func toggle(_ day: Int) {
        var days = alarm.repeatOption.days
        if days.contains(day) {
            days.remove(day)
        } else {
            days.insert(day)
        }
        alarm.repeatOption = days.isEmpty ? .once : .days(days)
    }

    private var missionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "起床使命",
                              note: alarm.missions.isEmpty ? "没设使命 = 白起" : "按顺序做完才能关")
                Spacer()
                Button {
                    showMissionPicker = true
                } label: {
                    Text(alarm.missions.isEmpty ? "添加" : "换一批")
                        .font(.footnote.weight(.semibold))
                        .padding(.vertical, 8)
                        .glassChip(tint: Palette.accent.opacity(0.4))
                }
            }
            if alarm.missions.isEmpty {
                Text("原版里这是最容易被划掉的一类。加一个：扫码 / 数学题 / 走到厨房拍张照片。")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
            } else {
                ForEach(Array(alarm.missions.enumerated()), id: \.element.id) { index, mission in
                    Button {
                        missionDraft = mission
                    } label: {
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .frame(width: 22, height: 22)
                                .glassChip(tint: Palette.cool.opacity(0.4))
                            Image(systemName: mission.kind.icon)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mission.kind.title).font(.subheadline.weight(.semibold))
                                Text(mission.summary).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.white.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                Button(role: .destructive) {
                    alarm.missions = []
                } label: {
                    Text("清空使命").font(.caption)
                }
            }

            Stepper(value: $alarm.missionTimeLimitSeconds, in: 0...600, step: 30) {
                HStack {
                    Text("单关限时")
                    Spacer()
                    Text(alarm.missionTimeLimitSeconds == 0 ? "不限"
                         : "\(alarm.missionTimeLimitSeconds) 秒")
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
            }
        }
        .glassPanel(tint: alarm.missions.isEmpty ? Color.orange.opacity(0.16) : Color.white.opacity(0.06))
    }

    private var snoozeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $alarm.snooze.enabled) {
                SectionHeader(title: "贪睡", note: "关掉贪睡才真的没有第二次机会")
            }
            .tint(Palette.accent)
            if alarm.snooze.enabled {
                Picker("间隔", selection: $alarm.snooze.minutes) {
                    ForEach(SnoozeConfig.allowedMinutes, id: \.self) { minute in
                        Text("\(minute) 分钟").tag(minute)
                    }
                }
                .pickerStyle(.menu)
                .tint(Palette.accent)
                Stepper(value: $alarm.snooze.limit, in: 0...9) {
                    HStack {
                        Text("最多几次")
                        Spacer()
                        Text(alarm.snooze.limit == 0 ? "不限" : "\(alarm.snooze.limit) 次")
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                }
            }
        }
        .glassPanel()
    }

    private var soundCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "铃声与音量")
            Button {
                showSoundPicker = true
            } label: {
                HStack {
                    Image(systemName: "speaker.wave.2.fill")
                    Text(soundTitle).fontWeight(.medium)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .foregroundStyle(.white)
                .padding(12)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            HStack {
                Text("音量")
                Slider(value: $alarm.volume, in: 0.05...1)
                    .tint(alarm.volume < 0.15 ? .orange : Palette.accent)
                Text("\(Int(alarm.volume * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 40)
            }
            .font(.footnote)
            if alarm.volume < 0.15 {
                Text("音量这么小，基本等于没设。")
                    .font(.caption2).foregroundStyle(.orange)
            }
            Picker("音量渐强", selection: $alarm.fadeInSeconds) {
                Text("关闭").tag(0)
                Text("10 秒").tag(10)
                Text("30 秒").tag(30)
                Text("60 秒").tag(60)
            }
            .pickerStyle(.menu)
            .tint(Palette.accent)
            Toggle("震动", isOn: $alarm.vibrate).tint(Palette.accent)
        }
        .glassPanel()
    }

    private var disciplineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "别让自己糊弄过去", note: "原版要开会员的，这里全给你")
            Picker("无人操作自动收起", selection: $alarm.autoDismissSeconds) {
                Text("永不").tag(0)
                Text("1 分钟").tag(60)
                Text("3 分钟").tag(180)
                Text("10 分钟").tag(600)
            }
            .pickerStyle(.menu)
            .tint(Palette.accent)
            Picker("最长响铃", selection: $alarm.ringLimitMinutes) {
                ForEach([5, 10, 15, 30, 60], id: \.self) { minute in
                    Text("\(minute) 分钟").tag(minute)
                }
            }
            .pickerStyle(.menu)
            .tint(Palette.accent)
            Toggle("删除这条要先做一次使命", isOn: $alarm.requiresMissionToDelete)
                .tint(Palette.accent)
            Toggle("启用", isOn: $alarm.enabled).tint(Palette.accent)
        }
        .glassPanel(tint: Color.white.opacity(0.06))
    }

    private var soundTitle: String {
        switch alarm.sound {
        case .builtIn(let file): return SoundCatalog.sound(named: file)?.title ?? file
        case .musicLibrary(_, let title): return title
        case .recording(_, let title): return title
        case .silence: return "静音"
        }
    }

    private func save() {
        var edited = alarm
        edited.hour = hours
        edited.minute = minutes
        store.upsert(edited)
        dismiss()
    }
}

// MARK: - 一行可点的小胶囊选项

private struct FlowlessRow: View {
    let items: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, title in
                Button {
                    selection = index
                } label: {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(index == selection ? .black : .white)
                }
                .buttonStyle(.glass)
                .tint(index == selection ? Palette.accent : nil)
            }
        }
    }
}
