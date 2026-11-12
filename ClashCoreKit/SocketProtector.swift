import Darwin
import Foundation

/// iOS counterpart of Android's `VpnService.protect()`.
///
/// Instead of marking sockets, the extension binds every outbound socket to the
/// physical interface. That keeps the core's own traffic out of the utun and is
/// the darwin equivalent of `SO_MARK`.
public final class SocketProtector {
    // Values from <netinet/in.h> on Darwin.
    private static let ipBoundIf: Int32 = 25
    private static let ipv6BoundIf: Int32 = 125

    private let lock = NSLock()
    private var interfaceIndex: UInt32

    public init(interfaceIndex: UInt32 = SocketProtector.defaultInterfaceIndex()) {
        self.interfaceIndex = interfaceIndex
    }

    public func update(interfaceIndex: UInt32) {
        lock.lock()
        defer { lock.unlock() }

        if interfaceIndex != 0 {
            self.interfaceIndex = interfaceIndex
        }
    }

    public func protect(fd: Int32) {
        lock.lock()
        var index = interfaceIndex
        lock.unlock()

        if index == 0 {
            index = Self.defaultInterfaceIndex()
        }

        guard index != 0 else { return }

        var value = Int32(index)
        let size = socklen_t(MemoryLayout<Int32>.size)

        setsockopt(fd, IPPROTO_IP, Self.ipBoundIf, &value, size)
        setsockopt(fd, IPPROTO_IPV6, Self.ipv6BoundIf, &value, size)
    }

    /// Best effort detection of the primary physical interface (en0 / pdp_ip0).
    /// The tunnel interfaces (utun*) are skipped so that the core never loops back.
    public static func defaultInterfaceIndex() -> UInt32 {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return 0 }

        defer { freeifaddrs(pointer) }

        var fallback: UInt32 = 0
        var candidate: UnsafeMutablePointer<ifaddrs>? = first

        while let interface = candidate {
            defer { candidate = interface.pointee.ifa_next }

            guard let address = interface.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) || address.pointee.sa_family == UInt8(AF_INET6) else {
                continue
            }

            let flags = Int32(interface.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }

            let name = String(cString: interface.pointee.ifa_name)

            if name.hasPrefix("utun") || name.hasPrefix("lo") {
                continue
            }

            let index = if_nametoindex(name)

            if name == "en0" {
                return index
            }

            if name.hasPrefix("pdp_ip") || name.hasPrefix("en") {
                if fallback == 0 {
                    fallback = index
                }
            }
        }

        return fallback
    }
}
