import SwiftUI
import UIKit
import UserNotifications

@main
struct BiqiAlarmApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = AlarmStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(AppSettings.shared)
                .preferredColorScheme(AppSettings.shared.themeDark ? .dark : nil)
                .tint(Palette.accent)
                .task { await store.bootstrap() }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil)
    -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // 前台收到自己的闹钟通知也要出声，不然会静默
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification,
                               withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        let info = response.notification.request.content.userInfo
        guard let alarmID = info["alarmID"] as? String else { return }
        let fire = (info["fireAt"] as? Double).map { Date(timeIntervalSince1970: $0) }
        Task { @MainActor in
            AlarmStore.shared.handleNotification(alarmIDString: alarmID, fireDate: fire)
        }
    }
}
