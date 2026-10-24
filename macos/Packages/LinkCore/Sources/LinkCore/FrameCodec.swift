import Foundation
import NIOCore

/// 单帧上限，超过即视为协议错误并断开连接。
public let maxFrameLength = 1 << 20

public enum FrameError: Error {
    case frameTooLarge(Int)
    case emptyFrame
}

/// 二进制数据帧的标记字节。JSON 对象以 `{` 开头，不会与之冲突。
public let binaryFrameMarker: UInt8 = 0x01

/// `[4 字节大端长度][JSON]` 或 `[4 字节大端长度][0x01][4 字节 streamId][数据]` → `LinkMessage`
public struct LinkMessageDecoder: ByteToMessageDecoder {
    public typealias InboundOut = LinkMessage

    private let jsonDecoder = JSONDecoder()

    public init() {}

    public mutating func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        guard let length = buffer.getInteger(at: buffer.readerIndex, as: UInt32.self) else { return .needMoreData }
        guard length <= maxFrameLength else { throw FrameError.frameTooLarge(Int(length)) }
        guard buffer.readableBytes >= 4 + Int(length) else { return .needMoreData }
        guard length >= 1 else { throw FrameError.emptyFrame }
        buffer.moveReaderIndex(forwardBy: 4)
        var body = buffer.readSlice(length: Int(length))!
        let message: LinkMessage
        if body.getInteger(at: body.readerIndex, as: UInt8.self) == binaryFrameMarker {
            guard length >= 5 else { throw FrameError.emptyFrame }
            body.moveReaderIndex(forwardBy: 1)
            let streamId = body.readInteger(as: UInt32.self)!
            message = .data(streamId: streamId, bytes: Data(body.readableBytesView))
        } else {
            message = try jsonDecoder.decode(LinkMessage.self, from: Data(body.readableBytesView))
        }
        context.fireChannelRead(wrapInboundOut(message))
        return .continue
    }
}

/// `LinkMessage` → 帧
public struct LinkMessageEncoder: MessageToByteEncoder {
    public typealias OutboundIn = LinkMessage

    private let jsonEncoder = JSONEncoder()

    public init() {}

    public func encode(data: LinkMessage, out: inout ByteBuffer) throws {
        if case .data(let streamId, let bytes) = data {
            guard bytes.count + 5 <= maxFrameLength else { throw FrameError.frameTooLarge(bytes.count + 5) }
            out.writeInteger(UInt32(bytes.count + 5))
            out.writeInteger(binaryFrameMarker)
            out.writeInteger(streamId)
            out.writeBytes(bytes)
            return
        }
        let body = try jsonEncoder.encode(data)
        guard body.count <= maxFrameLength else { throw FrameError.frameTooLarge(body.count) }
        out.writeInteger(UInt32(body.count))
        out.writeBytes(body)
    }
}
