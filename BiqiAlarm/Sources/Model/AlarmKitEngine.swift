import Foundation
import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI

// MARK: - AlarmKit 桥接：只负责「系统层一定叫得醒」
//
// 系统响铃界面的停止按钮无法拦截，所以使命屏障不在这里做；
// AlarmKit 的价值是穿透静音拨片和专注模式，这个通知做不到。

struct MissionMeta: AlarmMetadata {
    let alarmID: String
}

struct OpenMissionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "完成使命"
    static var description = IntentDescription("打开必起，做完起床使命才能关掉闹钟")
    static var openAppWhenRun: Bool = true

    @Parameter(name: "闹钟ID")
    var alarmID: String

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    init() {
        self.alarmID = ""
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AlarmStore.shared.handleNotification(alarmIDString: alarmID, fireDate: Date())
        return .result()
    }
}

@MainActor
enum AlarmKitEngine {
    /// iOS 26.0 的 AlarmPresentation.Alert 只有带 stopButton 的旧 init，
    /// 我们按 26.1+ 的写法编译，所以 26.0 设备退回纯通知方案。
    static var isSupported: Bool {
        if #available(iOS 26.1, *) { return true }
        return false
    }

    static var statusText: String {
        guard isSupported else { return "当前系统版本不支持系统级闹钟，已改用通知叫醒" }
        switch currentAuthorization() {
        case .granted: return "已授权，专注模式下也能响"
        case .denied: return "被拒绝，闹钟只能在应用内响"
        default: return "还没授权"
        }
    }

    static func currentAuthorization() -> PermissionState {
        switch AlarmManager.shared.authorizationState {
        case .authorized: return .granted
        case .denied: return .denied
        default: return .unknown
        }
    }

    static func requestAuthorization() async -> Bool {
        guard isSupported else { return false }
        do {
            return try await AlarmManager.shared.requestAuthorization() == .authorized
        } catch {
            NSLog("AlarmKit 授权失败: \(error)")
            return false
        }
    }

    static func cancel(id: UUID) {
        guard isSupported else { return }
        do { try AlarmManager.shared.cancel(id: id) } catch { NSLog("取消系统闹钟: \(error)") }
    }

    static func cancelAll() {
        guard isSupported else { return }
        guard let alarms = try? AlarmManager.shared.alarms else { return }
        for alarm in alarms {
            do { try AlarmManager.shared.cancel(id: alarm.id) } catch { NSLog("cancel \(error)") }
        }
    }

    /// 只为「最近会响的那一条」排系统闹钟，避免撞系统数量上限
    static func sync(nextAlarm alarm: AlarmItem?, snoozeDate: Date?) {
        cancelAll()
        guard isSupported, let alarm else { return }

        if #available(iOS 26.1, *) {
            let presentation = AlarmPresentation(
                alert: AlarmPresentation.Alert(
                    title: "\(alarm.timeTitle) \(alarm.displayName)",
                    secondaryButton: AlarmButton(text: "完成使命", textColor: .white,
                                                 systemImageName: "figure.walk"),
                    secondaryButtonBehavior: .custom))

            guard let attributes = configuredAttributes(presentation: presentation, alarmID: alarm.id) else { return }
            let sound = SoundCatalog.url(for: alarm.builtInFileName ?? "DigitalAlarm") == nil
                ? AlertConfiguration.AlertSound.default
                : .named((alarm.builtInFileName ?? "DigitalAlarm") + ".wav")

            let schedule: Alarm.Schedule
            if let snoozeDate {
                schedule = .fixed(snoozeDate)
            } else if let date = alarm.nextFireDate() {
                // 有明确日期就按日期排；重复闹钟交给下面的 weekly 表达
                schedule = alarm.repeatOption.days.isEmpty
                    ? .fixed(date)
                    : .relative(.init(time: .init(hour: alarm.hour, minute: alarm.minute),
                                      repeats: .weekly(alarm.localeWeekdays)))
            } else {
                return
            }

            let configuration = AlarmManager.AlarmConfiguration<MissionMeta>.alarm(
                schedule: schedule,
                attributes: attributes,
                stopIntent: nil,
                secondaryIntent: OpenMissionIntent(alarmID: alarm.id.uuidString),
                sound: sound)

            Task {
                do { _ = try await AlarmManager.shared.schedule(id: alarm.id, configuration: configuration) }
                catch { NSLog("系统闹钟排期失败: \(error)") }
            }
        }
    }

    @available(iOS 26.1, *)
    private static func configuredAttributes(presentation: AlarmPresentation,
                                            alarmID: UUID) -> AlarmAttributes<MissionMeta>? {
        AlarmAttributes<MissionMeta>(presentation: presentation,
                                     metadata: MissionMeta(alarmID: alarmID.uuidString),
                                     tintColor: Palette.accent)
    }
}

extension AlarmItem {
    var builtInFileName: String? {
        if case .builtIn(let file) = sound { return file }
        return nil
    }

    var localeWeekdays: [Locale.Weekday] {
        let table: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        return repeatOption.days.sorted().compactMap { index in
            table.indices.contains(index - 1) ? table[index - 1] : nil
        }
    }
}
