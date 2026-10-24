import CoreAudio
import Foundation
import IOBluetooth

// 用法：hfp-spike [设备名或地址的一部分]
// 前提：手机已在“系统设置 → 蓝牙”里与这台 Mac 配对。

func log(_ message: String) {
    let time = Date().formatted(date: .omitted, time: .standard)
    print("[\(time)] \(message)")
}

/// 打印 CoreAudio 设备，用于确认 SCO 打开后系统是否出现了蓝牙通话音频设备。
func listAudioDevices() {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids)
    for id in ids {
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
        let bt = transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
        let label = name?.takeRetainedValue() as String? ?? "?"
        print("  \(bt ? "🔵" : "  ") [\(id)] \(label)")
    }
}

final class Spike: NSObject, IOBluetoothHandsFreeDeviceDelegate {
    var handsFree: IOBluetoothHandsFreeDevice?

    func start(matching filter: String?) {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        log("已配对蓝牙设备：")
        for device in paired {
            let ag = device.isHandsFreeAudioGateway ? "（支持 HFP 网关）" : ""
            print("  - \(device.name ?? "?") \(device.addressString ?? "")\(ag)")
        }
        let candidates = paired.filter { $0.isHandsFreeAudioGateway }
        let target = filter.map { f in
            paired.first { ($0.name ?? "").localizedCaseInsensitiveContains(f) || ($0.addressString ?? "").contains(f) }
        } ?? candidates.first
        guard let device = target else {
            log("❌ 没找到可用的手机。请先在“系统设置 → 蓝牙”里配对手机，或在参数里指定名称。")
            exit(1)
        }
        log("使用设备：\(device.name ?? "?")，正在建立 HFP 连接…")
        let hf = IOBluetoothHandsFreeDevice(device: device, delegate: self)
        handsFree = hf
        hf?.connect()
    }

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
        print("""
        命令：a 接听 | e 挂断 | d <号码> 拨号 | sco / nosco 打开/关闭语音链路 | mac / phone 声音切换
              calls 当前通话 | at <命令> 发送 AT 命令 | audio 列出音频设备 | status 状态 | q 退出
        """)
    }

    // MARK: IOBluetoothHandsFreeDelegate

    func handsFree(_ device: IOBluetoothHandsFree!, connected status: NSNumber!) {
        log(status == 0 ? "✅ HFP 已连接" : "❌ HFP 连接失败 status=\(status!)")
        if status == 0 { printHelp() }
    }

    func handsFree(_ device: IOBluetoothHandsFree!, disconnected status: NSNumber!) {
        log("HFP 已断开 status=\(status!)")
    }

    func handsFree(_ device: IOBluetoothHandsFree!, scoConnectionOpened status: NSNumber!) {
        log(status == 0 ? "✅ 语音链路(SCO)已打开" : "❌ SCO 打开失败 status=\(status!)")
        listAudioDevices()
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
    }

    func handsFree(_ device: IOBluetoothHandsFreeDevice!, callSetupMode: NSNumber!) {
        let modes = ["空闲", "来电", "去电拨号中", "对方振铃"]
        log("呼叫状态=\(modes[safe: callSetupMode.intValue] ?? "\(callSetupMode!)")")
    }

    func handsFree(_ device: IOBluetoothHandsFreeDevice!, incomingCallFrom number: String!) {
        log("📞 来电：\(number ?? "未知号码")（输入 a 接听，e 拒接）")
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

let spike = Spike()
spike.start(matching: CommandLine.arguments.dropFirst().first)

// 后台线程读命令，回主线程执行（IOBluetooth 回调依赖主 RunLoop）
Thread.detachNewThread {
    while let line = readLine() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        DispatchQueue.main.async { spike.run(command: trimmed) }
    }
}
RunLoop.main.run()
