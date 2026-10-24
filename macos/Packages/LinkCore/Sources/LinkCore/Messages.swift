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

/// 请求：Mac → 手机（读取相册、文件列表、下载等）。`id` 由发起方分配，响应原样带回。
public struct RPCRequest: Codable, Equatable, Sendable {
    public var id: Int
    public var method: String
    public var params: JSONValue

    public init(id: Int, method: String, params: JSONValue = .object([:])) {
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct RPCResponse: Codable, Equatable, Sendable {
    public var id: Int
    public var ok: Bool
    public var result: JSONValue?
    public var error: String?

    public init(id: Int, ok: Bool, result: JSONValue? = nil, error: String? = nil) {
        self.id = id
        self.ok = ok
        self.result = result
        self.error = error
    }
}

/// 一次文件流（下载）结束。内容本身走二进制数据帧。
public struct StreamEnd: Codable, Equatable, Sendable {
    public var streamId: Int
    public var ok: Bool
    public var error: String?

    public init(streamId: Int, ok: Bool, error: String? = nil) {
        self.streamId = streamId
        self.ok = ok
        self.error = error
    }
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
    case request(RPCRequest)
    case response(RPCResponse)
    case streamEnd(StreamEnd)
    /// 二进制数据帧，属于 `streamId` 对应的文件流。不走 JSON，见 FrameCodec。
    case data(streamId: UInt32, bytes: Data)
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
        case "request": self = .request(try RPCRequest(from: decoder))
        case "response": self = .response(try RPCResponse(from: decoder))
        case "streamEnd": self = .streamEnd(try StreamEnd(from: decoder))
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
        case .request(let v): try v.encode(to: encoder)
        case .response(let v): try v.encode(to: encoder)
        case .streamEnd(let v): try v.encode(to: encoder)
        case .data, .unknown: break
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
        case .request: "request"
        case .response: "response"
        case .streamEnd: "streamEnd"
        case .data: "data"
        case .unknown(let type): type
        }
    }
}
