import Foundation
import Testing
@testable import LinkCore

@Suite struct H264Tests {
    private let sps = Data([0x67, 0x64, 0x00, 0x28, 0xAC])
    private let pps = Data([0x68, 0xEE, 0x3C, 0x80])
    private let idr = Data([0x65, 0x88, 0x84, 0x00, 0x10])
    private let slice = Data([0x41, 0x9A, 0x24, 0x6C])

    private func annexB(_ nals: [Data], longStart: Bool = true) -> Data {
        var data = Data()
        for nal in nals {
            data.append(contentsOf: longStart ? [0, 0, 0, 1] : [0, 0, 1])
            data.append(nal)
        }
        return data
    }

    @Test func splitsBothStartCodeLengths() {
        #expect(H264.nalUnits(inAnnexB: annexB([sps, pps], longStart: true)) == [sps, pps])
        #expect(H264.nalUnits(inAnnexB: annexB([sps, pps, idr], longStart: false)) == [sps, pps, idr])
        // 混用
        var mixed = Data([0, 0, 0, 1]); mixed.append(sps); mixed.append(contentsOf: [0, 0, 1]); mixed.append(pps)
        #expect(H264.nalUnits(inAnnexB: mixed) == [sps, pps])
        #expect(H264.nalUnits(inAnnexB: Data()).isEmpty)
    }

    @Test func extractsParameterSetsFromConfig() throws {
        let sets = try #require(H264.parameterSets(fromConfig: annexB([sps, pps])))
        #expect(sets.sps == sps && sets.pps == pps)
        #expect(H264.parameterSets(fromConfig: annexB([idr])) == nil)
    }

    @Test func convertsFrameToAvccDroppingParameterSets() {
        // 关键帧里常带着 SPS/PPS，转 AVCC 时去掉，只留画面数据
        let (avcc, hasIDR) = H264.avcc(fromAnnexB: annexB([sps, pps, idr]))
        #expect(hasIDR)
        var expected = Data()
        expected.append(contentsOf: [0, 0, 0, UInt8(idr.count)]); expected.append(idr)
        #expect(avcc == expected)

        let (p, key) = H264.avcc(fromAnnexB: annexB([slice]))
        #expect(!key)
        #expect(p.count == 4 + slice.count)
        #expect(H264.nalType(slice) == H264.typeNonIDR && H264.nalType(idr) == H264.typeIDR)
    }

    @Test func parsesVideoPacketHeader() throws {
        var raw = Data([3])
        raw.append(contentsOf: [0, 0, 0, 0, 0, 0x0F, 0x42, 0x40]) // 1_000_000 µs
        raw.append(annexB([idr]))
        let packet = try #require(VideoPacketData(parsing: raw))
        #expect(packet.isKeyFrame && packet.isConfig)
        #expect(packet.ptsMicroseconds == 1_000_000)
        #expect(packet.payload == annexB([idr]))
        #expect(VideoPacketData(parsing: Data([1, 2, 3])) == nil)
    }
}

@Suite struct AndroidKeysTests {
    @Test func mapsLettersDigitsAndSpecials() {
        #expect(AndroidKeys.keyCode(forMacKeyCode: 0) == 29)   // A
        #expect(AndroidKeys.keyCode(forMacKeyCode: 6) == 54)   // Z
        #expect(AndroidKeys.keyCode(forMacKeyCode: 8) == 31)   // C
        #expect(AndroidKeys.keyCode(forMacKeyCode: 29) == 7)   // 0
        #expect(AndroidKeys.keyCode(forMacKeyCode: 18) == 8)   // 1
        #expect(AndroidKeys.keyCode(forMacKeyCode: 25) == 16)  // 9
        #expect(AndroidKeys.keyCode(forMacKeyCode: 36) == 66)  // Return
        #expect(AndroidKeys.keyCode(forMacKeyCode: 51) == 67)  // Delete
        #expect(AndroidKeys.keyCode(forMacKeyCode: 53) == AndroidKeys.back) // Esc → 返回
        #expect(AndroidKeys.keyCode(forMacKeyCode: 126) == 19) // ↑
        #expect(AndroidKeys.keyCode(forMacKeyCode: 125) == 20) // ↓
        #expect(AndroidKeys.keyCode(forMacKeyCode: 999) == nil)
    }

    @Test func allLettersAreDistinct() {
        let letterCodes: [UInt16] = [0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46, 45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6]
        let mapped = letterCodes.compactMap(AndroidKeys.keyCode(forMacKeyCode:))
        #expect(mapped.count == 26 && Set(mapped).count == 26)
        #expect(mapped.min() == 29 && mapped.max() == 54)
    }

    @Test func commandActsAsControl() {
        #expect(AndroidKeys.metaState(shift: false, option: false, control: false, command: true) == AndroidKeys.metaCtrl)
        #expect(AndroidKeys.metaState(shift: true, option: false, control: false, command: false) == AndroidKeys.metaShift)
        #expect(AndroidKeys.metaState(shift: false, option: false, control: false, command: false) == 0)
    }
}

@Suite struct MirrorMessageTests {
    @Test func inputRoundTripsAndMatchesAndroidShape() throws {
        let touch = LinkMessage.mirrorInput(.touch(2, x: 0.25, y: 0.75))
        let data = try JSONEncoder().encode(touch)
        #expect(try JSONDecoder().decode(LinkMessage.self, from: data) == touch)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains(#""type":"mirrorInput""#) && json.contains(#""k":"t""#) && !json.contains("null"))

        // Android 编码出的事件（含 null 字段）
        let event = try JSONDecoder().decode(LinkMessage.self, from: Data(#"{"type":"mirrorEvent","event":"resized","width":1080,"height":2312,"deviceWidth":1080,"deviceHeight":2316,"rotation":0,"message":null}"#.utf8))
        #expect(event == .mirrorEvent(MirrorEvent(event: "resized", width: 1080, height: 2312, deviceWidth: 1080, deviceHeight: 2316, rotation: 0, message: nil)))
    }
}

@Suite struct PhoneRemoteMirrorTests {
    final class Fake: @unchecked Sendable {
        let lock = NSLock()
        var requests: [RPCRequest] = []
        var inputs: [MirrorInput] = []
        var sentData: [(streamId: UInt32, bytes: Data)] = []
        var onRequest: (@Sendable (RPCRequest) -> Void)?
        func send(_ message: LinkMessage) {
            switch message {
            case .request(let request):
                lock.withLock { requests.append(request) }
                onRequest?(request)
            case .mirrorInput(let input):
                lock.withLock { inputs.append(input) }
            case .data(let streamId, let bytes):
                lock.withLock { sentData.append((streamId, bytes)) }
            default: break
            }
        }
    }

    @Test func dataBeforeResponseIsDeliveredInOrder() async throws {
        let fake = Fake()
        let remote = PhoneRemote(send: fake.send)
        let received = Locked<[Data]>([])
        fake.onRequest = { [unowned remote] request in
            guard request.method == "mirrorStart" else { return }
            DispatchQueue.global().async {
                // 配置包先于响应到达，随后响应，再来画面
                _ = remote.handle(.data(streamId: 9, bytes: Data([1])))
                _ = remote.handle(.data(streamId: 9, bytes: Data([2])))
                _ = remote.handle(.response(.init(id: request.id, ok: true, result: .object([
                    "streamId": 9, "width": 1080, "height": 2312, "deviceWidth": 1080, "deviceHeight": 2316,
                ]))))
                _ = remote.handle(.data(streamId: 9, bytes: Data([3])))
            }
        }
        let info = try await remote.mirrorStart(MirrorStartOptions(mode: .mirror),
                                                video: { data in received.withLock { $0.append(data) } }, events: { _ in })
        #expect(info.streamId == 9 && info.width == 1080)
        try await Task.sleep(for: .milliseconds(100))
        #expect(received.value == [Data([1]), Data([2]), Data([3])])
    }

    @Test func audioStreamIsRegisteredAndEarlyPacketsArePlayedInOrder() async throws {
        let fake = Fake()
        let remote = PhoneRemote(send: fake.send)
        let video = Locked<[Data]>([])
        let audio = Locked<[Data]>([])
        fake.onRequest = { [unowned remote] request in
            guard request.method == "mirrorStart" else { return }
            #expect(request.params["audio"] == true)
            DispatchQueue.global().async {
                // 音频包先于响应到达，随后响应，再来视频和音频
                _ = remote.handle(.data(streamId: 12, bytes: Data([0xA1])))
                _ = remote.handle(.response(.init(id: request.id, ok: true, result: .object([
                    "streamId": 11, "audioStreamId": 12, "width": 720, "height": 1280, "deviceWidth": 720, "deviceHeight": 1280,
                ]))))
                _ = remote.handle(.data(streamId: 11, bytes: Data([0x01])))
                _ = remote.handle(.data(streamId: 12, bytes: Data([0xA2])))
            }
        }
        let info = try await remote.mirrorStart(
            MirrorStartOptions(mode: .newDisplay, audio: true),
            video: { data in video.withLock { $0.append(data) } },
            audio: { data in audio.withLock { $0.append(data) } },
            events: { _ in })
        #expect(info.audioStreamId == 12)
        try await Task.sleep(for: .milliseconds(100))
        #expect(video.value == [Data([0x01])])
        #expect(audio.value == [Data([0xA1]), Data([0xA2])])
    }

    @Test func microphoneStreamIdIsReturnedAndPcmIsSentAsDataFrames() async throws {
        let fake = Fake()
        let remote = PhoneRemote(send: fake.send)
        fake.onRequest = { [unowned remote] request in
            guard request.method == "mirrorStart" else { return }
            #expect(request.params["mic"] == true)
            DispatchQueue.global().async {
                _ = remote.handle(.response(.init(id: request.id, ok: true, result: .object([
                    "streamId": 1, "micStreamId": 3, "width": 720, "height": 1280, "deviceWidth": 720, "deviceHeight": 1280,
                ]))))
            }
        }
        let info = try await remote.mirrorStart(MirrorStartOptions(mode: .newDisplay, mic: true), video: { _ in }, events: { _ in })
        #expect(info.micStreamId == 3)
        remote.sendMic(streamId: try #require(info.micStreamId), Data(repeating: 7, count: 1920))
        let frames = fake.lock.withLock { fake.sentData }
        #expect(frames.count == 1 && frames[0].streamId == 3 && frames[0].bytes.count == 1920)
        #expect(MirrorStartOptions().params["mic"] == false)
    }

    @Test func audioStreamIsIgnoredWhenNoHandlerIsGiven() async throws {
        let fake = Fake()
        let remote = PhoneRemote(send: fake.send)
        fake.onRequest = { [unowned remote] request in
            DispatchQueue.global().async {
                _ = remote.handle(.response(.init(id: request.id, ok: true, result: .object([
                    "streamId": 1, "audioStreamId": 2, "width": 720, "height": 1280, "deviceWidth": 720, "deviceHeight": 1280,
                ]))))
            }
        }
        let info = try await remote.mirrorStart(MirrorStartOptions(mode: .mirror), video: { _ in }, events: { _ in })
        #expect(info.audioStreamId == 2)
        #expect(MirrorStartOptions().params["audio"] == false)
    }

    @Test func eventsAndInputFlow() async throws {
        let fake = Fake()
        let remote = PhoneRemote(send: fake.send)
        let events = Locked<[MirrorEvent]>([])
        fake.onRequest = { [unowned remote] request in
            DispatchQueue.global().async {
                _ = remote.handle(.response(.init(id: request.id, ok: true, result: .object([
                    "streamId": 1, "width": 720, "height": 1280, "deviceWidth": 720, "deviceHeight": 1280,
                ]))))
            }
        }
        _ = try await remote.mirrorStart(MirrorStartOptions(mode: .mirror, maxSize: 1280), video: { _ in },
                                         events: { event in events.withLock { $0.append(event) } })
        _ = remote.handle(.mirrorEvent(MirrorEvent(event: "resized", width: 1280, height: 720)))
        remote.sendInput(.command("back"))
        remote.close()
        #expect(events.value.map(\.event) == ["resized", "stopped"])
        #expect(fake.lock.withLock { fake.inputs } == [.command("back")])
    }
}

@Suite struct VirtualDisplayModeTests {
    @Test func startOptionsSendModeSizeAndApp() throws {
        let options = MirrorStartOptions(mode: .newDisplay, maxSize: 1920, bitRate: 8_000_000, fps: 60,
                                         width: 1080, height: 2340, app: "com.tencent.mm", forceStop: true)
        let params = options.params
        #expect(params["mode"] == "new" && params["width"] == 1080 && params["height"] == 2340)
        #expect(params["app"] == "com.tencent.mm" && params["forceStop"] == true)
        #expect(MirrorStartOptions(mode: .mirror).params["mode"] == "mirror")
        #expect(MirrorStartOptions().params["app"] == nil)
    }

    @Test func startInfoDecodesWithAndWithoutVirtualDisplayFields() throws {
        let old = try JSONValue.object(["streamId": 1, "width": 720, "height": 1280, "deviceWidth": 720, "deviceHeight": 1280]).decoded(MirrorStartInfo.self)
        #expect(old.displayId == nil && old.mode == nil)
        let new = try JSONValue.object(["streamId": 2, "width": 1080, "height": 2336, "deviceWidth": 1080, "deviceHeight": 2336, "displayId": 23, "mode": "new"]).decoded(MirrorStartInfo.self)
        #expect(new.displayId == 23 && new.mode == "new")
    }

    @Test func appListAndIconRequests() async throws {
        let fake = PhoneRemoteMirrorTests.Fake()
        let remote = PhoneRemote(send: fake.send)
        fake.onRequest = { [unowned remote] request in
            DispatchQueue.global().async {
                switch request.method {
                case "listApps":
                    _ = remote.handle(.response(.init(id: request.id, ok: true, result: .object(["apps": .array([
                        .object(["package": "com.a", "label": "微信"]), .object(["package": "com.b", "label": "Chrome"]),
                    ])]))))
                case "appIcon":
                    _ = remote.handle(.response(.init(id: request.id, ok: true, result: .object(["data": .string(Data([1, 2, 3]).base64EncodedString())]))))
                default:
                    _ = remote.handle(.response(.init(id: request.id, ok: true, result: .object(["ok": true]))))
                }
            }
        }
        let apps = try await remote.listApps()
        #expect(apps.map(\.label) == ["微信", "Chrome"])
        #expect(try await remote.appIcon(package: "com.a") == Data([1, 2, 3]))
        try await remote.mirrorResize(width: 800, height: 1600)
        try await remote.mirrorLaunch(package: "com.a", forceStop: true)
        let methods = fake.lock.withLock { fake.requests.map(\.method) }
        #expect(methods == ["listApps", "appIcon", "mirrorResize", "mirrorLaunch"])
        let launch = fake.lock.withLock { fake.requests.last! }
        #expect(launch.params["package"] == "com.a" && launch.params["forceStop"] == true)
    }
}

final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: T
    init(_ value: T) { storage = value }
    var value: T { lock.withLock { storage } }
    func withLock(_ body: (inout T) -> Void) { lock.withLock { body(&storage) } }
}
