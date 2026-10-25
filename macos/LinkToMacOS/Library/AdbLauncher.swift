import Foundation

struct AdbDevice: Identifiable, Equatable {
    let serial: String
    /// device / unauthorized / offline …
    let state: String
    let model: String?
    let isUSB: Bool
    var id: String { serial }
}

enum AdbError: LocalizedError {
    case notFound
    case noUSBDevice
    case unauthorized
    case multipleDevices
    case failed(String)
    case serviceDidNotStart(log: String)

    var errorDescription: String? {
        switch self {
        case .notFound: String(localized: "没有找到 adb。请安装 Android 平台工具（Android Studio 或 brew install android-platform-tools），或手动选择 adb。")
        case .noUSBDevice: String(localized: "没有检测到 USB 连接的手机。请用数据线连接，并在手机上开启“USB 调试”。")
        case .unauthorized: String(localized: "手机还没有授权这台电脑。请在手机弹出的“允许 USB 调试吗？”里点允许。")
        case .multipleDevices: String(localized: "检测到多部 USB 手机，请只连接一部。")
        case .failed(let message): message
        case .serviceDidNotStart(let log):
            log.isEmpty ? String(localized: "增强服务没有在预期时间内启动。")
                        : String(localized: "增强服务没有启动。手机上的日志：\(log)")
        }
    }
}

/// 通过 USB 上的 adb 启动手机上的 shell 服务。只在用户点击“启动增强服务”时使用，服务起来后就不再需要 adb 和数据线。
enum AdbLauncher {
    static let defaultsKey = "adbPath"
    static let serviceClass = "com.linktomacos.android.shell.ShellMain"
    static let logPath = "/data/local/tmp/linktomacos-shell.log"

    static func locate() -> URL? {
        var candidates: [String] = []
        if let saved = UserDefaults.standard.string(forKey: defaultsKey) { candidates.append(saved) }
        let env = ProcessInfo.processInfo.environment
        for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let root = env[key] { candidates.append(root + "/platform-tools/adb") }
        }
        candidates += [
            NSHomeDirectory() + "/Library/Android/sdk/platform-tools/adb",
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    // MARK: - 进程

    @discardableResult
    static func run(_ adb: URL, _ arguments: [String], timeout: TimeInterval = 20) async throws -> (status: Int32, output: String) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = adb
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice

            let lock = NSLock()
            var collected = Data()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty { lock.withLock { collected.append(chunk) } }
            }
            let timeoutItem = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)
            process.terminationHandler = { finished in
                timeoutItem.cancel()
                pipe.fileHandleForReading.readabilityHandler = nil
                let rest = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = lock.withLock { collected + rest }
                continuation.resume(returning: (finished.terminationStatus, String(decoding: output, as: UTF8.self)))
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }

    // MARK: - 设备

    static func devices(adb: URL) async throws -> [AdbDevice] {
        let (_, output) = try await run(adb, ["devices", "-l"])
        return output.split(separator: "\n").dropFirst().compactMap { line in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 2, !line.hasPrefix("*") else { return nil }
            let model = parts.first { $0.hasPrefix("model:") }.map { String($0.dropFirst(6)) }
            return AdbDevice(serial: parts[0], state: parts[1], model: model, isUSB: parts.contains { $0.hasPrefix("usb:") })
        }
    }

    /// 选出要用的 USB 手机。多部时优先选型号与当前连接的手机一致的那部。
    static func pickUSBDevice(_ devices: [AdbDevice], preferredModel: String?) throws -> AdbDevice {
        let usb = devices.filter(\.isUSB)
        guard !usb.isEmpty else { throw AdbError.noUSBDevice }
        let ready = usb.filter { $0.state == "device" }
        if ready.isEmpty { throw usb.contains { $0.state == "unauthorized" } ? AdbError.unauthorized : AdbError.noUSBDevice }
        if ready.count == 1 { return ready[0] }
        let normalize = { (text: String) in text.replacingOccurrences(of: "-", with: "_").lowercased() }
        if let preferredModel, let match = ready.first(where: { $0.model.map(normalize) == normalize(preferredModel) }) { return match }
        throw AdbError.multipleDevices
    }

    // MARK: - 服务

    static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// 启动命令。服务脱离 adb 会话运行（setsid + nohup + 重定向），拔掉数据线后继续有效，直到手机重启。
    static func launchCommand(apkPath: String, port: Int, secret: String) -> String {
        [
            "S=; command -v setsid >/dev/null 2>&1 && S=setsid;",
            "$S nohup app_process -Djava.class.path=\(shellQuote(apkPath)) /system/bin \(serviceClass)",
            "--port \(port) --secret \(secret)",
            "</dev/null >\(logPath) 2>&1 &",
        ].joined(separator: " ")
    }

    static func startService(adb: URL, serial: String, apkPath: String, port: Int, secret: String) async throws {
        // 先结束旧实例。pattern 写成 ShellMai[n]：命令行里不会出现连续的 “ShellMain”，pkill 不会误杀这条命令自己
        try await run(adb, ["-s", serial, "shell", "pkill -f 'ShellMai[n]' >/dev/null 2>&1; true"])
        try await Task.sleep(for: .milliseconds(400))
        let (status, output) = try await run(adb, ["-s", serial, "shell", launchCommand(apkPath: apkPath, port: port, secret: secret)])
        if status != 0 { throw AdbError.failed(output.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    static func stopService(adb: URL, serial: String) async throws {
        try await run(adb, ["-s", serial, "shell", "pkill -f 'ShellMai[n]' >/dev/null 2>&1; true"])
    }

    /// 服务日志的最后几行，用于启动失败时告诉用户原因。
    static func serviceLog(adb: URL, serial: String) async -> String {
        let result = try? await run(adb, ["-s", serial, "shell", "tail -n 12 \(logPath) 2>/dev/null"], timeout: 8)
        return (result?.output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
