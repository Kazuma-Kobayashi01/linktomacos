import Foundation
import NIOCore
import NIOPosix
import NIOSSL

public let bonjourServiceType = "_linktomacos._tcp."
public let defaultPort = 47152

public enum LinkEvent: Sendable {
    case listening(port: Int)
    case connected(PairedDevice, newlyPaired: Bool, address: String?)
    case message(deviceId: String, LinkMessage)
    case disconnected(deviceId: String, reason: String)
    case rejected(reason: String)
}

/// Mac 端服务：TLS 监听、Bonjour 广播、握手鉴权、心跳，以及按设备维护会话。
public final class LinkServer: @unchecked Sendable {
    static let heartbeatInterval: TimeAmount = .seconds(5)
    static let readTimeout: TimeAmount = .seconds(20)
    static let helloTimeout: TimeAmount = .seconds(10)

    public let events: AsyncStream<LinkEvent>
    private let eventSink: AsyncStream<LinkEvent>.Continuation

    private let identity: LinkIdentity
    private let pairing: PairingStore
    private let macName: String
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var serverChannel: Channel?
    private var bonjour: NetService?

    private let lock = NSLock()
    private var sessions: [String: Channel] = [:]
    private var inboundHook: (@Sendable (String, LinkMessage) -> Bool)?

    public private(set) var port: Int = 0

    public init(identity: LinkIdentity, pairing: PairingStore, macName: String) {
        self.identity = identity
        self.pairing = pairing
        self.macName = macName
        (events, eventSink) = AsyncStream.makeStream(of: LinkEvent.self)
    }

    public func start() async throws {
        var tls = TLSConfiguration.makeServerConfiguration(
            certificateChain: [.certificate(try identity.nioCertificate())],
            privateKey: .privateKey(try identity.nioPrivateKey())
        )
        tls.minimumTLSVersion = .tlsv13
        // 要求客户端出示证书；自签名证书在这里一律放行，真正的校验在 hello 阶段按指纹做。
        tls.certificateVerification = .noHostnameVerification
        let sslContext = try NIOSSLContext(configuration: tls)

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 16)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(.socketOption(.tcp_nodelay), value: 1)
            .childChannelInitializer { [weak self] channel in
                guard let self else { return channel.eventLoop.makeSucceededVoidFuture() }
                return channel.eventLoop.makeCompletedFuture {
                    let ssl = NIOSSLServerHandler(context: sslContext) { _, promise in
                        promise.succeed(.certificateVerified)
                    }
                    try channel.pipeline.syncOperations.addHandlers([
                        ssl,
                        IdleStateHandler(readTimeout: Self.readTimeout, writeTimeout: Self.heartbeatInterval),
                        ByteToMessageHandler(LinkMessageDecoder()),
                        MessageToByteHandler(LinkMessageEncoder()),
                        SessionHandler(server: self),
                    ])
                }
            }

        let channel: Channel
        do {
            channel = try await bootstrap.bind(host: "0.0.0.0", port: defaultPort).get()
        } catch {
            channel = try await bootstrap.bind(host: "0.0.0.0", port: 0).get()
        }
        serverChannel = channel
        port = channel.localAddress?.port ?? 0
        await MainActor.run { publishBonjour() }
        eventSink.yield(.listening(port: port))
    }

    /// 在连接线程上同步拦截入站消息，返回 true 表示已处理、不再进入 `events`。
    /// 文件数据量大，不能经过主线程的事件流。
    public func setInboundHook(_ hook: (@Sendable (String, LinkMessage) -> Bool)?) {
        lock.withLock { inboundHook = hook }
    }

    public func send(_ message: LinkMessage, to deviceId: String) {
        lock.withLock { sessions[deviceId] }?.writeAndFlush(message, promise: nil)
    }

    /// 和 `send` 一样，但等数据真正写进套接字缓冲区才返回。发大文件时逐块等待，就不会把整个文件堆在内存里。
    public func sendAwaiting(_ message: LinkMessage, to deviceId: String) async throws {
        guard let channel = lock.withLock({ sessions[deviceId] }) else { throw ChannelError.ioOnClosedChannel }
        try await channel.writeAndFlush(message).get()
    }

    public var connectedDeviceIds: [String] {
        lock.withLock { Array(sessions.keys) }
    }

    /// 向所有会话发送 goodbye 并关闭，最多等待 1 秒。用于退出 App 和系统睡眠前。
    public func disconnectAll(reason: String) async {
        let channels = lock.withLock { Array(sessions.values) }
        await withTaskGroup(of: Void.self) { group in
            for channel in channels {
                group.addTask {
                    try? await channel.writeAndFlush(LinkMessage.goodbye(reason: reason)).get()
                    try? await channel.close().get()
                }
            }
            group.addTask { try? await Task.sleep(for: .seconds(1)) }
            await group.next()
        }
    }

    public func shutdown(reason: String) async {
        // 先停止接受新连接并撤下 Bonjour，否则手机收到 goodbye 后立刻重连，会连上一个正在退出的 Mac
        try? await serverChannel?.close().get()
        serverChannel = nil
        await MainActor.run { bonjour?.stop() }
        await disconnectAll(reason: reason)
        try? await group.shutdownGracefully()
        eventSink.finish()
    }

    @MainActor
    private func publishBonjour() {
        let service = NetService(domain: "local.", type: bonjourServiceType, name: macName, port: Int32(port))
        let txt = ["fp": Data(identity.fingerprint.prefix(16).utf8), "v": Data("\(linkProtocolVersion)".utf8)]
        service.setTXTRecord(NetService.data(fromTXTRecord: txt))
        service.publish()
        bonjour = service
    }

    // MARK: - 会话回调（在 EventLoop 线程调用）

    fileprivate func authorize(hello: Hello, peerFingerprint: String) -> PairingStore.Verdict {
        pairing.evaluate(hello: hello, peerFingerprint: peerFingerprint)
    }

    fileprivate func register(_ device: PairedDevice, channel: Channel, newlyPaired: Bool) {
        let previous = lock.withLock {
            let old = sessions[device.deviceId]
            sessions[device.deviceId] = channel
            return old
        }
        if let previous, previous !== channel {
            previous.close(promise: nil)
        }
        channel.writeAndFlush(LinkMessage.helloAck(.init(accepted: true, macName: macName)), promise: nil)
        eventSink.yield(.connected(device, newlyPaired: newlyPaired, address: channel.remoteAddress?.ipAddress))
    }

    fileprivate func unregister(deviceId: String, channel: Channel, reason: String) {
        let removed = lock.withLock {
            guard sessions[deviceId] === channel else { return false }
            sessions[deviceId] = nil
            return true
        }
        if removed { eventSink.yield(.disconnected(deviceId: deviceId, reason: reason)) }
    }

    fileprivate func received(_ message: LinkMessage, from deviceId: String) {
        if let hook = lock.withLock({ inboundHook }), hook(deviceId, message) { return }
        eventSink.yield(.message(deviceId: deviceId, message))
    }

    fileprivate func reject(channel: Channel, reason: String) {
        eventSink.yield(.rejected(reason: reason))
        let ack = LinkMessage.helloAck(.init(accepted: false, macName: macName, reason: reason))
        channel.writeAndFlush(ack).whenComplete { _ in channel.close(promise: nil) }
    }

    fileprivate var name: String { macName }
}

/// 每条连接一个：等待 hello → 鉴权 → 转发消息；空闲写超时发 ping，读超时断开。
private final class SessionHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = LinkMessage

    private weak var server: LinkServer?
    private var deviceId: String?
    private var helloDeadline: Scheduled<Void>?
    private var closeReason = "connection closed"

    init(server: LinkServer) {
        self.server = server
    }

    func channelActive(context: ChannelHandlerContext) {
        let channel = context.channel
        helloDeadline = context.eventLoop.scheduleTask(in: LinkServer.helloTimeout) {
            channel.close(promise: nil)
        }
        context.fireChannelActive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let message = unwrapInboundIn(data)
        guard let deviceId else {
            handleFirst(message, context: context)
            return
        }
        switch message {
        case .ping(let t):
            context.writeAndFlush(NIOAny(LinkMessage.pong(t: t)), promise: nil)
        case .pong:
            break
        case .goodbye(let reason):
            closeReason = "peer goodbye: \(reason)"
            context.close(promise: nil)
        default:
            server?.received(message, from: deviceId)
        }
    }

    private func handleFirst(_ message: LinkMessage, context: ChannelHandlerContext) {
        guard case .hello(let hello) = message, let server else {
            context.close(promise: nil)
            return
        }
        helloDeadline?.cancel()
        let channel = context.channel
        let loopBound = NIOLoopBound(self, eventLoop: context.eventLoop)
        channel.nioSSL_peerCertificate().whenComplete { result in
            let handler = loopBound.value
            guard case .success(let cert?) = result, let der = try? cert.toDERBytes() else {
                server.reject(channel: channel, reason: "no client certificate")
                return
            }
            let fingerprint = LinkIdentity.fingerprint(ofDER: der)
            guard hello.protocolVersion == linkProtocolVersion else {
                server.reject(channel: channel, reason: "protocol version \(hello.protocolVersion) unsupported")
                return
            }
            switch server.authorize(hello: hello, peerFingerprint: fingerprint) {
            case .known(let device):
                handler.deviceId = device.deviceId
                server.register(device, channel: channel, newlyPaired: false)
            case .newlyPaired(let device):
                handler.deviceId = device.deviceId
                server.register(device, channel: channel, newlyPaired: true)
            case .rejected(let reason):
                server.reject(channel: channel, reason: reason)
            }
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        guard let idle = event as? IdleStateHandler.IdleStateEvent else {
            context.fireUserInboundEventTriggered(event)
            return
        }
        switch idle {
        case .write:
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            context.writeAndFlush(NIOAny(LinkMessage.ping(t: now)), promise: nil)
        case .read:
            closeReason = "heartbeat timeout"
            context.close(promise: nil)
        case .all:
            break
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        closeReason = "error: \(error)"
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        helloDeadline?.cancel()
        if let deviceId {
            server?.unregister(deviceId: deviceId, channel: context.channel, reason: closeReason)
        }
        context.fireChannelInactive()
    }
}
