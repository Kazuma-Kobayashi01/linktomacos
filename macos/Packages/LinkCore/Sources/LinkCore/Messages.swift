import Foundation

/// 协议版本，见 docs/PROTOCOL.md。
public let linkProtocolVersion = 1

public struct Hello: Codable, Equatable, Sendable {
    public var protocolVersion: Int
    public var deviceId: String
    public var deviceName: String
    public var model: String
    public var osVersion: String
    public var appVersion: String
    public var pairingToken: String?
}

public struct HelloAck: Codable, Equatable, Sendable {
    public var accepted: Bool
    public var macName: String
    public var reason: String?

    public init(accepted: Bool, macName: String, reason: String? = nil) {
        self.accepted = accepted
        self.macName = macName
        self.reason = reason
    }
}

public struct DeviceStatus: Codable, Equatable, Sendable {
    public var batteryLevel: Int
    public var charging: Bool
    public var signalLevel: Int?
    public var networkType: String?
    public var carrier: String?
    public var wifiConnected: Bool
    public var storageTotal: Int64
    public var storageFree: Int64
    public var timestamp: Int64
}

/// 手机上弹出的一条通知。`key` 在手机端唯一，同一条通知更新时 key 不变。
public struct PhoneNotification: Codable, Equatable, Sendable {
    public var key: String
    public var packageName: String
    public var appName: String
    public var title: String
    public var text: String
    public var subText: String?
    public var timestamp: Int64
    /// 应用图标，PNG 的 base64。
    public var iconPng: String?
}

public struct NotificationRemoved: Codable, Equatable, Sendable {
    public var key: String
}

/// 链路上的一条消息。JSON 中以 `type` 字段区分类型，其余字段平铺在同一层。
public enum LinkMessage: Equatable, Sendable {
    case hello(Hello)
    case helloAck(HelloAck)
    case ping(t: Int64)
    case pong(t: Int64)
    case deviceStatus(DeviceStatus)
    case goodbye(reason: String)
    case notification(PhoneNotification)
    case notificationRemoved(NotificationRemoved)
    /// 本端版本不认识的消息类型，忽略即可，保证向前兼容。
    case unknown(type: String)
}

extension LinkMessage: Codable {
    private enum TypeKey: String, CodingKey { case type }
    private enum FieldKey: String, CodingKey { case t, reason }

    public init(from decoder: Decoder) throws {
        let type = try decoder.container(keyedBy: TypeKey.self).decode(String.self, forKey: .type)
        let fields = try decoder.container(keyedBy: FieldKey.self)
        switch type {
        case "hello": self = .hello(try Hello(from: decoder))
        case "helloAck": self = .helloAck(try HelloAck(from: decoder))
        case "ping": self = .ping(t: try fields.decode(Int64.self, forKey: .t))
        case "pong": self = .pong(t: try fields.decode(Int64.self, forKey: .t))
        case "deviceStatus": self = .deviceStatus(try DeviceStatus(from: decoder))
        case "goodbye": self = .goodbye(reason: try fields.decodeIfPresent(String.self, forKey: .reason) ?? "")
        case "notification": self = .notification(try PhoneNotification(from: decoder))
        case "notificationRemoved": self = .notificationRemoved(try NotificationRemoved(from: decoder))
        default: self = .unknown(type: type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var typeContainer = encoder.container(keyedBy: TypeKey.self)
        try typeContainer.encode(typeName, forKey: .type)
        var fields = encoder.container(keyedBy: FieldKey.self)
        switch self {
        case .hello(let v): try v.encode(to: encoder)
        case .helloAck(let v): try v.encode(to: encoder)
        case .ping(let t), .pong(let t): try fields.encode(t, forKey: .t)
        case .deviceStatus(let v): try v.encode(to: encoder)
        case .goodbye(let reason): try fields.encode(reason, forKey: .reason)
        case .notification(let v): try v.encode(to: encoder)
        case .notificationRemoved(let v): try v.encode(to: encoder)
        case .unknown: break
        }
    }

    public var typeName: String {
        switch self {
        case .hello: "hello"
        case .helloAck: "helloAck"
        case .ping: "ping"
        case .pong: "pong"
        case .deviceStatus: "deviceStatus"
        case .goodbye: "goodbye"
        case .notification: "notification"
        case .notificationRemoved: "notificationRemoved"
        case .unknown(let type): type
        }
    }
}
