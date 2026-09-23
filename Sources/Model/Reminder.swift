import UserNotifications

/// 每日提醒：本地通知，不需要推送证书
enum Reminder {
    static let identifier = "huajianji.daily"

    @MainActor
    static func apply(on: Bool, hour: Int, minute: Int) {
        let center = UNUserNotificationCenter.current()
        guard on else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { schedule(hour: hour, minute: minute) }
        }
    }

    @MainActor
    private static func schedule(hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = "今天会翻到哪一张呢"
        content.body = "拆一组看看，说不定能找回点什么。"
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        )
    }
}
