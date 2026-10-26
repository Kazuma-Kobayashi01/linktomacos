import Foundation
import WidgetKit

/// 把手机状态写成快照，交给桌面小组件（见 Shared/WidgetSnapshot.swift），并请求它刷新。
@MainActor
final class WidgetPublisher {
    private var lastReload = Date.distantPast
    /// WidgetKit 对刷新次数有预算，状态每隔几秒就来一次，不能每次都刷。
    private static let reloadInterval: TimeInterval = 60

    /// `force`：连接或断开时立即刷新。
    func publish(_ monitor: DeviceMonitor?, force: Bool = false) {
        guard let monitor else { return }
        snapshot(of: monitor).write()
        let now = Date()
        guard force || now.timeIntervalSince(lastReload) >= Self.reloadInterval else { return }
        lastReload = now
        WidgetCenter.shared.reloadAllTimelines()
    }

    func snapshot(of monitor: DeviceMonitor) -> WidgetSnapshot {
        let status = monitor.status
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        let recent = monitor.history.filter { $0.time >= cutoff }
        // 最多约 48 个点，曲线够用，文件也小
        let stride = max(1, recent.count / 48)
        let points = recent.enumerated().filter { $0.offset % stride == 0 || $0.offset == recent.count - 1 }
            .map { WidgetSnapshot.Point(time: $0.element.time, battery: $0.element.battery, charging: $0.element.charging) }
        return WidgetSnapshot(
            deviceName: monitor.name, model: monitor.model, online: monitor.isOnline, lastSeen: monitor.lastSeen,
            battery: status?.batteryLevel, charging: status?.charging ?? false,
            storageUsed: status.map { $0.storageTotal - $0.storageFree }, storageTotal: status?.storageTotal,
            memoryUsed: status.flatMap { s in s.memoryTotal.flatMap { total in s.memoryAvailable.map { total - $0 } } },
            memoryTotal: status?.memoryTotal,
            network: status.map { $0.wifiConnected ? "Wi‑Fi" : ($0.networkType ?? "–") },
            signalLevel: status.flatMap { $0.wifiConnected ? $0.wifiLevel : $0.signalLevel },
            history: points, updated: Date())
    }
}
