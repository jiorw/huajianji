import Foundation
import SwiftUI

// MARK: - 全局设置（原版散在各处的 Premium 开关，这里全部默认打开）

@Observable
final class AppSettings {
    static let shared = AppSettings()

    var themeDark: Bool = true
    var defaultSnoozeMinutes: Int = 10
    var defaultVolume: Double = 0.85
    var defaultFadeInSeconds: Int = 0
    var defaultSound: String = "DigitalAlarm"

    /// 「必起」：没做完使命，闹钟不会因为时间到就自己停
    var unbeatable: Bool = true
    /// 响铃时按音量键不减轻
    var ignoreSilenceSwitch: Bool = true
    /// 贪睡到第三次之后强制做使命
    var snoozeBeforeMission: Int = 0
    /// 起床打卡后多久算「真起来了」
    var wakeWindowMinutes: Int = 30
    var motivationalQuotes: Bool = true
    var quoteCategory: Int = 0
    var keepScreenOnWhileRinging: Bool = true
    var morningReminderHour: Int = 21
    var morningReminderMinute: Int = 30
    var morningReminderOn: Bool = false

    private let key = "biqi.settings.v1"

    private struct Snapshot: Codable {
        var themeDark: Bool
        var defaultSnoozeMinutes: Int
        var defaultVolume: Double
        var defaultFadeInSeconds: Int
        var defaultSound: String
        var unbeatable: Bool
        var ignoreSilenceSwitch: Bool
        var snoozeBeforeMission: Int
        var wakeWindowMinutes: Int
        var motivationalQuotes: Bool
        var quoteCategory: Int
        var keepScreenOnWhileRinging: Bool
        var morningReminderHour: Int
        var morningReminderMinute: Int
        var morningReminderOn: Bool
    }

    private init() {}

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        themeDark = snap.themeDark
        defaultSnoozeMinutes = snap.defaultSnoozeMinutes
        defaultVolume = snap.defaultVolume
        defaultFadeInSeconds = snap.defaultFadeInSeconds
        defaultSound = snap.defaultSound
        unbeatable = snap.unbeatable
        ignoreSilenceSwitch = snap.ignoreSilenceSwitch
        snoozeBeforeMission = snap.snoozeBeforeMission
        wakeWindowMinutes = snap.wakeWindowMinutes
        motivationalQuotes = snap.motivationalQuotes
        quoteCategory = snap.quoteCategory
        keepScreenOnWhileRinging = snap.keepScreenOnWhileRinging
        morningReminderHour = snap.morningReminderHour
        morningReminderMinute = snap.morningReminderMinute
        morningReminderOn = snap.morningReminderOn
    }

    func save() {
        let snap = Snapshot(themeDark: themeDark, defaultSnoozeMinutes: defaultSnoozeMinutes,
                            defaultVolume: defaultVolume, defaultFadeInSeconds: defaultFadeInSeconds,
                            defaultSound: defaultSound, unbeatable: unbeatable,
                            ignoreSilenceSwitch: ignoreSilenceSwitch,
                            snoozeBeforeMission: snoozeBeforeMission,
                            wakeWindowMinutes: wakeWindowMinutes, motivationalQuotes: motivationalQuotes,
                            quoteCategory: quoteCategory, keepScreenOnWhileRinging: keepScreenOnWhileRinging,
                            morningReminderHour: morningReminderHour,
                            morningReminderMinute: morningReminderMinute, morningReminderOn: morningReminderOn)
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    var backgroundGradient: LinearGradient { themeDark ? Palette.night : Palette.dawn }
}
