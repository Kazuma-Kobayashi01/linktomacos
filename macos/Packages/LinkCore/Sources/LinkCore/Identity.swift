import Crypto
import Foundation
import NIOSSL
import X509

/// 本机的长期身份：P-256 私钥 + 自签名证书，以 PEM 存在 Application Support 下。
///
/// 不放钥匙串：ad-hoc 签名的 App 每次重新编译签名都会变，钥匙串会反复弹授权框。
public struct LinkIdentity: Sendable {
    public let certificatePEM: String
    public let privateKeyPEM: String
    /// 证书 DER 的 SHA-256，十六进制小写。
    public let fingerprint: String

    public static func loadOrCreate(in directory: URL, commonName: String) throws -> LinkIdentity {
        let certURL = directory.appendingPathComponent("identity-cert.pem")
        let keyURL = directory.appendingPathComponent("identity-key.pem")
        if let certPEM = try? String(contentsOf: certURL, encoding: .utf8),
           let keyPEM = try? String(contentsOf: keyURL, encoding: .utf8) {
            return try LinkIdentity(certificatePEM: certPEM, privateKeyPEM: keyPEM)
        }

        let key = P256.Signing.PrivateKey()
        let name = try DistinguishedName { CommonName(commonName) }
        let now = Date()
        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: .init(key.publicKey),
            notValidBefore: now.addingTimeInterval(-3600),
            notValidAfter: now.addingTimeInterval(20 * 365 * 24 * 3600),
            issuer: name,
            subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.notCertificateAuthority)
                KeyUsage(digitalSignature: true)
                try ExtendedKeyUsage([.serverAuth, .clientAuth])
            },
            issuerPrivateKey: .init(key)
        )
        let certPEM = try certificate.serializeAsPEM().pemString
        let keyPEM = key.pemRepresentation

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try certPEM.write(to: certURL, atomically: true, encoding: .utf8)
        try keyPEM.write(to: keyURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
        return try LinkIdentity(certificatePEM: certPEM, privateKeyPEM: keyPEM)
    }

    init(certificatePEM: String, privateKeyPEM: String) throws {
        self.certificatePEM = certificatePEM
        self.privateKeyPEM = privateKeyPEM
        let der = try NIOSSLCertificate(bytes: Array(certificatePEM.utf8), format: .pem).toDERBytes()
        self.fingerprint = Self.fingerprint(ofDER: der)
    }

    public static func fingerprint<D: DataProtocol>(ofDER der: D) -> String {
        SHA256.hash(data: Array(der)).map { String(format: "%02x", $0) }.joined()
    }

    func nioCertificate() throws -> NIOSSLCertificate {
        try NIOSSLCertificate(bytes: Array(certificatePEM.utf8), format: .pem)
    }

    func nioPrivateKey() throws -> NIOSSLPrivateKey {
        try NIOSSLPrivateKey(bytes: Array(privateKeyPEM.utf8), format: .pem)
    }
}
