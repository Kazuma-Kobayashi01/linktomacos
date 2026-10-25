import SwiftUI

/// 用户偏好的键和默认值。界面用 @AppStorage 读写，其他地方用这里的读取方法。
enum Prefs {
    static let openMainWindowAtLaunch = "openMainWindowAtLaunch"
    static let showNotifications = "showPhoneNotifications"
    static let notificationSound = "notificationSound"
    static let showCallAlerts = "showCallAlerts"
    static let callRingtone = "callRingtone"
    /// 来电铃声用的系统提示音的名字（/System/Library/Sounds 里的文件名，不含扩展名）。
    static let callRingtoneName = "callRingtoneName"
    static let defaultCallRingtoneName = "Hero"

    /// 系统自带的提示音，按名字排序。
    static var systemSounds: [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        return files.filter { $0.hasSuffix(".aiff") }.map { String($0.dropLast(5)) }.sorted()
    }

    static func bool(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }
}

extension FocusedValues {
    /// 投屏窗口在前台时才有值：投屏菜单里的命令只对投屏窗口生效。
    @Entry var mirrorSession: MirrorSession?
}
