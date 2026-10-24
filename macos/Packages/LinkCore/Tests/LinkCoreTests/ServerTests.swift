import Foundation
import NIOCore
import NIOPosix
import NIOSSL
import Testing
@testable import LinkCore

/// 收集客户端收到的消息。
private final class Collector: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = LinkMessage
    let stream: AsyncStream<LinkMessage>
    private let sink: AsyncStream<LinkMessage>.Continuation
    init() { (stream, sink) = AsyncStream.makeStream() }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) { sink.yield(unwrapInboundIn(data)) }
    func channelInactive(context: ChannelHandlerContext) { sink.finish() }
}

@Suite(.serialized) struct ServerTests {
    private func connect(port: Int, identity: LinkIdentity, pinned: String) async throws -> (Channel, Collector) {
        var tls = TLSConfiguration.makeClientConfiguration()
        tls.certificateChain = [.certificate(try identity.nioCertificate())]
        tls.privateKey = .privateKey(try identity.nioPrivateKey())
        tls.certificateVerification = .noHostnameVerification
        let context = try NIOSSLContext(configuration: tls)
        let collector = Collector()
        let channel = try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let ssl = try NIOSSLClientHandler(context: context, serverHostname: nil) { certs, promise in
                        let fp = (try? certs.first?.toDERBytes()).map { LinkIdentity.fingerprint(ofDER: $0) }
                        promise.succeed(fp == pinned ? .certificateVerified : .failed)
                    }
                    try channel.pipeline.syncOperations.addHandlers([
                        ssl, ByteToMessageHandler(LinkMessageDecoder()), MessageToByteHandler(LinkMessageEncoder()),
                        collector,
                    ])
                }
            }
            .connect(host: "127.0.0.1", port: port).get()
        return (channel, collector)
    }

    private func hello(_ token: String?) -> LinkMessage {
        .hello(Hello(protocolVersion: 1, deviceId: "phone", deviceName: "S23U", model: "SM-S9180",
                     osVersion: "15", appVersion: "0.1", pairingToken: token))
    }

    @Test func pairsThenReconnectsByFingerprint() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let macIdentity = try LinkIdentity.loadOrCreate(in: dir.appendingPathComponent("mac"), commonName: "mac")
        let phoneIdentity = try LinkIdentity.loadOrCreate(in: dir.appendingPathComponent("phone"), commonName: "phone")
        let otherIdentity = try LinkIdentity.loadOrCreate(in: dir.appendingPathComponent("other"), commonName: "x")
        let pairing = PairingStore(directory: dir)
        let server = LinkServer(identity: macIdentity, pairing: pairing, macName: "Test Mac")
        try await server.start()
        let token = pairing.issueToken().token

        // 1. 首次配对：携带令牌
        let (c1, r1) = try await connect(port: server.port, identity: phoneIdentity, pinned: macIdentity.fingerprint)
        try await c1.writeAndFlush(hello(token)).get()
        var it1 = r1.stream.makeAsyncIterator()
        #expect(await it1.next() == .helloAck(.init(accepted: true, macName: "Test Mac")))
        try await c1.writeAndFlush(LinkMessage.ping(t: 1)).get()
        #expect(await it1.next() == .pong(t: 1))
        try await c1.close().get()

        // 2. 已配对：不带令牌，靠证书指纹
        let (c2, r2) = try await connect(port: server.port, identity: phoneIdentity, pinned: macIdentity.fingerprint)
        try await c2.writeAndFlush(hello(nil)).get()
        var it2 = r2.stream.makeAsyncIterator()
        #expect(await it2.next() == .helloAck(.init(accepted: true, macName: "Test Mac")))

        // 3. 别的证书冒充同一个 deviceId：拒绝
        let (c3, r3) = try await connect(port: server.port, identity: otherIdentity, pinned: macIdentity.fingerprint)
        try await c3.writeAndFlush(hello(token)).get()
        var it3 = r3.stream.makeAsyncIterator()
        guard case .helloAck(let ack) = await it3.next() else { Issue.record("no ack"); return }
        #expect(ack.accepted == false)

        // 4. 退出时向在线设备发 goodbye
        await server.disconnectAll(reason: "quit")
        #expect(await it2.next() == .goodbye(reason: "quit"))
        await server.shutdown(reason: "quit")
    }
}
