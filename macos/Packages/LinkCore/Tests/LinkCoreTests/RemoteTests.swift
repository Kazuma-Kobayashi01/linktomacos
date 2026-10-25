import Foundation
import NIOCore
import NIOEmbedded
import Testing
@testable import LinkCore

@Suite struct RemoteProtocolTests {
    @Test func binaryFrameRoundTrips() throws {
        let channel = EmbeddedChannel(handlers: [
            ByteToMessageHandler(LinkMessageDecoder()), MessageToByteHandler(LinkMessageEncoder()),
        ])
        let payload = Data((0..<1000).map { UInt8($0 % 251) })
        try channel.writeOutbound(LinkMessage.data(streamId: 7, bytes: payload))
        let encoded = try #require(try channel.readOutbound(as: ByteBuffer.self))
        // [长度][0x01][streamId][数据]
        #expect(encoded.getInteger(at: 0, as: UInt32.self) == UInt32(payload.count + 5))
        #expect(encoded.getInteger(at: 4, as: UInt8.self) == binaryFrameMarker)
        try channel.writeInbound(encoded)
        #expect(try channel.readInbound(as: LinkMessage.self) == .data(streamId: 7, bytes: payload))
    }

    @Test func decodesAndroidRequestAndResponse() throws {
        let json = #"{"type":"response","id":3,"ok":true,"result":{"total":2,"items":[{"id":1,"name":"a.jpg","isVideo":false,"size":12345678901,"ratio":1.5,"tag":null}]},"error":null}"#
        guard case .response(let r) = try JSONDecoder().decode(LinkMessage.self, from: Data(json.utf8)) else {
            Issue.record("not response"); return
        }
        #expect(r.id == 3 && r.ok)
        #expect(r.result?["total"] == .int(2))
        guard case .array(let items)? = r.result?["items"] else { Issue.record("no items"); return }
        #expect(items[0]["size"]?.int64Value == 12_345_678_901)
        #expect(items[0]["ratio"] == .double(1.5))
        #expect(items[0]["tag"] == .null)

        let request = LinkMessage.request(.init(id: 9, method: "listMedia", params: .object(["offset": 0, "album": .null])))
        let data = try JSONEncoder().encode(request)
        #expect(try JSONDecoder().decode(LinkMessage.self, from: data) == request)
    }

    @Test func deviceStatusBackwardCompatible() throws {
        // 旧版手机没有新字段
        let old = #"{"type":"deviceStatus","batteryLevel":50,"charging":false,"wifiConnected":true,"storageTotal":10,"storageFree":5,"timestamp":1}"#
        guard case .deviceStatus(let status) = try JSONDecoder().decode(LinkMessage.self, from: Data(old.utf8)) else {
            Issue.record("not deviceStatus"); return
        }
        #expect(status.batteryTemperature == nil && status.memoryTotal == nil)
        // 新版手机的完整字段，含 Kotlin 编码出的 null 和小数
        let new = #"{"type":"deviceStatus","batteryLevel":80,"charging":true,"signalLevel":3,"networkType":"5G","carrier":null,"wifiConnected":true,"storageTotal":512,"storageFree":100,"timestamp":1,"batteryTemperature":31.5,"batteryVoltage":4200,"batteryHealth":"good","chargingType":"ac","memoryTotal":12884901888,"memoryAvailable":5368709120,"wifiLevel":4,"wifiLinkSpeed":866,"signalDbm":-92,"uptime":123456}"#
        guard case .deviceStatus(let full) = try JSONDecoder().decode(LinkMessage.self, from: Data(new.utf8)) else {
            Issue.record("not deviceStatus"); return
        }
        #expect(full.batteryTemperature == 31.5 && full.chargingType == "ac" && full.signalDbm == -92)
        #expect(full.memoryTotal == 12_884_901_888 && full.uptime == 123_456)
    }

    @Test func deviceInfoDecodesWithAndWithoutSoc() throws {
        let base: [String: JSONValue] = [
            "manufacturer": "samsung", "brand": "samsung", "model": "SM-S9180", "device": "dm3q", "androidVersion": "15", "sdk": 35,
            "securityPatch": "2025-09-01", "buildId": "AP3A", "abi": "arm64-v8a", "cpuCores": 8, "memoryTotal": 11_580_000_000,
            "screenWidth": 1440, "screenHeight": 3088, "densityDpi": 600, "refreshRate": 120.0, "language": "en-US",
            "timezone": "Asia/Shanghai", "appVersion": "0.1.0",
        ]
        let old = try JSONValue.object(base).decoded(DeviceInfo.self)
        #expect(old.socModel == nil)
        var withSoc = base
        withSoc["socManufacturer"] = "QTI"; withSoc["socModel"] = "SM8550"; withSoc["hardware"] = "qcom"
        let new = try JSONValue.object(withSoc).decoded(DeviceInfo.self)
        #expect(new.socModel == "SM8550" && new.socManufacturer == "QTI")
    }

    @Test func storageBreakdownDerivesOther() throws {
        let value = JSONValue.object(["total": 1000, "free": 400, "images": 100, "videos": 200, "audio": 50, "hasMedia": true])
        let storage = try value.decoded(StorageBreakdown.self)
        #expect(storage.used == 600 && storage.other == 250)
    }

    @Test func mediaPageDecodes() throws {
        let value = JSONValue.object([
            "total": 1,
            "items": .array([.object([
                "id": 5, "name": "IMG.jpg", "mime": "image/jpeg", "size": 100, "width": 4000, "height": 3000,
                "duration": 0, "date": 1_700_000_000_000, "isVideo": false, "album": "Camera",
            ])]),
        ])
        let page = try value.decoded(MediaPage.self)
        #expect(page.total == 1 && page.items[0].album == "Camera")
    }
}

@Suite struct PhoneRemoteTests {
    /// 记录发出的请求，并允许测试扮演手机回复。
    final class FakePhone: @unchecked Sendable {
        let lock = NSLock()
        private(set) var requests: [RPCRequest] = []
        var onRequest: (@Sendable (RPCRequest) -> Void)?
        func send(_ message: LinkMessage) {
            guard case .request(let request) = message else { return }
            lock.withLock { requests.append(request) }
            onRequest?(request)
        }
        var methods: [String] { lock.withLock { requests.map(\.method) } }
    }

    @Test func callReturnsResultAndErrors() async throws {
        let phone = FakePhone()
        let remote = PhoneRemote(send: phone.send)
        phone.onRequest = { [unowned remote] request in
            DispatchQueue.global().async {
                if request.method == "access" {
                    _ = remote.handle(.response(.init(id: request.id, ok: true, result: .object(["media": true, "allFiles": false]))))
                } else {
                    _ = remote.handle(.response(.init(id: request.id, ok: false, error: "没有权限")))
                }
            }
        }
        let access = try await remote.access()
        #expect(access == AccessInfo(media: true, allFiles: false))
        await #expect(throws: RemoteError.remote("没有权限")) { _ = try await remote.albums() }
    }

    @Test func closeFailsPendingCalls() async throws {
        let phone = FakePhone()
        let remote = PhoneRemote(send: phone.send)
        let task = Task { try await remote.albums() }
        while phone.methods.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        remote.close()
        await #expect(throws: RemoteError.disconnected) { _ = try await task.value }
        await #expect(throws: RemoteError.disconnected) { _ = try await remote.albums() }
    }

    @Test func cancelTellsPhoneToStop() async throws {
        let phone = FakePhone()
        let remote = PhoneRemote(send: phone.send)
        let task = Task { try await remote.albums() }
        while phone.methods.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        while !phone.methods.contains("cancel") { try await Task.sleep(for: .milliseconds(5)) }
        #expect(phone.methods == ["listAlbums", "cancel"])
    }

    @Test func downloadWritesStreamedChunks() async throws {
        let phone = FakePhone()
        let remote = PhoneRemote(send: phone.send)
        let content = Data((0..<500_000).map { UInt8($0 % 253) })
        phone.onRequest = { [unowned remote] request in
            guard request.method == "download" else { return }
            DispatchQueue.global().async {
                // 响应之后紧跟数据帧和结束帧，与真实手机的发送顺序一致
                _ = remote.handle(.response(.init(id: request.id, ok: true, result: .object([
                    "streamId": 42, "size": .int(Int64(content.count)), "name": "x.bin", "mime": "application/octet-stream", "modified": 1,
                ]))))
                var offset = 0
                while offset < content.count {
                    let end = min(offset + 65_536, content.count)
                    _ = remote.handle(.data(streamId: 42, bytes: content[offset..<end]))
                    offset = end
                }
                _ = remote.handle(.streamEnd(.init(streamId: 42, ok: true)))
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        let info = try await remote.download(.file(path: "x.bin"), to: url)
        #expect(info.name == "x.bin" && info.size == 500_000)
        #expect(try Data(contentsOf: url) == content)
    }

    @Test func truncatedDownloadFailsAndCleansUp() async throws {
        let phone = FakePhone()
        let remote = PhoneRemote(send: phone.send)
        phone.onRequest = { [unowned remote] request in
            guard request.method == "download" else { return }
            DispatchQueue.global().async {
                _ = remote.handle(.response(.init(id: request.id, ok: true, result: .object(["streamId": 1, "size": 100]))))
                _ = remote.handle(.data(streamId: 1, bytes: Data(count: 40)))
                _ = remote.handle(.streamEnd(.init(streamId: 1, ok: true)))
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).bin")
        await #expect(throws: RemoteError.sizeMismatch) { _ = try await remote.download(.media(id: 1), to: url) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func disconnectDuringDownloadFails() async throws {
        let phone = FakePhone()
        let remote = PhoneRemote(send: phone.send)
        phone.onRequest = { [unowned remote] request in
            guard request.method == "download" else { return }
            DispatchQueue.global().async {
                _ = remote.handle(.response(.init(id: request.id, ok: true, result: .object(["streamId": 5, "size": 1000]))))
                _ = remote.handle(.data(streamId: 5, bytes: Data(count: 10)))
                remote.close()
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).bin")
        await #expect(throws: RemoteError.disconnected) { _ = try await remote.download(.media(id: 1), to: url) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
