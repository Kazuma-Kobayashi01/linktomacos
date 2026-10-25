import Foundation
import LinkCore
import Observation
import os

private let log = Logger(subsystem: "com.linktomacos.mac", category: "monitor")

/// 历史曲线上的一个点。
struct HistoryPoint: Codable, Identifiable, Equatable {
    var time: Date
    var battery: Int
    var charging: Bool
    var temperature: Double?
    var signalDbm: Int?
    /// 蜂窝或 Wi‑Fi 信号格数 0-4。
    var signalLevel: Int?
    var id: Date { time }
}

/// 一台手机的设备信息、实时状态和历史。离线时仍保留最后已知的数据，并保存在磁盘上。
@MainActor
@Observable
final class DeviceMonitor: Identifiable {
    private struct Snapshot: Codable {
        var name: String
        var model: String
        var info: DeviceInfo?
        var status: DeviceStatus?
        var storage: StorageBreakdown?
        var history: [HistoryPoint]
        var lastSeen: Date?
    }

    static let historyWindow: TimeInterval = 24 * 3600

    let id: String
    private(set) var name: String
    private(set) var model: String
    private(set) var info: DeviceInfo?
    private(set) var status: DeviceStatus?
    private(set) var storage: StorageBreakdown?
    private(set) var history: [HistoryPoint] = []
    private(set) var lastSeen: Date?
    private(set) var isOnline = false
    private(set) var connectedSince: Date?
    private(set) var address: String?
    private(set) var pairedAt: Date?

    private var remote: PhoneRemote?
    private var storageTask: Task<Void, Never>?
    private var lastSave = Date.distantPast
    private let fileURL: URL

    init(device: PairedDevice, directory: URL) {
        id = device.deviceId
        name = device.name
        model = device.model
        pairedAt = device.pairedAt
        fileURL = directory.appendingPathComponent("device-\(device.deviceId).json")
        if let data = try? Data(contentsOf: fileURL), let snapshot = try? JSONDecoder.iso.decode(Snapshot.self, from: data) {
            info = snapshot.info
            status = snapshot.status
            storage = snapshot.storage
            history = snapshot.history
            lastSeen = snapshot.lastSeen
        }
    }

    // MARK: 连接状态

    func attach(remote: PhoneRemote, device: PairedDevice, address: String?) {
        self.remote = remote
        name = device.name
        model = device.model
        self.address = address
        isOnline = true
        connectedSince = Date()
        storageTask?.cancel()
        storageTask = Task { [weak self] in
            await self?.refreshInfo()
            while !Task.isCancelled {
                await self?.refreshStorage()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    func detach() {
        storageTask?.cancel()
        storageTask = nil
        remote = nil
        isOnline = false
        connectedSince = nil
        save(force: true)
    }

    func deleteSavedData() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: 数据

    func update(_ status: DeviceStatus) {
        self.status = status
        let now = Date()
        lastSeen = now
        let point = HistoryPoint(
            time: now, battery: status.batteryLevel, charging: status.charging,
            temperature: status.batteryTemperature, signalDbm: status.signalDbm,
            signalLevel: status.wifiConnected ? status.wifiLevel : status.signalLevel)
        // 每分钟一个点；电量或充电状态一变就立刻记一个
        if let last = history.last, now.timeIntervalSince(last.time) < 50,
           last.battery == point.battery, last.charging == point.charging {
        } else {
            history.append(point)
            let cutoff = now.addingTimeInterval(-Self.historyWindow)
            if let first = history.firstIndex(where: { $0.time >= cutoff }), first > 0 { history.removeFirst(first) }
        }
        save(force: false)
    }

    func refreshInfo() async {
        guard let remote else { return }
        do { info = try await remote.deviceInfo() } catch { log.info("deviceInfo failed: \(error.localizedDescription)") }
        save(force: true)
    }

    func refreshStorage() async {
        guard let remote else { return }
        do { storage = try await remote.storageBreakdown() } catch is CancellationError {} catch {
            log.info("storageBreakdown failed: \(error.localizedDescription)")
        }
        save(force: true)
    }

    // MARK: 持久化

    private func save(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastSave) > 60 else { return }
        lastSave = now
        let snapshot = Snapshot(name: name, model: model, info: info, status: status, storage: storage, history: history, lastSeen: lastSeen)
        guard let data = try? JSONEncoder.iso.encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static var iso: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var iso: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

#if DEBUG
extension DeviceMonitor {
    /// 调试用：一台带示例数据的手机，用于离屏渲染主页（见 SnapshotRenderer）。
    static func sample(online: Bool = true) -> DeviceMonitor {
        func decode<T: Decodable>(_ value: JSONValue) -> T { try! value.decoded(T.self) }
        let now = Date()
        let device: PairedDevice = decode(.object([
            "deviceId": "sample", "name": "Galaxy S23 Ultra", "model": "SM-S9180",
            "certificateFingerprint": "", "pairedAt": .double(now.addingTimeInterval(-86400).timeIntervalSinceReferenceDate),
        ]))
        let monitor = DeviceMonitor(device: device, directory: FileManager.default.temporaryDirectory.appendingPathComponent("linktomacos-sample"))
        let infoFields: [String: JSONValue] = [
            "manufacturer": "samsung", "brand": "samsung", "model": "SM-S9180", "device": "dm3q", "androidVersion": "15",
            "sdk": 35, "securityPatch": "2025-09-01", "buildId": "AP3A.240905.015.A2.S9180ZHS6DYI3", "abi": "arm64-v8a",
            "cpuCores": 8, "memoryTotal": 11_585_000_000, "screenWidth": 1440, "screenHeight": 3088, "densityDpi": 600,
            "refreshRate": 120.0, "socManufacturer": "QTI", "socModel": "SM8550", "hardware": "qcom", "language": "en-US",
            "timezone": "Asia/Shanghai", "appVersion": "0.1.0",
        ]
        monitor.info = decode(.object(infoFields))
        monitor.status = DeviceStatus(
            batteryLevel: 76, charging: true, signalLevel: 3, networkType: "5G", carrier: "CMCC", wifiConnected: false,
            storageTotal: 496_190_000_000, storageFree: 338_400_000_000, timestamp: 0,
            batteryTemperature: 34.8, batteryVoltage: 4360, batteryHealth: "good", chargingType: "usb",
            memoryTotal: 11_585_000_000, memoryAvailable: 4_630_000_000, signalDbm: -94, uptime: 1_000_000_000)
        monitor.storage = decode(.object([
            "total": 496_190_000_000, "free": 338_400_000_000, "images": 24_350_000_000,
            "videos": 28_050_000_000, "audio": 9_150_000_000, "hasMedia": true,
        ]))
        var history: [HistoryPoint] = []
        for i in 0..<120 {
            let time = now.addingTimeInterval(Double(i - 120) * 180)
            let temperature: Double = 33 + sin(Double(i) / 9) * 1.6
            let signal: Int = -98 + ((i / 20) % 3) * 3
            history.append(HistoryPoint(time: time, battery: 40 + i / 3, charging: true,
                                        temperature: temperature, signalDbm: signal, signalLevel: 3))
        }
        monitor.history = history
        if online {
            monitor.isOnline = true
            monitor.address = "192.168.1.23"
            monitor.connectedSince = now.addingTimeInterval(-380)
        } else {
            monitor.lastSeen = now.addingTimeInterval(-3600)
        }
        return monitor
    }
}
#endif
