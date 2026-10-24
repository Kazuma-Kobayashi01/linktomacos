import AppKit
import LinkCore
import UserNotifications
import os

private let log = Logger(subsystem: "com.linktomacos.mac", category: "notifications")

/// 把手机通知显示为 macOS 系统通知，并在手机端清除时同步移除。
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let iconDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("phone-icons", isDirectory: true)

    override init() {
        super.init()
        center.delegate = self
        try? FileManager.default.createDirectory(at: iconDirectory, withIntermediateDirectories: true)
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            log.info("authorization granted=\(granted) error=\(String(describing: error))")
        }
    }

    func post(_ notification: PhoneNotification, from deviceName: String) {
        let content = UNMutableNotificationContent()
        content.title = notification.title.isEmpty ? notification.appName : notification.title
        content.subtitle = notification.title.isEmpty ? "" : notification.appName
        content.body = notification.text
        content.threadIdentifier = notification.packageName
        content.sound = .default
        if let subText = notification.subText, !subText.isEmpty {
            content.subtitle = "\(notification.appName) · \(subText)"
        }
        if let attachment = iconAttachment(for: notification) {
            content.attachments = [attachment]
        }
        // 同一个 key 的通知（如消息更新）会替换已显示的那条
        let request = UNNotificationRequest(identifier: notification.key, content: content, trigger: nil)
        center.add(request) { error in
            if let error { log.error("post failed: \(error)") }
            else { log.info("posted from \(notification.packageName, privacy: .public)") }
        }
    }

    func remove(key: String) {
        center.removeDeliveredNotifications(withIdentifiers: [key])
    }

    func removeAll() {
        center.removeAllDeliveredNotifications()
    }

    /// 图标以缩略图形式附在通知右侧。附件必须是文件，写到临时目录，按包名缓存。
    private func iconAttachment(for notification: PhoneNotification) -> UNNotificationAttachment? {
        guard let base64 = notification.iconPng, let data = Data(base64Encoded: base64) else { return nil }
        let url = iconDirectory.appendingPathComponent("\(notification.packageName).png")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url)
        }
        // 系统会把附件文件移走，所以每次用一份拷贝
        let copy = iconDirectory.appendingPathComponent("\(UUID().uuidString).png")
        try? FileManager.default.copyItem(at: url, to: copy)
        return try? UNNotificationAttachment(identifier: "icon", url: copy, options: nil)
    }

    // 本 App 是菜单栏常驻程序，视为前台，必须显式允许在前台弹出横幅
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
