import Foundation
import NIOCore

/// 单帧上限，超过即视为协议错误并断开连接。
public let maxFrameLength = 1 << 20

public enum FrameError: Error {
    case frameTooLarge(Int)
}

/// `[4 字节大端长度][JSON]` → `LinkMessage`
public struct LinkMessageDecoder: ByteToMessageDecoder {
    public typealias InboundOut = LinkMessage

    private let jsonDecoder = JSONDecoder()

    public init() {}

    public mutating func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        guard let length = buffer.getInteger(at: buffer.readerIndex, as: UInt32.self) else { return .needMoreData }
        guard length <= maxFrameLength else { throw FrameError.frameTooLarge(Int(length)) }
        guard buffer.readableBytes >= 4 + Int(length) else { return .needMoreData }
        buffer.moveReaderIndex(forwardBy: 4)
        let body = buffer.readSlice(length: Int(length))!
        let message = try jsonDecoder.decode(LinkMessage.self, from: Data(body.readableBytesView))
        context.fireChannelRead(wrapInboundOut(message))
        return .continue
    }
}

/// `LinkMessage` → `[4 字节大端长度][JSON]`
public struct LinkMessageEncoder: MessageToByteEncoder {
    public typealias OutboundIn = LinkMessage

    private let jsonEncoder = JSONEncoder()

    public init() {}

    public func encode(data: LinkMessage, out: inout ByteBuffer) throws {
        let body = try jsonEncoder.encode(data)
        guard body.count <= maxFrameLength else { throw FrameError.frameTooLarge(body.count) }
        out.writeInteger(UInt32(body.count))
        out.writeBytes(body)
    }
}
