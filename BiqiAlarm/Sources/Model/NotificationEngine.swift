import Foundation
import UserNotifications

// MARK: - 本地通知引擎：使命屏障的主力
//
// AlarmKit 的「停止」按钮是系统给的、拦不住，所以「不做任务关不掉」靠这里：
// 到点先响，之后按 escalating 间隔继续轰炸，直到用户在 App 里做完使命为止。

@MainActor
enum NotificationEngine {
    static let ringCategory = "BIQI_RING"
    static let reminderCategory = "BIQI_REMIND"

    private static var prefix: String { "biqi-" }

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            NSLog("通知授权失败: \(error)")
            return false
        }
    }

    static func registerCategories() {
        let mission = UNNotificationAction(identifier: "BIQI_MISSION",
                                           title: "起来做使命",
                                           options: [.foreground])
        let stop = UNNotificationAction(identifier: "BIQI_OPEN",
                                        title: "打开必起",
                                        options: [.foreground])
        let ring = UNNotificationCategory(identifier: ringCategory,
                                          actions: [mission, stop],
                                          intentIdentifiers: [],
                                          options: [])
        let remind = UNNotificationCategory(identifier: reminderCategory, actions: [],
                                           intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([ring, remind])
    }

    /// 清掉本 App 排的全部闹钟通知
    static func clearAllAlarms() async {
        let center = UNUserNotificationCenter.current()
        let ids = (await center.pendingNotificationRequests()).map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// 为每条启用的闹钟排「下一次会响」的通知；最近的几条额外排轰炸序列
    static func sync(with alarms: [AlarmItem], eveningReminder: EveningReminder?) async {
        let center = UNUserNotificationCenter.current()
        await clearAllAlarms()

        var scheduled = 0
        let sorted = alarms.compactMap { alarm -> (AlarmItem, Date)? in
            guard alarm.enabled, let date = alarm.nextFireDate() else { return nil }
            return (alarm, date)
        }.sorted { $0.1 < $1.1 }

        for (alarm, date) in sorted {
            guard scheduled < 56 else { break }
            scheduleBurst(for: alarm, firstFire: date, escalating: scheduled < 3)
            scheduled += 1
        }

        if let eveningReminder, let date = eveningReminder.nextDate() {
            let content = UNMutableNotificationContent()
            content.title = eveningReminder.title
            content.body = eveningReminder.body
            content.categoryIdentifier = reminderCategory
            add(request(with: content, date: date, id: "biqi-evening"))
        }
    }

    /// 响铃期间（App 活着时）继续追加提醒，保证划掉通知还在响
    static func scheduleEscalation(for alarm: AlarmItem, from date: Date) {
        scheduleBurst(for: alarm, firstFire: date.addingTimeInterval(45), escalating: true)
    }

    /// 贪睡到点：只排一条，但到了会再自己续炸
    static func syncSnooze(alarm: AlarmItem, until date: Date) async {
        let id = "biqi-snooze-\(alarm.id.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        add(request(with: ringContent(for: alarm), date: date, id: id))
    }

    /// 快速闹钟：定好时间排一条
    static func syncNudge(alarm: AlarmItem, at date: Date) async {
        await clearAllAlarms()
        scheduleBurst(for: alarm, firstFire: date, escalating: true)
    }

    static func cancel(alarmID: UUID) {
        let center = UNUserNotificationCenter.current()
        let ids = ["biqi-ring-\(alarmID.uuidString)"] + (0..<12).map { "biqi-burst-\(alarmID.uuidString)-\($0)" }
            + ["biqi-snooze-\(alarmID.uuidString)"]
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - 内部

    private static func scheduleBurst(for alarm: AlarmItem, firstFire: Date, escalating: Bool) {
        let content = ringContent(for: alarm)
        add(request(with: content, date: firstFire, id: "biqi-ring-\(alarm.id.uuidString)"))
        guard escalating else { return }

        // 越等越短的间隔，最长续到用户设定的响铃上限
        let gaps: [TimeInterval] = [45, 60, 60, 120, 120, 180, 180, 300, 300, 300, 300, 300]
        var cursor = firstFire
        let limit = firstFire.addingTimeInterval(TimeInterval(alarm.ringLimitMinutes * 60))
        for (index, gap) in gaps.enumerated() {
            cursor = cursor.addingTimeInterval(gap)
            if cursor > limit { break }
            add(request(with: content, date: cursor, id: "biqi-burst-\(alarm.id.uuidString)-\(index)"))
        }
    }

    private static func ringContent(for alarm: AlarmItem) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = alarm.label.isEmpty ? "起床！" : alarm.label
        let missionText = alarm.missions.first.map { "「\($0.kind.title)」没做完是关不掉的" } ?? "点一下就能起"
        content.body = "\(alarm.timeTitle) · \(missionText)"
        content.sound = alarm.sound.notificationSound
        content.categoryIdentifier = ringCategory
        content.threadIdentifier = "biqi-\(alarm.id.uuidString)"
        content.userInfo = ["alarmID": alarm.id.uuidString, "fireAt": alarm.nextFireDate()?.timeIntervalSince1970 ?? 0]
        // 不用 .critical（要 entitlement），timeSensitive 在专注模式下由用户放行
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1
        return content
    }

    private static func add(_ request: UNNotificationRequest) {
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("排通知失败: \(error.localizedDescription)") }
        }
    }

    private static func request(with content: UNNotificationContent, date: Date, id: String) -> UNNotificationRequest {
        let interval = max(1, date.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }
}

// MARK: - 明晚提醒（原版 xday_noti）

struct EveningReminder {
    let title: String
    let body: String
    let hour: Int
    let minute: Int

    func nextDate() -> Date? {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        guard let today = calendar.date(byAdding: .second, value: hour * 3600 + minute * 60, to: startOfToday)
        else { return nil }
        return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today)
    }
}

private extension SoundChoice {
    var notificationSound: UNNotificationSound? {
        switch self {
        case .builtIn(let file):
            guard SoundCatalog.url(for: file) != nil else { return .default }
            return UNNotificationSound(named: UNNotificationSoundName(file + ".wav"))
        case .musicLibrary, .recording, .silence:
            return .default
        }
    }
}
