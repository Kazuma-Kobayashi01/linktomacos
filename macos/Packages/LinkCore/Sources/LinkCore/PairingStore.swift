import Foundation

public struct PairedDevice: Codable, Equatable, Sendable, Identifiable {
    public var id: String { deviceId }
    public var deviceId: String
    public var name: String
    public var model: String
    public var certificateFingerprint: String
    public var pairedAt: Date
}

/// 已配对设备 + 当前有效的一次性配对令牌。
public final class PairingStore: @unchecked Sendable {
    public static let tokenLifetime: TimeInterval = 5 * 60

    private let fileURL: URL
    private let lock = NSLock()
    private var devices: [String: PairedDevice]
    private var pendingToken: (value: String, expires: Date)?

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("paired-devices.json")
        let data = try? Data(contentsOf: fileURL)
        let list = data.flatMap { try? JSONDecoder().decode([PairedDevice].self, from: $0) } ?? []
        devices = Dictionary(uniqueKeysWithValues: list.map { ($0.deviceId, $0) })
    }

    public var pairedDevices: [PairedDevice] {
        lock.withLock { devices.values.sorted { $0.pairedAt < $1.pairedAt } }
    }

    /// 生成新的配对令牌，旧令牌立即失效。
    public func issueToken() -> (token: String, expires: Date) {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        let expires = Date().addingTimeInterval(Self.tokenLifetime)
        lock.withLock { pendingToken = (token, expires) }
        return (token, expires)
    }

    public func cancelToken() {
        lock.withLock { pendingToken = nil }
    }

    public enum Verdict: Equatable {
        case known(PairedDevice)
        case newlyPaired(PairedDevice)
        case rejected(String)
    }

    /// 判断一次握手：已配对设备需证书指纹一致；未配对设备需携带有效令牌（使用后作废）。
    public func evaluate(hello: Hello, peerFingerprint: String) -> Verdict {
        lock.withLock {
            if let device = devices[hello.deviceId], device.certificateFingerprint == peerFingerprint {
                return .known(device)
            }
            guard let token = hello.pairingToken,
                  let pending = pendingToken,
                  pending.value == token,
                  pending.expires > Date()
            else {
                return .rejected(devices[hello.deviceId] == nil ? "not paired" : "certificate mismatch")
            }
            pendingToken = nil
            let device = PairedDevice(
                deviceId: hello.deviceId,
                name: hello.deviceName,
                model: hello.model,
                certificateFingerprint: peerFingerprint,
                pairedAt: Date()
            )
            devices[device.deviceId] = device
            saveLocked()
            return .newlyPaired(device)
        }
    }

    public func remove(deviceId: String) {
        lock.withLock {
            devices[deviceId] = nil
            saveLocked()
        }
    }

    private func saveLocked() {
        let list = devices.values.sorted { $0.pairedAt < $1.pairedAt }
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
