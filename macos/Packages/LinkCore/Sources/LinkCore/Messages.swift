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
    /// 以下字段由较新版本的手机提供，旧版本缺失时为 nil。
    public var batteryTemperature: Double?
    public var batteryVoltage: Int?
    /// good / overheat / dead / over_voltage / cold / failure / unknown
    public var batteryHealth: String?
    /// ac / usb / wireless / dock；未充电为 nil。
    public var chargingType: String?
    public var memoryTotal: Int64?
    public var memoryAvailable: Int64?
    /// Wi‑Fi 信号格数 0-4。
    public var wifiLevel: Int?
    /// Wi‑Fi 连接速率，Mbps。
    public var wifiLinkSpeed: Int?
    /// 蜂窝信号强度，dBm。
    public var signalDbm: Int?
    /// 开机至今的毫秒数。
    public var uptime: Int64?

    public init(
        batteryLevel: Int, charging: Bool, signalLevel: Int? = nil, networkType: String? = nil, carrier: String? = nil,
        wifiConnected: Bool, storageTotal: Int64, storageFree: Int64, timestamp: Int64,
        batteryTemperature: Double? = nil, batteryVoltage: Int? = nil, batteryHealth: String? = nil,
        chargingType: String? = nil, memoryTotal: Int64? = nil, memoryAvailable: Int64? = nil,
        wifiLevel: Int? = nil, wifiLinkSpeed: Int? = nil, signalDbm: Int? = nil, uptime: Int64? = nil
    ) {
        self.batteryLevel = batteryLevel
        self.charging = charging
        self.signalLevel = signalLevel
        self.networkType = networkType
        self.carrier = carrier
        self.wifiConnected = wifiConnected
        self.storageTotal = storageTotal
        self.storageFree = storageFree
        self.timestamp = timestamp
        self.batteryTemperature = batteryTemperature
        self.batteryVoltage = batteryVoltage
        self.batteryHealth = batteryHealth
        self.chargingType = chargingType
        self.memoryTotal = memoryTotal
        self.memoryAvailable = memoryAvailable
        self.wifiLevel = wifiLevel
        self.wifiLinkSpeed = wifiLinkSpeed
        self.signalDbm = signalDbm
        self.uptime = uptime
    }
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

/// 投屏时 Mac → 手机的输入事件。`k`：t 触摸（`a` 0 按下 1 抬起 2 移动，`x`/`y` 是 0…1 的相对位置）、
/// s 滚轮（`h`/`v`）、key 按键（`a` 0 按下 1 抬起，`c` Android 键值，`m` 修饰键）、text 文字、
/// cmd 命令（`cmd`：back / home / recents / wake / power / notifications / sync / screenOff / screenOn）。
public struct MirrorInput: Codable, Equatable, Sendable {
    public var k: String
    public var a: Int?
    public var x: Double?
    public var y: Double?
    public var c: Int?
    public var m: Int?
    public var h: Double?
    public var v: Double?
    public var text: String?
    public var cmd: String?

    public init(k: String, a: Int? = nil, x: Double? = nil, y: Double? = nil, c: Int? = nil, m: Int? = nil,
                h: Double? = nil, v: Double? = nil, text: String? = nil, cmd: String? = nil) {
        self.k = k; self.a = a; self.x = x; self.y = y; self.c = c; self.m = m
        self.h = h; self.v = v; self.text = text; self.cmd = cmd
    }

    public static func touch(_ action: Int, x: Double, y: Double) -> MirrorInput { .init(k: "t", a: action, x: x, y: y) }
    public static func command(_ name: String) -> MirrorInput { .init(k: "cmd", cmd: name) }
}

/// 投屏状态变化（手机 → Mac）：resized（旋转或尺寸变化）、stopped、error。
public struct MirrorEvent: Codable, Equatable, Sendable {
    public var event: String
    public var width: Int?
    public var height: Int?
    public var deviceWidth: Int?
    public var deviceHeight: Int?
    public var rotation: Int?
    public var message: String?
}

/// 手机的通话状态变化（手机 → Mac）。`state`：ringing（来电响铃）、offhook（通话中，接通或拨出）、idle（空闲，通话结束）。
/// `name` 是来电的联系人名或号码，取自手机上的来电通知，拿不到时为 nil；响铃期间可能再发一次带名字的 ringing。
public struct CallState: Codable, Equatable, Sendable {
    public var state: String
    public var name: String?
    public var timestamp: Int64

    public init(state: String, name: String? = nil, timestamp: Int64 = 0) {
        self.state = state; self.name = name; self.timestamp = timestamp
    }

    public var isRinging: Bool { state == "ringing" }
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
    case mirrorInput(MirrorInput)
    case mirrorEvent(MirrorEvent)
    case callState(CallState)
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
        case "mirrorInput": self = .mirrorInput(try MirrorInput(from: decoder))
        case "mirrorEvent": self = .mirrorEvent(try MirrorEvent(from: decoder))
        case "callState": self = .callState(try CallState(from: decoder))
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
        case .mirrorInput(let v): try v.encode(to: encoder)
        case .mirrorEvent(let v): try v.encode(to: encoder)
        case .callState(let v): try v.encode(to: encoder)
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
        case .mirrorInput: "mirrorInput"
        case .mirrorEvent: "mirrorEvent"
        case .callState: "callState"
        case .data: "data"
        case .unknown(let type): type
        }
    }
}
