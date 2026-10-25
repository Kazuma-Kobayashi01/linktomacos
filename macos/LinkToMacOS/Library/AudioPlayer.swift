import AVFoundation
import LinkCore
import os

private let log = Logger(subsystem: "com.linktomacos.mac", category: "audio")

/// 手机声音：把手机发来的 Opus 包解码，从 Mac 的扬声器播放；同时（可选）采集 Mac 的麦克风发给手机。
///
/// 麦克风和扬声器放在同一个 AVAudioEngine 里，并打开语音处理（回声消除）：系统只有拿到“同一个引擎正在播放的声音”
/// 作参考，才能把扬声器播出来的手机声音从麦克风里消掉，否则对方会听到自己的回声。
///
/// 手机每 20 ms 发一个包。这里先攒够 `prebufferFrames` 再开始播（抗网络抖动），播放中积压超过 `maxBufferedFrames`
/// 就丢掉新来的包，避免延迟越积越大；缓冲播空了就暂停，攒够了再继续。
final class AudioPlayer: @unchecked Sendable {
    private static let sampleRate = 48_000.0
    private static let framesPerPacket: UInt32 = 960  // 20 ms
    /// 开始播放前攒的量：80 ms。
    private static let prebufferFrames = 3_840
    /// 积压上限：300 ms。
    private static let maxBufferedFrames = 14_400

    /// 所有状态都在这个队列上访问。
    private let queue = DispatchQueue(label: "com.linktomacos.audio", qos: .userInteractive)
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let pcmFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false)!
    private var opusFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var configObserver: NSObjectProtocol?

    private var running = false
    private var playing = false
    private var bufferedFrames = 0

    private var micHandler: (@Sendable (Data) -> Void)?
    private var micConverter: AVAudioConverter?
    private var micConverterRate = 0.0
    private var micPending = Data()
    private var voiceProcessing = false
    /// 20 ms 的 48 kHz 单声道 16 位。
    private static let micChunkBytes = 1_920

    private var packets = 0
    private var dropped = 0
    private var underruns = 0
    private var decodeErrors = 0
    private var lastReport = Date()

    init() {
        var description = AudioStreamBasicDescription(
            mSampleRate: Self.sampleRate, mFormatID: kAudioFormatOpus, mFormatFlags: 0, mBytesPerPacket: 0,
            mFramesPerPacket: Self.framesPerPacket, mBytesPerFrame: 0, mChannelsPerFrame: 2, mBitsPerChannel: 0, mReserved: 0)
        opusFormat = AVAudioFormat(streamDescription: &description)
        if let opusFormat { converter = AVAudioConverter(from: opusFormat, to: pcmFormat) }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: pcmFormat)
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    }

    /// 收到手机发来的一个音频包（`VideoPacketData` 格式）。在连接线程上调用，这里只做拷贝，解码在自己的队列上。
    func handle(packet data: Data) {
        guard let packet = VideoPacketData(parsing: data), !packet.isConfig else { return }
        queue.async { [self] in
            do {
                try startIfNeeded()
            } catch {
                log.error("audio engine failed to start: \(error.localizedDescription)")
                return
            }
            decode(packet.payload)
        }
    }

    /// 开始采集麦克风，每 20 ms 回调一次 PCM（48 kHz、单声道、16 位小端）。要先有麦克风权限。
    /// 打开语音处理需要引擎停着，所以会重新启动引擎。
    func startMic(_ handler: @escaping @Sendable (Data) -> Void) {
        queue.async { [self] in
            do {
                try configureMic(handler)
            } catch {
                log.error("microphone failed to start: \(error.localizedDescription)")
            }
        }
    }

    /// 停止播放并清空缓冲，同时停止麦克风。投屏结束或重新开始时调用。
    func stop() {
        queue.async { [self] in
            guard running else { return }
            running = false
            playing = false
            bufferedFrames = 0
            node.stop()
            if micHandler != nil {
                engine.inputNode.removeTap(onBus: 0)
                micHandler = nil
                micConverter = nil
                micPending.removeAll()
            }
            engine.stop()
            if voiceProcessing {
                try? engine.inputNode.setVoiceProcessingEnabled(false)
                voiceProcessing = false
            }
            converter?.reset()
            log.info("audio stopped: \(packets) packets, \(dropped) dropped, \(underruns) underruns, \(decodeErrors) decode errors")
            packets = 0; dropped = 0; underruns = 0; decodeErrors = 0
        }
    }

    // MARK: - 以下都在 queue 上

    private func startIfNeeded() throws {
        guard !running else { return }
        engine.prepare()
        try engine.start()
        running = true
        if configObserver == nil {
            // 换了输出设备（插拔耳机、切换蓝牙）时引擎会停下，重新启动
            configObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
            ) { [weak self] _ in
                self?.queue.async { self?.restartAfterConfigurationChange() }
            }
        }
        log.info("audio started")
    }

    private func configureMic(_ handler: @escaping @Sendable (Data) -> Void) throws {
        if running {
            node.stop()
            engine.stop()
            playing = false
            bufferedFrames = 0
            running = false
        }
        let input = engine.inputNode
        if !voiceProcessing {
            try input.setVoiceProcessingEnabled(true)
            voiceProcessing = true
            // 默认会把其他应用的声音压低；这里不需要
            input.voiceProcessingOtherAudioDuckingConfiguration = AVAudioVoiceProcessingOtherAudioDuckingConfiguration(
                enableAdvancedDucking: false, duckingLevel: .min)
            // 打开语音处理会改变输出格式，播放节点重新接一遍
            engine.disconnectNodeOutput(node)
            engine.connect(node, to: engine.mainMixerNode, format: pcmFormat)
        }
        micHandler = handler
        micPending.removeAll()
        micConverter = nil
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 960, format: format) { [weak self] buffer, _ in
            self?.consumeMic(buffer)
        }
        try startIfNeeded()
        log.info("microphone started (voice processing, input \(Int(format.sampleRate)) Hz, \(format.channelCount) channels)")
    }

    /// 在录音线程上调用（一次只有一个）。只取第一个声道，转成 48 kHz 单声道 16 位，凑够 20 ms 就交给手机。
    private func consumeMic(_ buffer: AVAudioPCMBuffer) {
        guard let handler = micHandler, let source = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        let rate = buffer.format.sampleRate
        if micConverter == nil || micConverterRate != rate {
            guard let monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
                  let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Self.sampleRate, channels: 1, interleaved: true)
            else { return }
            micConverter = AVAudioConverter(from: monoFormat, to: target)
            micConverterRate = rate
        }
        guard let converter = micConverter,
              let mono = AVAudioPCMBuffer(pcmFormat: converter.inputFormat, frameCapacity: buffer.frameLength)
        else { return }
        mono.frameLength = buffer.frameLength
        mono.floatChannelData![0].update(from: source[0], count: Int(buffer.frameLength))
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * Self.sampleRate / rate) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return mono
        }
        guard status != .error, output.frameLength > 0, let samples = output.int16ChannelData else { return }
        micPending.append(Data(bytes: samples[0], count: Int(output.frameLength) * 2))
        while micPending.count >= Self.micChunkBytes {
            handler(Data(micPending.prefix(Self.micChunkBytes)))
            micPending.removeFirst(Self.micChunkBytes)
        }
    }

    private func restartAfterConfigurationChange() {
        guard running, !engine.isRunning else { return }
        playing = false
        bufferedFrames = 0
        do { try engine.start() } catch { log.error("audio engine restart failed: \(error.localizedDescription)") }
    }

    private func decode(_ opus: Data) {
        guard let converter, let opusFormat, !opus.isEmpty else { return }
        packets += 1

        let input = AVAudioCompressedBuffer(format: opusFormat, packetCapacity: 1, maximumPacketSize: opus.count)
        opus.copyBytes(to: input.data.assumingMemoryBound(to: UInt8.self), count: opus.count)
        input.byteLength = UInt32(opus.count)
        input.packetCount = 1
        input.packetDescriptions?[0] = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(opus.count))

        // 一个包最长 120 ms
        guard let output = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: 5_760) else { return }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, output.frameLength > 0 else {
            decodeErrors += 1
            if decodeErrors <= 3 { log.error("opus decode failed: \(error?.localizedDescription ?? "no output")") }
            return
        }
        schedule(output)
        report()
    }

    private func schedule(_ buffer: AVAudioPCMBuffer) {
        let frames = Int(buffer.frameLength)
        if bufferedFrames + frames > Self.maxBufferedFrames {
            dropped += 1
            return
        }
        bufferedFrames += frames
        node.scheduleBuffer(buffer) { [weak self] in
            self?.queue.async { self?.didPlay(frames: frames) }
        }
        if !playing, bufferedFrames >= Self.prebufferFrames {
            node.play()
            playing = true
        }
    }

    private func didPlay(frames: Int) {
        bufferedFrames = max(0, bufferedFrames - frames)
        if bufferedFrames == 0, playing {
            // 播空了：暂停，等攒够了再继续，比一直断断续续好
            underruns += 1
            node.pause()
            playing = false
        }
    }

    private func report() {
        guard Date().timeIntervalSince(lastReport) > 10 else { return }
        lastReport = Date()
        let buffered = bufferedFrames * 1000 / 48_000
        log.info("audio: \(self.packets) packets, \(self.dropped) dropped, \(self.underruns) underruns, buffered \(buffered) ms")
    }
}
