import Darwin
import Foundation

enum NetworkAddresses {
    static func localIPv4() -> [String] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }

        var result: [String] = []
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let item = current?.pointee {
            defer { current = item.ifa_next }
            guard let addressPointer = item.ifa_addr,
                  addressPointer.pointee.sa_family == UInt8(AF_INET),
                  (item.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
                  (item.ifa_flags & UInt32(IFF_UP)) != 0 else { continue }
            var address = addressPointer.pointee
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(&address, socklen_t(address.sa_len), &host, socklen_t(host.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                let bytes = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                result.append(String(decoding: bytes, as: UTF8.self))
            }
        }
        return Array(Set(result)).sorted()
    }
}
