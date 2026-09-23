import Foundation
import SwiftUI
import UserNotifications

// MARK: - 正在响的状态

struct RingingState: Equatable {
    let alarm: AlarmItem
    let fireDate: Date
    var startedAt: Date = Date()
    var snoozeCount: Int = 0
    var missionIndex: Int = 0
    var elapsedMissions: Int = 0

    var remainingMissions: Int {
        max(0, alarm.missions.count - missionIndex)
    }
}

// MARK: - 通知授权状态

enum PermissionState: Equatable {
    case unknown, granted, denied
}

// MARK: - 主存储

@MainActor
@Observable
final class AlarmStore {
    static let shared = AlarmStore()

    private(set) var alarms: [AlarmItem] = []
    var ringing: RingingState?
    var notificationState: PermissionState = .unknown
    var alarmKitState: PermissionState = .unknown
    var lastError: String?
    var deleteGate: UUID?          // 需要做完使命才能删除的那条闹钟

    private let settings = AppSettings.shared
    private var tickTimer: Timer?
    private var loaded = false
    private var handledFireDates: [UUID: Date] = [:]

    private var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("BiqiData/alarms.json")
    }

    private init() {}

    // MARK: 载入 / 保存

    func bootstrap() async {
        load()
        NotificationEngine.registerCategories()
        await refreshAuthorization()
        await resync()
        loaded = true
        startTicking()
    }

    private func load() {
        guard !loaded else { return }
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([AlarmItem].self, from: data) else {
            if alarms.isEmpty {
                alarms = [AlarmItem.demo()]
                save()
            }
            return
        }
        alarms = list
    }

    private func save() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(alarms) else { return }
        try? data.write(to: fileURL)
    }

    // MARK: 授权

    func refreshAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let options = await center.notificationSettings().authorizationStatus
        switch options {
        case .authorized, .provisional, .ephemeral: notificationState = .granted
        case .denied: notificationState = .denied
        default: notificationState = .unknown
        }
        if AlarmKitEngine.isSupported {
            alarmKitState = AlarmKitEngine.currentAuthorization()
        }
    }

    func requestNotificationPermission() async {
        let granted = await NotificationEngine.requestAuthorization()
        notificationState = granted ? .granted : .denied
        if granted { await resync() }
    }

    func requestAlarmKitPermission() async {
        let granted = await AlarmKitEngine.requestAuthorization()
        alarmKitState = granted ? .granted : .denied
        await resync()
    }

    // MARK: CRUD

    func newAlarm() -> AlarmItem {
        var alarm = AlarmItem()
        alarm.sound = .builtIn(settings.defaultSound)
        alarm.volume = settings.defaultVolume
        alarm.fadeInSeconds = settings.defaultFadeInSeconds
        alarm.snooze.minutes = settings.defaultSnoozeMinutes
        alarm.missions = [MissionConfig.default(.math)]
        return alarm
    }

    func upsert(_ alarm: AlarmItem) {
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index] = alarm
        } else {
            alarms.append(alarm)
        }
        save()
        Task { await resync() }
    }

    func remove(_ alarm: AlarmItem) {
        alarms.removeAll { $0.id == alarm.id }
        NotificationEngine.cancel(alarmID: alarm.id)
        AlarmKitEngine.cancel(id: alarm.id)
        save()
        Task { await resync() }
    }

    func setEnabled(_ enabled: Bool, for alarm: AlarmItem) {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        alarms[index].enabled = enabled
        save()
        Task { await resync() }
    }

    func duplicate(_ alarm: AlarmItem) {
        var copy = alarm
        copy.id = UUID()
        copy.enabled = false
        copy.label = alarm.label.isEmpty ? "副本" : alarm.label + " 副本"
        alarms.append(copy)
        save()
    }

    var sortedAlarms: [AlarmItem] {
        alarms.sorted {
            guard let a = $0.nextFireDate(), let b = $1.nextFireDate() else {
                return $0.nextFireDate() != nil
            }
            return a < b
        }
    }

    var nextAlarm: AlarmItem? {
        sortedAlarms.first { $0.enabled && $0.nextFireDate() != nil }
    }

    // MARK: 排期

    func resync() async {
        let enabled = alarms.filter(\.enabled)
        let evening = settings.morningReminderOn
            ? EveningReminder(title: "准备好明天的自己",
                              body: "56% 的人用数学题叫醒自己，要不要试一下？",
                              hour: settings.morningReminderHour,
                              minute: settings.morningReminderMinute)
            : nil
        await NotificationEngine.sync(with: enabled, eveningReminder: evening)
        AlarmKitEngine.sync(nextAlarm: nextAlarm, snoozeDate: nil)
    }

    // MARK: 响铃

    private func startTicking() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in AlarmStore.shared.handleTick() }
        }
    }

    /// App 在前台时靠这里捕捉到点；在后台时靠通知
    func handleTick() {
        guard ringing == nil, loaded else { return }
        let now = Date()
        for alarm in alarms where alarm.enabled {
            guard let fire = alarm.nextFireDate(before: now) else { continue }
            if handledFireDates[alarm.id] == fire { continue }
            guard now.timeIntervalSince(fire) < 120 else { continue }
            handledFireDates[alarm.id] = fire
            beginRinging(alarmID: alarm.id, fireDate: fire)
            return
        }
    }

    func beginRinging(alarmID: UUID, fireDate: Date) {
        guard ringing == nil else { return }
        guard let stored = alarms.first(where: { $0.id == alarmID }) else { return }
        handledFireDates[alarmID] = fireDate
        var alarm = stored

        // 贪睡到一定次数，没设使命的闹钟也硬塞一道数学题
        if alarm.missions.isEmpty, settings.snoozeBeforeMission > 0 {
            let recent = WakeLog.shared.events.filter {
                $0.alarmID == alarmID && $0.kind == .snoozed
                    && Date().timeIntervalSince($0.actionDate) < 90 * 60
            }.count
            if recent >= settings.snoozeBeforeMission {
                alarm.missions = [MissionConfig.default(.math)]
            }
        }

        ringing = RingingState(alarm: alarm, fireDate: fireDate)
        RingPlayer.shared.start(choice: alarm.sound,
                                volume: settings.unbeatable ? max(alarm.volume, 0.6) : alarm.volume,
                                fadeInSeconds: alarm.fadeInSeconds,
                                vibrate: alarm.vibrate,
                                loopWhileSilent: settings.ignoreSilenceSwitch)
        NotificationEngine.scheduleEscalation(for: alarm, from: fireDate)
    }

    func handleNotification(alarmIDString: String, fireDate: Date?) {
        guard let uuid = UUID(uuidString: alarmIDString) else { return }
        beginRinging(alarmID: uuid, fireDate: fireDate ?? Date())
    }

    func snoozeCurrent() {
        guard var state = ringing else { return }
        let alarm = state.alarm
        if alarm.snooze.enabled, alarm.snooze.limit > 0, state.snoozeCount >= alarm.snooze.limit {
            lastError = "贪睡次数用完了，起来做使命"
            return
        }
        state.snoozeCount += 1
        ringing = state
        RingPlayer.shared.stop()
        NotificationEngine.cancel(alarmID: alarm.id)

        let minutes = TimeInterval(max(1, alarm.snooze.minutes) * 60)
        let until = Date().addingTimeInterval(minutes)
        WakeLog.shared.record(WakeEvent(alarmID: alarm.id, alarmLabel: alarm.displayName,
                                        fireDate: state.fireDate, actionDate: Date(),
                                        kind: .snoozed, snoozeCount: state.snoozeCount))
        AlarmKitEngine.sync(nextAlarm: alarm, snoozeDate: until)
        Task {
            await NotificationEngine.syncSnooze(alarm: alarm, until: until)
        }
    }

    /// 使命链走完
    func completeMission() {
        guard var state = ringing else { return }
        let alarm = state.alarm
        state.missionIndex += 1
        state.elapsedMissions += 1
        if state.missionIndex < alarm.missions.count {
            ringing = state
            return
        }
        finish(alarm: alarm, state: state, kind: alarm.missions.isEmpty ? .plain : .missionDone)
    }

    /// 无使命闹钟的普通关闭 / 超时收起
    func dismissWithoutMission(kind: WakeKind = .plain) {
        guard let state = ringing, let alarm = alarms.first(where: { $0.id == state.alarm.id }) else { return }
        finish(alarm: alarm, state: state, kind: kind)
    }

    private func finish(alarm: AlarmItem, state: RingingState, kind: WakeKind) {
        RingPlayer.shared.stop()
        NotificationEngine.cancel(alarmID: alarm.id)
        AlarmKitEngine.cancel(id: alarm.id)
        ringing = nil

        var verdict = kind
        // 超过起床有效窗口才关掉：算你睡过去了，不给记成功
        if verdict == .plain,
           Date().timeIntervalSince(state.fireDate) > TimeInterval(settings.wakeWindowMinutes * 60) {
            verdict = .missed
        }
        WakeLog.shared.record(WakeEvent(alarmID: alarm.id, alarmLabel: alarm.displayName,
                                        fireDate: state.fireDate, actionDate: Date(),
                                        kind: verdict, snoozeCount: state.snoozeCount,
                                        missionSeconds: Int(Date().timeIntervalSince(state.startedAt))))

        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            if case .once = alarm.repeatOption { alarms[index].enabled = false }
            save()
        }
        Task { await resync() }
    }

    // MARK: 快速闹钟（原版 quick_alarm：立刻开始一段叫醒流程）

    func startQuickAlarm(minutes: Int, mission: MissionConfig) {
        let fire = Date().addingTimeInterval(TimeInterval(minutes * 60))
        var alarm = newAlarm()
        alarm.id = UUID()
        alarm.hour = Calendar.current.component(.hour, from: fire)
        alarm.minute = Calendar.current.component(.minute, from: fire)
        alarm.label = "快速闹钟"
        alarm.repeatOption = .once
        alarm.missions = mission.kind == .none ? [] : [mission]
        alarms.append(alarm)
        save()
        Task {
            await NotificationEngine.syncNudge(alarm: alarm, at: fire)
            AlarmKitEngine.sync(nextAlarm: alarm, snoozeDate: fire)
        }
    }
}

private extension AlarmItem {
    static func demo() -> AlarmItem {
        var alarm = AlarmItem()
        alarm.hour = 7
        alarm.minute = 10
        alarm.label = "早安"
        alarm.repeatOption = .weekdays
        alarm.missions = [MissionConfig.default(.math), MissionConfig.default(.walk)]
        alarm.sound = .builtIn("DigitalAlarm")
        return alarm
    }

    /// 用来判断「刚刚有没有响过」：把下一次时刻限制在 now 之前最近的一次
    func nextFireDate(before now: Date) -> Date? {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let startOfToday = calendar.startOfDay(for: now)
        let days = repeatOption.days
        for offset in (0...2).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: startOfToday) else { continue }
            if case .days = repeatOption, !days.isEmpty,
               !days.contains(calendar.component(.weekday, from: day)) { continue }
            switch repeatOption {
            case .weekdays:
                let wd = calendar.component(.weekday, from: day)
                if !(2...6).contains(wd) { continue }
            case .weekends:
                let wd = calendar.component(.weekday, from: day)
                if !(wd == 1 || wd == 7) { continue }
            default: break
            }
            guard let date = calendar.date(byAdding: .second,
                                           value: hour * 3600 + minute * 60, to: day) else { continue }
            if date <= now, now.timeIntervalSince(date) < 3600 { return date }
        }
        return nil
    }
}
