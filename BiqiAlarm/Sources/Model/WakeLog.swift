import Foundation

// MARK: - 起床记录

enum WakeKind: String, Codable {
    case missionDone    // 做完使命起床
    case plain          // 没有使命，直接关
    case snoozed        // 贪睡过
    case missed         // 一直没理，响到超时
}

struct WakeEvent: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var alarmID: UUID?
    var alarmLabel: String
    var fireDate: Date
    var actionDate: Date
    var kind: WakeKind
    var snoozeCount: Int = 0
    var missionSeconds: Int = 0

    var wokeUp: Bool { kind == .missionDone || kind == .plain }

    /// 从响到真正起床花了多久（含贪睡）
    var costMinutes: Int { max(0, Int(actionDate.timeIntervalSince(fireDate)) / 60) }
}

// MARK: - 评分（对齐原版的效率 / 规律性 / 相对分数）

struct WakeReport {
    let events: [WakeEvent]

    var scheduledCount: Int { events.count }
    var wokeCount: Int { events.filter(\.wokeUp).count }

    var successRate: Double {
        scheduledCount == 0 ? 0 : Double(wokeCount) / Double(scheduledCount)
    }

    /// 效率：起床耗时越短、贪睡越少越高
    var efficiency: Int {
        let done = events.filter(\.wokeUp)
        guard !done.isEmpty else { return 0 }
        let avgCost = Double(done.reduce(0) { $0 + $1.costMinutes }) / Double(done.count)
        let avgSnooze = Double(done.reduce(0) { $0 + $1.snoozeCount }) / Double(done.count)
        let costScore = max(0.0, 1.0 - min(avgCost, 45) / 45.0)
        let snoozeScore = max(0.0, 1.0 - min(avgSnooze, 4) / 4.0)
        let missionScore = Double(done.filter { $0.kind == .missionDone }.count) / Double(done.count)
        return Int((costScore * 0.45 + snoozeScore * 0.3 + missionScore * 0.25) * 100)
    }

    /// 规律性：起床钟点越集中越高
    var regularity: Int {
        let times = events.filter(\.wokeUp).map { secondsOfDay($0.actionDate) }
        guard times.count > 1 else { return times.isEmpty ? 0 : 70 }
        let mean = Double(times.reduce(0, +)) / Double(times.count)
        let variance = Double(times.reduce(0) { $0 + pow(Double($1) - mean, 2) }) / Double(times.count)
        let deviation = sqrt(variance) / 60.0            // 分钟为单位的标准差
        return Int(max(0.0, 1.0 - min(deviation, 90) / 90.0) * 100)
    }

    /// 相对分数：比上周期的自己好多少
    var relativeScore: Int {
        let previous = events.filter { $0.fireDate < earlierBoundary }
        let current = events.filter { $0.fireDate >= earlierBoundary }
        guard previous.count >= 2, current.count >= 1 else { return 0 }
        let old = averageCost(previous), now = averageCost(current)
        let delta = Int((old - now) / max(old, 1) * 100)
        return max(-99, min(99, delta))
    }

    var averageWakeText: String {
        let done = events.filter(\.wokeUp)
        guard !done.isEmpty else { return "—" }
        let total = done.reduce(0) { $0 + secondsOfDay($1.actionDate) }
        let seconds = total / done.count
        return String(format: "%02d:%02d", seconds / 3600, seconds % 3600 / 60)
    }

    var totalSnooze: Int { events.reduce(0) { $0 + $1.snoozeCount } }
    var missionDoneCount: Int { events.filter { $0.kind == .missionDone }.count }

    private var earlierBoundary: Date {
        Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    }

    private func averageCost(_ list: [WakeEvent]) -> Double {
        let done = list.filter(\.wokeUp)
        guard !done.isEmpty else { return 0 }
        return Double(done.reduce(0) { $0 + $1.costMinutes }) / Double(done.count)
    }

    private func secondsOfDay(_ date: Date) -> Int {
        let c = Calendar.current.component(.hour, from: date) * 3600
            + Calendar.current.component(.minute, from: date) * 60
        return c
    }
}

// MARK: - 存储

@MainActor
final class WakeLog {
    static let shared = WakeLog()

    private(set) var events: [WakeEvent] = []
    private let fileURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("BiqiData", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("wake-events.json")
        load()
    }

    func record(_ event: WakeEvent) {
        events.append(event)
        if events.count > 1200 { events.removeFirst(events.count - 1200) }
        save()
    }

    func events(in days: Int) -> [WakeEvent] {
        let boundary = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return events.filter { $0.fireDate >= boundary }
    }

    func report(in days: Int) -> WakeReport {
        WakeReport(events: events(in: days))
    }

    func clear() {
        events = []
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([WakeEvent].self, from: data) else { return }
        events = list
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: fileURL)
    }
}
