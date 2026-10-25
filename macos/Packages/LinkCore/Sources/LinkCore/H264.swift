import Foundation

/// 手机发来的一个视频包：`[标志 1 字节][pts 8 字节大端，微秒][H.264 Annex-B 数据]`。
/// 音频包的格式相同，只是数据是一个 Opus 包（每个 20 ms），标志位 1 = 配置（Opus 头）。
public struct VideoPacketData: Equatable, Sendable {
    public var flags: UInt8
    public var ptsMicroseconds: Int64
    public var payload: Data

    /// 编码器输出的配置（SPS/PPS），不是画面。
    public var isConfig: Bool { flags & 1 != 0 }
    public var isKeyFrame: Bool { flags & 2 != 0 }

    public init?(parsing data: Data) {
        guard data.count > 9 else { return nil }
        let base = data.startIndex
        flags = data[base]
        var pts: Int64 = 0
        for i in 1...8 { pts = (pts << 8) | Int64(data[base + i]) }
        ptsMicroseconds = pts
        payload = data.subdata(in: (base + 9)..<data.endIndex)
    }
}

/// H.264 码流处理。MediaCodec 输出的是 Annex-B（起始码分隔），VideoToolbox 要 AVCC（4 字节长度前缀）。
public enum H264 {
    public static let typeNonIDR = 1
    public static let typeIDR = 5
    public static let typeSEI = 6
    public static let typeSPS = 7
    public static let typePPS = 8
    public static let typeAUD = 9

    /// 按 `00 00 01` / `00 00 00 01` 切分 NAL 单元，去掉起始码。
    public static func nalUnits(inAnnexB data: Data) -> [Data] {
        let bytes = [UInt8](data)
        var starts: [(codeStart: Int, nalStart: Int)] = []
        var i = 0
        while i + 2 < bytes.count {
            if bytes[i] == 0, bytes[i + 1] == 0, bytes[i + 2] == 1 {
                // 4 字节起始码时，前面多出的 00 也属于起始码
                let codeStart = (i > 0 && bytes[i - 1] == 0) ? i - 1 : i
                starts.append((codeStart, i + 3))
                i += 3
            } else {
                i += 1
            }
        }
        guard !starts.isEmpty else { return bytes.isEmpty ? [] : [data] }
        var result: [Data] = []
        for (index, start) in starts.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1].codeStart : bytes.count
            if end > start.nalStart { result.append(Data(bytes[start.nalStart..<end])) }
        }
        return result
    }

    public static func nalType(_ nal: Data) -> Int {
        nal.isEmpty ? 0 : Int(nal[nal.startIndex] & 0x1F)
    }

    /// 从配置包里取出 SPS 和 PPS。
    public static func parameterSets(fromConfig data: Data) -> (sps: Data, pps: Data)? {
        let nals = nalUnits(inAnnexB: data)
        guard let sps = nals.first(where: { nalType($0) == typeSPS }),
              let pps = nals.first(where: { nalType($0) == typePPS }) else { return nil }
        return (sps, pps)
    }

    /// 画面数据转 AVCC：去掉 SPS/PPS/AUD（格式描述里已经有），其余每个 NAL 加 4 字节大端长度。
    public static func avcc(fromAnnexB data: Data) -> (avcc: Data, hasIDR: Bool) {
        var out = Data()
        var hasIDR = false
        for nal in nalUnits(inAnnexB: data) {
            let type = nalType(nal)
            if type == typeSPS || type == typePPS || type == typeAUD { continue }
            if type == typeIDR { hasIDR = true }
            var length = UInt32(nal.count).bigEndian
            withUnsafeBytes(of: &length) { out.append(contentsOf: $0) }
            out.append(nal)
        }
        return (out, hasIDR)
    }
}
