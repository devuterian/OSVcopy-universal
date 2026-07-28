import Foundation
import UserNotifications

enum OrganizeNotifications {
    static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    @MainActor
    static func notifyFinished(success: Int, skipped: Int, failed: Int, preview: Bool) {
        let content = UNMutableNotificationContent()
        content.title = preview ? "OSVcopy 미리보기 완료" : "OSVcopy 정리 완료"
        content.body = "성공 \(success), 건너뜀 \(skipped), 실패 \(failed)"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let id = "osvcopy-done-\(UUID().uuidString)"
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }
}
