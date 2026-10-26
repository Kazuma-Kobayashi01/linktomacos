import Foundation
import NIOCore
import NIOPosix

/// 投屏助手（另一个独立的 App）经主程序转发请求时用的起始请求编号，见 `PhoneRemote.init(firstRequestId:)`。
public let relayRequestIdBase = 1 << 30

/// 本机的 Unix 套接字路径：每个用户一份，放在系统临时目录（路径短，不会超过套接字路径的长度上限）。
public func relaySocketPath() -> String {
    (NSTemporaryDirectory() as NSString).appendingPathComponent("linktomacos-relay-\(getuid()).sock")
}

/// 主程序里的中继服务器：投屏助手 App 连进来，把它的请求、输入和麦克风数据转给手机，
/// 把手机发来的、属于助手的响应、视频和音频数据、投屏事件转回给它。
///
/// 本机通信，用和手机链路一样的帧格式（`LinkMessage`）。助手启动时拿到一次性令牌，连上后第一条消息必须带它。
public final class RelayServer: @unchecked Sendable {
    private let path: String
    private let token: String
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var serverChannel: Channel?
    private let lock = NSLock()
    private var client: Channel?
    /// 助手拥有的数据流（投屏的视频、音频），从发给助手的响应里登记。
    private var streams: Set<UInt32> = []

    /// 助手发来的消息，要转给手机（在网络线程上调用）。
    public var onFromHelper: (@Sendable (LinkMessage) -> Void)?
    /// 助手连上或断开。
    public var onClientChange: (@Sendable (Bool) -> Void)?

    public init(path: String = relaySocketPath(), token: String) {
        self.path = path
        self.token = token
    }

    public func start() async throws {
        unlink(path)
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 4)
            .childChannelInitializer { [weak self] channel in
                guard let self else { return channel.eventLoop.makeSucceededVoidFuture() }
                return channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandlers([
                        ByteToMessageHandler(LinkMessageDecoder()),
                        MessageToByteHandler(LinkMessageEncoder()),
                        RelayServerHandler(server: self),
                    ])
                }
            }
        serverChannel = try await bootstrap.bind(unixDomainSocketPath: path).get()
        chmod(path, 0o600)
    }

    public var hasClient: Bool { lock.withLock { client != nil } }

    public func sendToHelper(_ message: LinkMessage) {
        lock.withLock { client }?.writeAndFlush(message, promise: nil)
    }

    /// 手机发来的消息：属于助手的转给助手并返回 true；其余返回 false，由主程序自己处理。
    public func routeFromPhone(_ message: LinkMessage) -> Bool {
        switch message {
        case .response(let response):
            guard response.id >= relayRequestIdBase else { return false }
            if let result = response.result {
                lock.withLock {
                    for key in ["streamId", "audioStreamId", "micStreamId"] {
                        if let id = result[key]?.int64Value, id > 0 { streams.insert(UInt32(truncatingIfNeeded: id)) }
                    }
                }
            }
            sendToHelper(message)
            return true
        case .data(let streamId, _):
            guard lock.withLock({ streams.contains(streamId) }) else { return false }
            sendToHelper(message)
            return true
        case .streamEnd(let end):
            guard lock.withLock({ streams.contains(UInt32(truncatingIfNeeded: end.streamId)) }) else { return false }
            sendToHelper(message)
            return true
        case .mirrorEvent:
            guard hasClient else { return false }
            sendToHelper(message)
            return true
        default:
            return false
        }
    }

    public func shutdown() async {
        try? await serverChannel?.close().get()
        lock.withLock { client }?.close(promise: nil)
        unlink(path)
        try? await group.shutdownGracefully()
    }

    // MARK: 内部

    fileprivate func attach(_ channel: Channel) {
        let previous = lock.withLock { () -> Channel? in
            let old = client
            client = channel
            streams.removeAll()
            return old
        }
        previous?.close(promise: nil)
        onClientChange?(true)
    }

    fileprivate func detach(_ channel: Channel) {
        let wasCurrent = lock.withLock { () -> Bool in
            guard client === channel else { return false }
            client = nil
            streams.removeAll()
            return true
        }
        if wasCurrent { onClientChange?(false) }
    }

    fileprivate func checkToken(_ candidate: String) -> Bool {
        let a = Array(token.utf8), b = Array(candidate.utf8)
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for (x, y) in zip(a, b) { difference |= x ^ y }
        return difference == 0
    }
}

private final class RelayServerHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = LinkMessage

    private weak var server: RelayServer?
    private var authenticated = false

    init(server: RelayServer) { self.server = server }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let message = unwrapInboundIn(data)
        guard authenticated else {
            if case .request(let request) = message, request.method == "relayHello",
               let token = request.params["token"]?.stringValue, server?.checkToken(token) == true {
                authenticated = true
                server?.attach(context.channel)
            } else {
                context.close(promise: nil)
            }
            return
        }
        server?.onFromHelper?(message)
    }

    func channelInactive(context: ChannelHandlerContext) {
        if authenticated { server?.detach(context.channel) }
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}

/// 投屏助手里的中继客户端：连到主程序，收发 `LinkMessage`。
public final class RelayClient: @unchecked Sendable {
    private let path: String
    private let token: String
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private let lock = NSLock()
    private var channel: Channel?

    /// 主程序发来的消息（在网络线程上调用）。
    public var onMessage: (@Sendable (LinkMessage) -> Void)?
    /// 和主程序的连接断了。
    public var onClose: (@Sendable () -> Void)?

    public init(path: String = relaySocketPath(), token: String) {
        self.path = path
        self.token = token
    }

    public func connect() async throws {
        let bootstrap = ClientBootstrap(group: group)
            .channelInitializer { [weak self] channel in
                guard let self else { return channel.eventLoop.makeSucceededVoidFuture() }
                return channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandlers([
                        ByteToMessageHandler(LinkMessageDecoder()),
                        MessageToByteHandler(LinkMessageEncoder()),
                        RelayClientHandler(client: self),
                    ])
                }
            }
        let channel = try await bootstrap.connect(unixDomainSocketPath: path).get()
        lock.withLock { self.channel = channel }
        channel.writeAndFlush(
            LinkMessage.request(RPCRequest(id: 0, method: "relayHello", params: .object(["token": .string(token)]))), promise: nil)
    }

    public func send(_ message: LinkMessage) {
        lock.withLock { channel }?.writeAndFlush(message, promise: nil)
    }

    public func close() {
        lock.withLock { channel }?.close(promise: nil)
    }

    fileprivate func received(_ message: LinkMessage) { onMessage?(message) }
    fileprivate func closed() { onClose?() }
}

private final class RelayClientHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = LinkMessage

    private weak var client: RelayClient?

    init(client: RelayClient) { self.client = client }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        client?.received(unwrapInboundIn(data))
    }

    func channelInactive(context: ChannelHandlerContext) {
        client?.closed()
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}
