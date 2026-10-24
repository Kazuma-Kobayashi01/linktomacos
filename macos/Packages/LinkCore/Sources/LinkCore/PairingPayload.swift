import Darwin
import Foundation

/// 二维码内容：`linktomacos://pair?v=1&n=..&h=ip1,ip2&p=..&fp=..&t=..`
public struct PairingPayload: Equatable, Sendable {
    public var macName: String
    public var hosts: [String]
    public var port: Int
    public var fingerprint: String
    public var token: String

    public init(macName: String, hosts: [String], port: Int, fingerprint: String, token: String) {
        self.macName = macName
        self.hosts = hosts
        self.port = port
        self.fingerprint = fingerprint
        self.token = token
    }

    public var uri: String {
        var components = URLComponents()
        components.scheme = "linktomacos"
        components.host = "pair"
        components.queryItems = [
            .init(name: "v", value: "\(linkProtocolVersion)"),
            .init(name: "n", value: macName),
            .init(name: "h", value: hosts.joined(separator: ",")),
            .init(name: "p", value: "\(port)"),
            .init(name: "fp", value: fingerprint),
            .init(name: "t", value: token),
        ]
        return components.string!
    }

    public init?(uri: String) {
        guard let components = URLComponents(string: uri),
              components.scheme == "linktomacos", components.host == "pair",
              let items = components.queryItems
        else { return nil }
        let query = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        guard let name = query["n"], let hosts = query["h"], let port = query["p"].flatMap(Int.init),
              let fp = query["fp"], let token = query["t"]
        else { return nil }
        self.init(macName: name, hosts: hosts.split(separator: ",").map(String.init), port: port,
                  fingerprint: fp, token: token)
    }

    /// 本机可被局域网访问的 IPv4 地址（en* 接口，排除回环和链路本地地址）。
    public static func localIPv4Addresses() -> [String] {
        var result: [String] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  (ifa.ifa_flags & UInt32(IFF_UP)) != 0, (ifa.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
                  String(cString: ifa.ifa_name).hasPrefix("en")
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            if !ip.hasPrefix("169.254.") { result.append(ip) }
        }
        return result
    }
}
