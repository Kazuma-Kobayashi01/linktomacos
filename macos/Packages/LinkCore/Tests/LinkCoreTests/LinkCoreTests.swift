import Foundation
import NIOCore
import NIOEmbedded
import Testing
@testable import LinkCore

@Suite struct MessageTests {
    @Test func roundTripsEveryKnownType() throws {
        let status = try JSONDecoder().decode(DeviceStatus.self, from: Data("""
            {"batteryLevel":80,"charging":true,"signalLevel":3,"networkType":"5G","carrier":"CMHK",
             "wifiConnected":true,"storageTotal":512,"storageFree":100,"timestamp":1}
            """.utf8))
        let messages: [LinkMessage] = [
            .helloAck(.init(accepted: true, macName: "Mac")),
            .ping(t: 42), .pong(t: 42), .deviceStatus(status), .goodbye(reason: "quit"),
        ]
        for message in messages {
            let data = try JSONEncoder().encode(message)
            #expect(try JSONDecoder().decode(LinkMessage.self, from: data) == message)
        }
    }

    @Test func decodesAndroidNotification() throws {
        let json = """
            {"type":"notification","key":"0|com.x|1|null|10","packageName":"com.x","appName":"X","title":"标题",
             "text":"内容","subText":null,"timestamp":1,"iconPng":null}
            """
        guard case .notification(let n) = try JSONDecoder().decode(LinkMessage.self, from: Data(json.utf8)) else {
            Issue.record("not notification"); return
        }
        #expect(n.title == "标题" && n.subText == nil)
        let removed = try JSONDecoder().decode(LinkMessage.self, from: Data(#"{"type":"notificationRemoved","key":"k"}"#.utf8))
        #expect(removed == .notificationRemoved(.init(key: "k")))
        let data = try JSONEncoder().encode(LinkMessage.notification(n))
        #expect(try JSONDecoder().decode(LinkMessage.self, from: data) == .notification(n))
    }

    @Test func decodesAndroidHello() throws {
        let json = """
            {"type":"hello","protocolVersion":1,"deviceId":"abc","deviceName":"S23U","model":"SM-S9180",
             "osVersion":"15","appVersion":"0.1","pairingToken":null}
            """
        guard case .hello(let hello) = try JSONDecoder().decode(LinkMessage.self, from: Data(json.utf8)) else {
            Issue.record("not hello"); return
        }
        #expect(hello.deviceId == "abc")
        #expect(hello.pairingToken == nil)
    }

    @Test func decodesAndroidCallState() throws {
        let json = #"{"type":"callState","state":"ringing","name":"张三","timestamp":1700000000000}"#
        guard case .callState(let call) = try JSONDecoder().decode(LinkMessage.self, from: Data(json.utf8)) else {
            Issue.record("not callState"); return
        }
        #expect(call.isRinging && call.name == "张三")
        let idle = try JSONDecoder().decode(LinkMessage.self, from: Data(#"{"type":"callState","state":"idle","name":null,"timestamp":5}"#.utf8))
        #expect(idle == .callState(.init(state: "idle", name: nil, timestamp: 5)))
        let data = try JSONEncoder().encode(LinkMessage.callState(call))
        #expect(try JSONDecoder().decode(LinkMessage.self, from: data) == .callState(call))
    }

    @Test func clipboardRoundTripsAndToleratesMissingTimestamp() throws {
        let clip = ClipboardText(text: "第一行\n\"引号\" 😀\t末尾", timestamp: 42)
        let data = try JSONEncoder().encode(LinkMessage.clipboard(clip))
        #expect(try JSONDecoder().decode(LinkMessage.self, from: data) == .clipboard(clip))
        // Android 端也可能不带 timestamp
        let bare = try JSONDecoder().decode(LinkMessage.self, from: Data(#"{"type":"clipboard","text":"x"}"#.utf8))
        #expect(bare == .clipboard(.init(text: "x")))
    }

    @Test func unknownTypeIsTolerated() throws {
        let message = try JSONDecoder().decode(LinkMessage.self, from: Data(#"{"type":"future","x":1}"#.utf8))
        #expect(message == .unknown(type: "future"))
    }
}

@Suite struct FrameTests {
    @Test func decodesSplitFrames() throws {
        let channel = EmbeddedChannel(handlers: [
            ByteToMessageHandler(LinkMessageDecoder()), MessageToByteHandler(LinkMessageEncoder()),
        ])
        try channel.writeOutbound(LinkMessage.ping(t: 7))
        var encoded = try #require(try channel.readOutbound(as: ByteBuffer.self))
        let head = encoded.readSlice(length: 3)!
        try channel.writeInbound(head)
        #expect(try channel.readInbound(as: LinkMessage.self) == nil)
        try channel.writeInbound(encoded)
        #expect(try channel.readInbound(as: LinkMessage.self) == .ping(t: 7))
    }

    @Test func rejectsOversizedFrame() throws {
        let channel = EmbeddedChannel(handler: ByteToMessageHandler(LinkMessageDecoder()))
        var buffer = ByteBuffer()
        buffer.writeInteger(UInt32(maxFrameLength + 1))
        #expect(throws: FrameError.self) { try channel.writeInbound(buffer) }
    }
}

@Suite struct PairingTests {
    private func hello(token: String?) -> Hello {
        Hello(protocolVersion: 1, deviceId: "phone", deviceName: "S23U", model: "SM-S9180",
              osVersion: "15", appVersion: "0.1", pairingToken: token)
    }

    @Test func tokenIsSingleUseAndFingerprintIsPinned() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = PairingStore(directory: dir)
        let token = store.issueToken().token

        #expect(store.evaluate(hello: hello(token: "wrong"), peerFingerprint: "aa") == .rejected("not paired"))
        guard case .newlyPaired = store.evaluate(hello: hello(token: token), peerFingerprint: "aa") else {
            Issue.record("expected pairing"); return
        }
        guard case .known = store.evaluate(hello: hello(token: nil), peerFingerprint: "aa") else {
            Issue.record("expected known"); return
        }
        #expect(store.evaluate(hello: hello(token: token), peerFingerprint: "bb") == .rejected("certificate mismatch"))
        // 重新加载后仍记得已配对设备
        #expect(PairingStore(directory: dir).pairedDevices.map(\.deviceId) == ["phone"])
    }

    @Test func payloadRoundTrip() {
        let payload = PairingPayload(macName: "Jackson 的 MacBook", hosts: ["192.168.1.2", "10.0.0.3"],
                                     port: 47152, fingerprint: "ab", token: "cd")
        #expect(PairingPayload(uri: payload.uri) == payload)
    }

    @Test func identityPersists() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = try LinkIdentity.loadOrCreate(in: dir, commonName: "test")
        let second = try LinkIdentity.loadOrCreate(in: dir, commonName: "test")
        #expect(first.fingerprint == second.fingerprint)
        #expect(first.fingerprint.count == 64)
    }
}
