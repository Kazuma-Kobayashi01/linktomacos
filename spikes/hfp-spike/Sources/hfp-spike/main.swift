import AVFoundation
import CoreAudio
import Foundation
import IOBluetooth

// 用法：
//   hfp-spike [设备名或地址的一部分]                      交互模式：手动输入命令
//   hfp-spike --auto [名称] [--dial 号码] [--wait 秒]     自动模式：连接 → 等来电（或拨号）→ 接听 → 打开语音链路 →
//                                                         测蓝牙音频设备的收音和放音 → 挂断 → 汇总，全部写进 hfp-spike.log
//   hfp-spike --list-audio                                只列出 CoreAudio 设备（不碰蓝牙）
// 前提：手机已在“系统设置 → 蓝牙”里与这台 Mac 配对，并允许“通话音频”。

// MARK: - 日志和结果

let logURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("hfp-spike.log")
var logHandle: FileHandle? = {
    FileManager.default.createFile(atPath: logURL.path, contents: nil)
    return try? FileHandle(forWritingTo: logURL)
}()

func emit(_ line: String) {
    print(line)
    fflush(stdout)
    if let data = (line + "\n").data(using: .utf8) { try? logHandle?.write(contentsOf: data) }
}

func log(_ message: String) {
    emit("[\(Date().formatted(date: .omitted, time: .standard))] \(message)")
}

struct CheckResult {
    var name: String
    var ok: Bool?  // nil = 需要你自己确认
    var detail: String
}

var results: [CheckResult] = []

func record(_ name: String, _ ok: Bool?, _ detail: String = "") {
    results.append(CheckResult(name: name, ok: ok, detail: detail))
    log("\(ok == true ? "✅" : (ok == false ? "❌" : "❓")) \(name)\(detail.isEmpty ? "" : "：\(detail)")")
}

func sleep(_ seconds: Double) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}

// MARK: - CoreAudio

struct AudioDevice {
    var id: AudioObjectID
    var name: String
    var isBluetooth: Bool
    var inputChannels: Int
    var outputChannels: Int
    var sampleRate: Double
}

func channelCount(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
    let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
    return list.reduce(0) { $0 + Int($1.mNumberChannels) }
}

func audioDevices() -> [AudioDevice] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids)
    return ids.map { id in
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &name)
        var transportAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0
        var transportSize = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &transportAddress, 0, nil, &transportSize, &transport)
        var rateAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var rate: Float64 = 0
        var rateSize = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(id, &rateAddress, 0, nil, &rateSize, &rate)
        return AudioDevice(
            id: id, name: name?.takeRetainedValue() as String? ?? "?",
            isBluetooth: transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE,
            inputChannels: channelCount(id, scope: kAudioObjectPropertyScopeInput),
            outputChannels: channelCount(id, scope: kAudioObjectPropertyScopeOutput), sampleRate: rate)
    }
}

/// 打印 CoreAudio 设备，用于确认 SCO 打开后系统是否出现了蓝牙通话音频设备。
func listAudioDevices() {
    for device in audioDevices() {
        emit("  \(device.isBluetooth ? "🔵" : "  ") [\(device.id)] \(device.name)  输入 \(device.inputChannels) 声道 / 输出 \(device.outputChannels) 声道 / \(Int(device.sampleRate)) Hz")
    }
}

/// 通话时系统出现的蓝牙音频设备：优先名字里有手机名、同时有输入和输出的。
func findPhoneAudioDevice(phoneName: String) -> AudioDevice? {
    let bluetooth = audioDevices().filter { $0.isBluetooth }
    let named = bluetooth.filter { $0.name.localizedCaseInsensitiveContains(phoneName) }
    return (named + bluetooth).first { $0.inputChannels > 0 && $0.outputChannels > 0 } ?? (named + bluetooth).first
}

struct SpikeError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

final class Stats: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: Float = 0
    private var sumSquares = 0.0
    private var frames = 0
    func add(peak: Float, sumSquares: Double, frames: Int) {
        lock.withLock { self.peak = max(self.peak, peak); self.sumSquares += sumSquares; self.frames += frames }
    }
    var snapshot: (peak: Float, rms: Float, frames: Int) {
        lock.withLock { (peak, frames > 0 ? Float((sumSquares / Double(frames)).squareRoot()) : 0, frames) }
    }
}

/// 从指定的音频设备录音若干秒，返回峰值、均方根和采样数。
func recordFromDevice(_ device: AudioDevice, seconds: Double) async throws -> (peak: Float, rms: Float, frames: Int, rate: Double) {
    let engine = AVAudioEngine()
    try engine.inputNode.auAudioUnit.setDeviceID(device.id)
    let format = engine.inputNode.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else { throw SpikeError("设备的输入格式无效：\(format)") }
    let stats = Stats()
    engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
        guard let data = buffer.floatChannelData else { return }
        let count = Int(buffer.frameLength)
        var peak: Float = 0
        var sum = 0.0
        for i in 0..<count {
            let value = data[0][i]
            peak = max(peak, abs(value))
            sum += Double(value * value)
        }
        stats.add(peak: peak, sumSquares: sum, frames: count)
    }
    try engine.start()
    await sleep(seconds)
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    let result = stats.snapshot
    return (result.peak, result.rms, result.frames, format.sampleRate)
}

/// 往指定的音频设备播放 440 Hz 提示音。
func playTone(on device: AudioDevice, seconds: Double) async throws {
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    try engine.outputNode.auAudioUnit.setDeviceID(device.id)
    engine.attach(player)
    let rate = device.sampleRate > 0 ? device.sampleRate : 16_000
    guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { throw SpikeError("无法创建音频格式") }
    engine.connect(player, to: engine.mainMixerNode, format: format)
    let frames = AVAudioFrameCount(rate * seconds)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { throw SpikeError("无法创建缓冲") }
    buffer.frameLength = frames
    for i in 0..<Int(frames) { buffer.floatChannelData![0][i] = Float(sin(2 * Double.pi * 440 * Double(i) / rate)) * 0.3 }
    try engine.start()
    player.scheduleBuffer(buffer, completionHandler: nil)
    player.play()
    await sleep(seconds + 0.3)
    player.stop()
    engine.stop()
}

// MARK: - 命令行

struct Options {
    var auto = false
    var listAudio = false
    var dial: String?
    var wait = 180.0
    var deviceFilter: String?

    init(_ arguments: [String]) {
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--auto": auto = true
            case "--list-audio": listAudio = true
            case "--dial": index += 1; dial = index < arguments.count ? arguments[index] : nil
            case "--wait": index += 1; wait = index < arguments.count ? Double(arguments[index]) ?? 180 : 180
            default: deviceFilter = arguments[index]
            }
            index += 1
        }
    }
}

let options = Options(Array(CommandLine.arguments.dropFirst()))

// MARK: - HFP

final class Spike: NSObject, IOBluetoothHandsFreeDeviceDelegate {
    var handsFree: IOBluetoothHandsFreeDevice?
    var phoneName = ""
    private var answered = false
    private var callWasActive = false
    private var audioTestStarted = false
    private var finished = false

    func start(matching filter: String?) {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        log("已配对蓝牙设备：")
        for device in paired {
            let ag = device.isHandsFreeAudioGateway ? "（支持 HFP 网关）" : ""
            emit("  - \(device.name ?? "?") \(device.addressString ?? "")\(ag)")
        }
        let candidates = paired.filter { $0.isHandsFreeAudioGateway }
        let target = filter.map { f in
            paired.first { ($0.name ?? "").localizedCaseInsensitiveContains(f) || ($0.addressString ?? "").contains(f) }
        } ?? candidates.first
        guard let device = target else {
            record("找到已配对的手机", false, "请先在“系统设置 → 蓝牙”里配对手机，或在参数里指定名称")
            finish(code: 1)
            return
        }
        phoneName = device.name ?? ""
        record("找到已配对的手机", true, "\(phoneName) \(device.addressString ?? "")，支持 HFP 网关=\(device.isHandsFreeAudioGateway)")
        log("正在建立 HFP 连接…（首次会请求蓝牙权限，请点允许）")
        let hf = IOBluetoothHandsFreeDevice(device: device, delegate: self)
        handsFree = hf
        hf?.connect()
        if options.auto {
            // 连接本身最多等 30 秒
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                guard let self, !self.connectedOnce else { return }
                record("HFP 连接", false, "30 秒内没有连上。检查手机上有没有弹出配对或权限请求，以及手机的“通话音频”开关")
                self.finish(code: 1)
            }
        }
    }

    private var connectedOnce = false

    // MARK: 自动流程

    private func beginScenario() {
        if let number = options.dial {
            log("📞 自动拨号：\(number)")
            handsFree?.dialNumber(number)
        } else {
            emit("")
            emit("════════════════════════════════════════")
            emit("  现在请用另一部手机拨打这台手机（\(phoneName)）")
            emit("  \(Int(options.wait)) 秒内没有来电就会结束。接通后我会自动接听。")
            emit("════════════════════════════════════════")
            emit("")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + options.wait) { [weak self] in
            guard let self, !self.callWasActive else { return }
            record("通话建立", false, "\(Int(options.wait)) 秒内没有通话")
            self.finish(code: 2)
        }
    }

    private func ensureVoiceLink() {
        guard let hf = handsFree, !audioTestStarted else { return }
        if hf.isSCOConnected() {
            runAudioTests()
            return
        }
        log("→ 打开语音链路（connectSCO）")
        hf.connectSCO()
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, !self.audioTestStarted else { return }
            log("语音链路 6 秒内没有打开，改用 transferAudioToComputer")
            hf.transferAudioToComputer()
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                guard let self, !self.audioTestStarted else { return }
                record("语音链路（SCO）", false, "connectSCO 和 transferAudioToComputer 都没有打开，看上面的日志和手机的“通话音频”开关")
                self.hangUpAndFinish()
            }
        }
    }

    private func runAudioTests() {
        guard !audioTestStarted else { return }
        audioTestStarted = true
        Task { @MainActor in
            await sleep(1.0)  // 等系统把蓝牙通话设备建出来
            log("CoreAudio 设备：")
            listAudioDevices()
            guard let device = findPhoneAudioDevice(phoneName: phoneName) else {
                record("系统出现蓝牙通话音频设备", false, "SCO 打开后 CoreAudio 里没有蓝牙设备")
                hangUpAndFinish()
                return
            }
            let quality = device.sampleRate >= 15_000 ? "宽带（mSBC，约 16 kHz）" : "窄带（CVSD，约 8 kHz）"
            record("系统出现蓝牙通话音频设备", true,
                   "\(device.name)，输入 \(device.inputChannels) / 输出 \(device.outputChannels) 声道，\(Int(device.sampleRate)) Hz，\(quality)")

            emit("")
            emit("──── 现在请对着打来电话的那部手机说话（或拍手），持续 4 秒 ────")
            do {
                let heard = try await recordFromDevice(device, seconds: 4)
                let level = String(format: "峰值 %.3f，均方根 %.4f，%d 个采样，采样率 %d Hz", heard.peak, heard.rms, heard.frames, Int(heard.rate))
                record("收到对方的声音（Mac 能从蓝牙设备录到）", heard.peak > 0.02, level)
            } catch {
                record("收到对方的声音（Mac 能从蓝牙设备录到）", false, "\(error)。如果是权限问题，去系统设置 → 隐私与安全性 → 麦克风里允许终端")
            }

            emit("")
            emit("──── 接下来向对方播放 2 秒“嘟”声，请在对方手机上听 ────")
            do {
                try await playTone(on: device, seconds: 2)
                record("向对方播放提示音", nil, "播放没有报错；请确认对方手机里是否听到了“嘟”声")
            } catch {
                record("向对方播放提示音", false, "\(error)")
            }
            await sleep(1.0)
            hangUpAndFinish()
        }
    }

    private func hangUpAndFinish() {
        guard !finished else { return }
        log("→ 挂断")
        handsFree?.endCall()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.finish(code: 0) }
    }

    func finish(code: Int32) {
        guard !finished else { return }
        finished = true
        emit("")
        emit("════════ 汇总 ════════")
        for result in results {
            emit("\(result.ok == true ? "✅" : (result.ok == false ? "❌" : "❓")) \(result.name)\(result.detail.isEmpty ? "" : "：\(result.detail)")")
        }
        emit("日志已写入 \(logURL.path)")
        handsFree?.disconnect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(code) }
    }

    // MARK: 交互模式命令

    func run(command line: String) {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        guard let hf = handsFree, let cmd = parts.first else { return }
        switch cmd {
        case "a": hf.acceptCall(); log("→ 接听")
        case "e": hf.endCall(); log("→ 挂断 / 拒接")
        case "d" where parts.count == 2: hf.dialNumber(parts[1]); log("→ 拨号 \(parts[1])")
        case "sco": hf.connectSCO(); log("→ 打开语音链路")
        case "nosco": hf.disconnectSCO(); log("→ 关闭语音链路")
        case "mac": hf.transferAudioToComputer(); log("→ 声音切到 Mac")
        case "phone": hf.transferAudioToPhone(); log("→ 声音切回手机")
        case "calls": hf.currentCallList(); log("→ 查询当前通话")
        case "at" where parts.count == 2: hf.send(atCommand: parts[1]); log("→ AT \(parts[1])")
        case "audio": listAudioDevices()
        case "status":
            log("HFP 已连接=\(hf.isConnected) SCO=\(hf.isSCOConnected()) 手机功能位=0x\(String(hf.deviceSupportedFeatures, radix: 16))")
        case "q": hf.disconnect(); exit(0)
        default: printHelp()
        }
    }

    func printHelp() {
        emit("""
        命令：a 接听 | e 挂断 | d <号码> 拨号 | sco / nosco 打开/关闭语音链路 | mac / phone 声音切换
              calls 当前通话 | at <命令> 发送 AT 命令 | audio 列出音频设备 | status 状态 | q 退出
        """)
    }

    // MARK: IOBluetoothHandsFreeDelegate

    func handsFree(_ device: IOBluetoothHandsFree!, connected status: NSNumber!) {
        guard status == 0 else {
            record("HFP 连接", false, "status=\(status!)")
            if options.auto { finish(code: 1) }
            return
        }
        connectedOnce = true
        let features = handsFree?.deviceSupportedFeatures ?? 0
        // 网关（手机）支持的功能位：bit 9 = 编解码协商（宽带语音 mSBC）
        record("HFP 连接", true, "手机功能位 0x\(String(features, radix: 16))，支持宽带语音协商=\(features & 0x200 != 0)")
        if options.auto { beginScenario() } else { printHelp() }
    }

    func handsFree(_ device: IOBluetoothHandsFree!, disconnected status: NSNumber!) {
        log("HFP 已断开 status=\(status!)")
    }

    func handsFree(_ device: IOBluetoothHandsFree!, scoConnectionOpened status: NSNumber!) {
        if status == 0 {
            record("语音链路（SCO）打开", true)
            if options.auto { runAudioTests() } else { listAudioDevices() }
        } else {
            log("❌ SCO 打开失败 status=\(status!)")
        }
    }

    func handsFree(_ device: IOBluetoothHandsFree!, scoConnectionClosed status: NSNumber!) {
        log("语音链路(SCO)已关闭 status=\(status!)")
    }

    // MARK: IOBluetoothHandsFreeDeviceDelegate

    func handsFree(_ device: IOBluetoothHandsFreeDevice!, isServiceAvailable: NSNumber!) {
        log("网络服务可用=\(isServiceAvailable!)")
    }

    func handsFree(_ device: IOBluetoothHandsFreeDevice!, isCallActive: NSNumber!) {
        log("通话中=\(isCallActive!)")
        if isCallActive.boolValue {
            guard !callWasActive else { return }
            callWasActive = true
            record("通话建立", true)
            if options.auto {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.ensureVoiceLink() }
            }
        } else if callWasActive, options.auto, !audioTestStarted {
            record("通话保持到测试开始", false, "对方在测试前挂断了")
            finish(code: 2)
        }
    }

    func handsFree(_ device: IOBluetoothHandsFreeDevice!, callSetupMode: NSNumber!) {
        let modes = ["空闲", "来电", "去电拨号中", "对方振铃"]
        log("呼叫状态=\(modes[safe: callSetupMode.intValue] ?? "\(callSetupMode!)")")
    }

    func handsFree(_ device: IOBluetoothHandsFreeDevice!, incomingCallFrom number: String!) {
        let shown = (number ?? "").isEmpty ? nil : number
        record("来电显示号码", shown != nil, shown ?? "没有收到号码")
        if options.auto, !answered {
            answered = true
            log("2 秒后自动接听…")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                log("→ 接听")
                self?.handsFree?.acceptCall()
            }
        } else if !options.auto {
            log("📞 来电：\(number ?? "未知号码")（输入 a 接听，e 拒接）")
        }
    }

    func handsFree(_ device: IOBluetoothHandsFreeDevice!, ringAttempt: NSNumber!) {
        log("🔔 振铃 #\(ringAttempt!)")
    }

    func handsFree(_ device: IOBluetoothHandsFreeDevice!, signalStrength: NSNumber!) {
        log("信号=\(signalStrength!)")
    }

    func handsFree(_ device: IOBluetoothHandsFreeDevice!, batteryCharge: NSNumber!) {
        log("电量=\(batteryCharge!)")
    }

    func handsFree(_ device: IOBluetoothHandsFreeDevice!, currentCall: [AnyHashable: Any]!) {
        log("当前通话：\(currentCall ?? [:])")
    }

    func handsFree(_ device: IOBluetoothHandsFreeDevice!, unhandledResultCode resultCode: String!) {
        log("未处理的结果码：\(resultCode ?? "")")
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: - 入口

if options.listAudio {
    emit("CoreAudio 设备：")
    listAudioDevices()
    exit(0)
}

let spike = Spike()
spike.start(matching: options.deviceFilter)

if !options.auto {
    // 后台线程读命令，回主线程执行（IOBluetooth 回调依赖主 RunLoop）
    Thread.detachNewThread {
        while let line = readLine() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            DispatchQueue.main.async { spike.run(command: trimmed) }
        }
    }
}
RunLoop.main.run()
