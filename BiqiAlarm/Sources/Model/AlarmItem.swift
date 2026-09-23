import Foundation

// MARK: - 重复方式

enum RepeatOption: Hashable, Codable {
    case once
    case everyday
    case weekdays
    case weekends
    case days(Set<Int>)   // 1 = 周日 ... 7 = 周六

    var symbolTitle: String {
        switch self {
        case .once: return "不重复"
        case .everyday: return "每天"
        case .weekdays: return "工作日"
        case .weekends: return "周末"
        case .days(let set):
            if set.isEmpty { return "不重复" }
            if set == Set(2...6) { return "工作日" }
            if set == [1, 7] { return "周末" }
            if set == Set(1...7) { return "每天" }
            return set.sorted().map { Self.names[$0 - 1] }.joined(separator: " ")
        }
    }

    static let names = ["日", "一", "二", "三", "四", "五", "六"]

    var days: Set<Int> {
        switch self {
        case .once: return []
        case .everyday: return Set(1...7)
        case .weekdays: return Set(2...6)
        case .weekends: return [1, 7]
        case .days(let set): return set
        }
    }
}

// MARK: - 贪睡

struct SnoozeConfig: Hashable, Codable {
    var enabled: Bool = true
    var minutes: Int = 10
    var limit: Int = 3        // 最多贪睡几次，0 = 不限

    static let allowedMinutes = [1, 2, 3, 5, 10, 15, 20, 30]
}

// MARK: - 铃声来源

enum SoundChoice: Hashable, Codable {
    case builtIn(String)                 // bundle 里的 wav 文件名（不含扩展名）
    case musicLibrary(itemID: String, title: String)
    case recording(url: String, title: String)
    case silence
}

// MARK: - 闹钟

struct AlarmItem: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var hour: Int = 7
    var minute: Int = 0
    var label: String = ""
    var enabled: Bool = true
    var repeatOption: RepeatOption = .everyday
    var snooze: SnoozeConfig = SnoozeConfig()
    var sound: SoundChoice = .builtIn("DigitalAlarm")
    var volume: Double = 0.85
    var fadeInSeconds: Int = 0            // 音量渐强时长，0 = 关闭
    var vibrate: Bool = true
    var autoDismissSeconds: Int = 0       // 无人操作自动收起，0 = 永不
    var missions: [MissionConfig] = []
    var missionTimeLimitSeconds: Int = 0  // 0 = 不限时
    var requiresMissionToDelete: Bool = false
    var ringLimitMinutes: Int = 30        // 超过这么久没理它就算「睡过去了」

    var timeTitle: String { String(format: "%02d:%02d", hour, minute) }

    var displayName: String {
        label.isEmpty ? (repeatOption.days.isEmpty ? "闹钟" : "闹钟 · \(repeatOption.symbolTitle)") : label
    }

    /// 只考虑 24 小时内下一次响的时刻；nil = 今天起不会再响（不重复且时间已过）
    func nextFireDate(from now: Date = Date()) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let startOfToday = calendar.startOfDay(for: now)
        let days = repeatOption.days

        for offset in 0..<8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday) else { continue }
            guard let date = calendar.date(byAdding: .second,
                                           value: hour * 3600 + minute * 60,
                                           to: day) else { continue }
            if !date.after(now) { continue }
            switch repeatOption {
            case .once:
                if offset < 2 { return date }        // 今天没过期就今天，否则算明天
            case .everyday:
                return date
            case .weekdays, .weekends, .days:
                let weekday = calendar.component(.weekday, from: date)
                if days.contains(weekday) { return date }
            }
        }
        return nil
    }

    var nextFireText: String {
        guard let date = nextFireDate() else { return "已关闭" }
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
        if date < tomorrow { return "今天 \(timeTitle)" }
        if date < calendar.date(byAdding: .day, value: 2, to: startOfToday) ?? tomorrow { return "明天 \(timeTitle)" }
        let weekday = calendar.component(.weekday, from: date)
        return "周\(RepeatOption.names[weekday - 1]) \(timeTitle)"
    }

    /// 「必起」口径下这条闹钟当天是否被真正起过
    func countDownText(to date: Date) -> String {
        let seconds = Int(date.timeIntervalSinceNow)
        if seconds <= 0 { return "正在响" }
        let hours = seconds / 3600, minutes = seconds % 3600 / 60
        if hours > 0 { return "\(hours) 小时 \(minutes) 分后" }
        if minutes > 0 { return "\(minutes) 分后" }
        return "\(seconds) 秒后"
    }
}
