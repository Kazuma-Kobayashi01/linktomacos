import AppKit
import LinkCore
import UserNotifications
import os

private let log = Logger(subsystem: "com.linktomacos.mac", category: "calls")

/// 手机来电提示：响铃时在 Mac 上弹通知并循环播放提示音，接通、挂断或手机断线时停止。
/// 响铃中对方挂断（没接就结束了）会补一条“未接来电”。只做提示，不转发通话的声音，也不在 Mac 上接听。
@MainActor
final class CallAlerter {
    private static let callIdentifier = "linktomacos.call"
    private static let missedIdentifier = "linktomacos.missed-call"
    /// 状态一直没有变化（比如手机掉线了）时，最多响这么久。
    private static let longestRing: Duration = .seconds(90)
    /// 两次响铃之间的停顿，加上提示音本身的长度。
    private static let ringPause: TimeInterval = 1.4

    private let center = UNUserNotificationCenter.current()
    private var ringing = false
    private var callerName: String?
    private var ringTimer: Timer?
    private var safetyStop: Task<Void, Never>?
    private var ringtone: NSSound?

    func handle(_ call: CallState, from deviceName: String) {
        switch call.state {
        case "ringing":
            guard Prefs.bool(Prefs.showCallAlerts, default: true) else { return }
            ring(name: call.name, deviceName: deviceName)
        case "offhook":
            stop(missedFrom: nil)  // 接通了（或是自己拨出去的）
        default:
            stop(missedFrom: ringing ? deviceName : nil)  // 响铃中直接结束 = 没接
        }
    }

    /// 手机断线、Mac 退出时调用：停止响铃，不算未接来电。
    func stop() {
        stop(missedFrom: nil)
    }

    private func ring(name: String?, deviceName: String) {
        let isNew = !ringing
        ringing = true
        if let name, !name.isEmpty { callerName = name }
        postNotification(deviceName: deviceName)
        guard isNew else { return }  // 同一通电话补发名字，只更新通知，不重新响
        log.info("incoming call from \(self.callerName ?? "unknown", privacy: .private)")
        if Prefs.bool(Prefs.callRingtone, default: true) { startRingtone() }
        safetyStop = Task { [weak self] in
            try? await Task.sleep(for: Self.longestRing)
            if !Task.isCancelled { self?.stop(missedFrom: nil) }
        }
    }

    private func stop(missedFrom deviceName: String?) {
        let wasRinging = ringing
        ringing = false
        ringTimer?.invalidate()
        ringTimer = nil
        ringtone?.stop()
        safetyStop?.cancel()
        safetyStop = nil
        let name = callerName
        callerName = nil
        guard wasRinging else { return }
        center.removeDeliveredNotifications(withIdentifiers: [Self.callIdentifier])
        if let deviceName { postMissed(name: name, deviceName: deviceName) }
    }

    private func startRingtone() {
        let name = UserDefaults.standard.string(forKey: Prefs.callRingtoneName) ?? Prefs.defaultCallRingtoneName
        ringtone = NSSound(named: NSSound.Name(name)) ?? NSSound(named: NSSound.Name(Prefs.defaultCallRingtoneName))
        ringtone?.play()
        let interval = (ringtone?.duration ?? 1) + Self.ringPause
        ringTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.ringtone?.stop()
                self?.ringtone?.play()
            }
        }
    }

    private func postNotification(deviceName: String) {
        let content = UNMutableNotificationContent()
        content.title = callerName ?? String(localized: "来电")
        content.subtitle = deviceName
        content.body = callerName == nil ? "" : String(localized: "来电")
        content.sound = nil  // 铃声自己循环播放，不用通知的提示音
        center.add(UNNotificationRequest(identifier: Self.callIdentifier, content: content, trigger: nil)) { error in
            if let error { log.error("call notification failed: \(error.localizedDescription)") }
        }
    }

    private func postMissed(name: String?, deviceName: String) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "未接来电")
        content.subtitle = deviceName
        content.body = name ?? ""
        center.add(UNNotificationRequest(identifier: Self.missedIdentifier, content: content, trigger: nil)) { error in
            if let error { log.error("missed call notification failed: \(error.localizedDescription)") }
        }
    }
}
