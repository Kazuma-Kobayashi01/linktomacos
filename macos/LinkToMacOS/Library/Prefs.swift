import SwiftUI

/// 用户偏好的键和默认值。界面用 @AppStorage 读写，其他地方用这里的读取方法。
enum Prefs {
    static let openMainWindowAtLaunch = "openMainWindowAtLaunch"
    static let showNotifications = "showPhoneNotifications"
    static let notificationSound = "notificationSound"

    static func bool(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }
}

extension FocusedValues {
    /// 投屏窗口在前台时才有值：投屏菜单里的命令只对投屏窗口生效。
    @Entry var mirrorSession: MirrorSession?
}
