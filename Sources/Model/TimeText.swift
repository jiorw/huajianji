import Foundation

/// 「距今多久」的口语化标签
enum TimeText {
    static func since(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "不知道是哪一天" }
        let day = Calendar.current.dateComponents([.day], from: date, to: now).day ?? 0
        switch day {
        case ..<0: return "就在今天"
        case 0: return "就在今天"
        case 1: return "就是昨天"
        case..<7: return "是很近 · \(day) 天前"
        case..<31: return "\(day / 7) 周前"
        case..<365: return "\(day / 31) 个月前"
        case..<365 * 3: return "\(day / 365) 年前"
        case..<365 * 8: return "\(day / 365) 年前 · 很久以前"
        default: return "很久很久以前"
        }
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 HH:mm"
        return f
    }()

    static func precise(_ date: Date?) -> String {
        guard let date else { return "没有时间信息" }
        return formatter.string(from: date)
    }
}
