import Darwin
import Foundation
import NetworkExtension

public enum TunBridgeError: LocalizedError {
    case socketpairFailed(Int32)
    case setupFailed(String)

    public var errorDescription: String? {
        switch self {
        case .socketpairFailed(let code):
            return "socketpair failed: \(String(cString: strerror(code)))"
        case .setupFailed(let message):
            return message
        }
    }
}

/// Bridges `NEPacketTunnelFlow` and a `SOCK_DGRAM` socketpair.
///
/// The Go side (sing-tun, darwin) only ever sees the second fd of the pair and
/// expects raw utun frames: a 4 byte big endian address-family header followed
/// by the IP packet. SOCK_DGRAM preserves datagram boundaries, which is exactly
/// what utun semantics need.
public final class TunBridge {
    public let goFD: Int32

    private let localFD: Int32
    private let flow: NEPacketTunnelFlow
    private let readQueue = DispatchQueue(label: "clash.tun.read", qos: .userInitiated)
    private let writeQueue = DispatchQueue(label: "clash.tun.write", qos: .userInitiated)
    private var stopped = false

    public init(flow: NEPacketTunnelFlow, bufferSize: Int = 4 * 1024 * 1024) throws {
        var fds: [Int32] = [-1, -1]

        guard socketpair(AF_UNIX, SOCK_DGRAM, 0, &fds) == 0 else {
            throw TunBridgeError.socketpairFailed(errno)
        }

        localFD = fds[0]
        goFD = fds[1]
        self.flow = flow

        for fd in fds {
            var size = Int32(bufferSize)
            setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &size, socklen_t(MemoryLayout<Int32>.size))
            setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &size, socklen_t(MemoryLayout<Int32>.size))

            let flags = fcntl(fd, F_GETFL, 0)
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }
    }

    public func start() {
        readQueue.async { [weak self] in
            self?.pumpPacketsFromFlow()
        }

        writeQueue.async { [weak self] in
            self?.pumpPacketsFromCore()
        }
    }

    public func stop() {
        guard !stopped else { return }
        stopped = true

        close(goFD)
        close(localFD)
    }

    private func pumpPacketsFromFlow() {
        flow.readPacketObjects { [weak self] packets in
            guard let self, !self.stopped else { return }

            for packet in packets {
                self.writeToCore(packet)
            }

            self.pumpPacketsFromFlow()
        }
    }

    private func writeToCore(_ packet: NEPacket) {
        var buffer = [UInt8](repeating: 0, count: packet.data.count + 4)
        let family = Self.addressFamily(for: packet)

        buffer[0] = 0
        buffer[1] = 0
        buffer[2] = 0
        buffer[3] = family

        packet.data.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                memcpy(&buffer[4], base, packet.data.count)
            }
        }

        _ = buffer.withUnsafeBufferPointer { pointer in
            write(localFD, pointer.baseAddress, pointer.count)
        }
    }

    private func pumpPacketsFromCore() {
        var buffer = [UInt8](repeating: 0, count: 65_536)

        while !stopped {
            let count = read(localFD, &buffer, buffer.count)

            if count <= 4 {
                if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    usleep(1000)
                    continue
                }

                continue
            }

            let family = buffer[3]
            let payload = Data(buffer[4..<count])
            let packet = NEPacket(data: payload, protocolFamily: family)

            flow.writePacketObjects([packet])
        }
    }

    private static func addressFamily(for packet: NEPacket) -> UInt8 {
        switch packet.protocolFamily {
        case sa_family_t(AF_INET), sa_family_t(AF_INET6):
            return packet.protocolFamily
        default:
            guard let first = packet.data.first else { return sa_family_t(AF_INET) }
            return sa_family_t((first >> 4) == 6 ? AF_INET6 : AF_INET)
        }
    }
}
