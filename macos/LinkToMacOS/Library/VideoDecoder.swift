import AppKit
import AVFoundation
import CoreMedia
import LinkCore

/// 把手机发来的 H.264 视频包喂给 AVSampleBufferDisplayLayer（走系统硬件解码）。
///
/// 手机发来：先是配置包（SPS/PPS），之后是画面。收到新的配置包（手机旋转、尺寸变化）就重建格式并等下一个关键帧；
/// 解码出错或中途丢帧时，请求手机立刻出一个关键帧，不显示花屏。
final class VideoDecoder: @unchecked Sendable {
    let layer = AVSampleBufferDisplayLayer()
    /// 需要关键帧时调用（节流：最多每 0.5 秒一次）。
    var onNeedKeyframe: (@Sendable () -> Void)?
    /// 视频尺寸变化（像素）。
    var onSize: (@Sendable (CGSize) -> Void)?

    private let queue = DispatchQueue(label: "linktomacos.video", qos: .userInteractive)
    private var format: CMVideoFormatDescription?
    private var needKeyframe = true
    private var lastRequest = Date.distantPast

    init() {
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = NSColor.black.cgColor
    }

    /// 在网络线程上调用，内部转到解码队列。
    func handle(packet data: Data) {
        queue.async { [self] in process(data) }
    }

    func reset() {
        queue.async { [self] in
            format = nil
            needKeyframe = true
            layer.sampleBufferRenderer.flush(removingDisplayedImage: true)
        }
    }

    private func process(_ data: Data) {
        guard let packet = VideoPacketData(parsing: data) else { return }
        if packet.isConfig {
            configure(packet.payload)
            return
        }
        guard let format else { return requestKeyframe() }
        let renderer = layer.sampleBufferRenderer
        if renderer.status == .failed {
            renderer.flush()
            needKeyframe = true
        }
        let (avcc, hasIDR) = H264.avcc(fromAnnexB: packet.payload)
        guard !avcc.isEmpty else { return }
        if needKeyframe {
            guard hasIDR else { return requestKeyframe() }
            needKeyframe = false
        }
        guard let sample = makeSample(avcc, format: format, pts: packet.ptsMicroseconds, isKey: hasIDR) else { return }
        renderer.enqueue(sample)
    }

    private func configure(_ config: Data) {
        guard let sets = H264.parameterSets(fromConfig: config) else { return }
        var newFormat: CMVideoFormatDescription?
        let status = sets.sps.withUnsafeBytes { sps in
            sets.pps.withUnsafeBytes { pps in
                let pointers = [sps.bindMemory(to: UInt8.self).baseAddress!, pps.bindMemory(to: UInt8.self).baseAddress!]
                let sizes = [sets.sps.count, sets.pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: nil, parameterSetCount: 2, parameterSetPointers: pointers, parameterSetSizes: sizes,
                    nalUnitHeaderLength: 4, formatDescriptionOut: &newFormat)
            }
        }
        guard status == noErr, let newFormat else { return }
        let old = format.map(CMVideoFormatDescriptionGetDimensions)
        let dims = CMVideoFormatDescriptionGetDimensions(newFormat)
        format = newFormat
        if old == nil || old!.width != dims.width || old!.height != dims.height {
            layer.sampleBufferRenderer.flush()
            needKeyframe = true
            onSize?(CGSize(width: Int(dims.width), height: Int(dims.height)))
        }
    }

    private func makeSample(_ avcc: Data, format: CMVideoFormatDescription, pts: Int64, isKey: Bool) -> CMSampleBuffer? {
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: avcc.count, blockAllocator: nil, customBlockSource: nil,
            offsetToData: 0, dataLength: avcc.count, flags: 0, blockBufferOut: &block) == noErr, let block else { return nil }
        let copied = avcc.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: avcc.count)
        }
        guard copied == noErr else { return nil }

        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTime(value: pts, timescale: 1_000_000), decodeTimeStamp: .invalid)
        var size = avcc.count
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample) == noErr,
              let sample else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary],
           let first = attachments.first {
            // 低延迟：不按时间戳排队，来了就显示
            first[kCMSampleAttachmentKey_DisplayImmediately] = true
            if !isKey { first[kCMSampleAttachmentKey_NotSync] = true }
        }
        return sample
    }

    private func requestKeyframe() {
        let now = Date()
        guard now.timeIntervalSince(lastRequest) > 0.5 else { return }
        lastRequest = now
        onNeedKeyframe?()
    }
}
