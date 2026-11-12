import ClashCoreKit
import Foundation
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private static let tunnelRemoteAddress = "172.19.0.1"
    private static let gateway4 = "172.19.0.1"
    private static let gateway6 = "fdfe:dcba:9876::1"
    private static let portal4 = "172.19.0.2"
    private static let portal6 = "fdfe:dcba:9876::2"

    private let core = ClashCore.shared
    private let logStore = ProviderLogStore()
    private var bridge: TunBridge?
    private var protector = SocketProtector()
    private var statusTimer: DispatchSourceTimer?
    private var profilePath = ""
    private var startedAt = Date()

    private var configuration: [String: Any] {
        (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration ?? [:]
    }

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        Task {
            do {
                try await start(options: options ?? [:])
                completionHandler(nil)
            } catch {
                logStore.append(level: "error", message: "startTunnel: \(error.localizedDescription)")
                completionHandler(error)
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        Task {
            await core.stopTun()
            bridge?.stop()
            bridge = nil

            statusTimer?.cancel()
            statusTimer = nil

            writeStatus(running: false)
            logStore.flush()

            completionHandler()
        }
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        Task {
            let response = await handle(message: messageData)
            completionHandler?(response)
        }
    }

    private func start(options: [String: NSObject]) async throws {
        ClashShared.ensureDirectories()

        let config = configuration

        guard let home = config[TunnelKeys.home] as? String,
              let profile = config[TunnelKeys.profilePath] as? String else {
            throw ClashCoreError("missing home/profile in provider configuration")
        }

        profilePath = profile
        startedAt = Date()

        let settings = TunnelSettings.load()
        let stack = (config[TunnelKeys.stack] as? String) ?? settings.stack
        let ipv6 = (config[TunnelKeys.ipv6] as? Bool) ?? settings.ipv6
        let mtu = (config[TunnelKeys.mtu] as? Int) ?? settings.mtu

        await core.initialize(
            home: URL(fileURLWithPath: home),
            versionName: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            gitVersion: "ios_unknown_\(Int(Date().timeIntervalSince1970))"
        )

        startLogSubscription()

        try await core.load(path: URL(fileURLWithPath: profile))

        let tunBridge = try TunBridge(flow: packetFlow)
        bridge = tunBridge

        try await setNetworkSettings(ipv6: ipv6, mtu: mtu)

        protector = SocketProtector()

        try await core.startTun(
            fd: tunBridge.goFD,
            stack: stack,
            gateway: ipv6 ? "\(Self.gateway4)/30,\(Self.gateway6)/126" : "\(Self.gateway4)/30",
            portal: ipv6 ? "\(Self.portal4),\(Self.portal6)" : Self.portal4,
            dns: settings.dnsHijacking ? "0.0.0.0" : (ipv6 ? "\(Self.portal4),\(Self.portal6)" : Self.portal4),
            markSocket: { [protector] fd in
                protector.protect(fd: fd)
            },
            queryUid: { _, _, _ in
                -1
            }
        )

        tunBridge.start()

        startStatusTimer()
        writeStatus(running: true)

        logStore.append(level: "info", message: "tunnel started, stack=\(stack)")
    }

    private func setNetworkSettings(ipv6: Bool, mtu: Int) async throws {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: Self.tunnelRemoteAddress)

        let v4 = NEIPv4Settings(
            addresses: [Self.gateway4],
            subnetMasks: ["255.255.255.252"]
        )

        if TunnelSettings.load().bypassPrivateNetwork {
            v4.includedRoutes = Self.privateRoutesV4
        } else {
            v4.includedRoutes = [NEIPv4Route.default()]
        }

        settings.ipv4Settings = v4

        if ipv6 {
            let v6 = NEIPv6Settings(addresses: [Self.gateway6], networkPrefixLengths: [126])

            if TunnelSettings.load().bypassPrivateNetwork {
                v6.includedRoutes = Self.privateRoutesV6
            } else {
                v6.includedRoutes = [NEIPv6Route.default()]
            }

            settings.ipv6Settings = v6
        }

        let dns = NEDNSSettings(servers: [Self.portal4])
        dns.matchDomains = [""]
        settings.dnsSettings = dns

        settings.mtu = NSNumber(value: mtu)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            setTunnelNetworkSettings(settings) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func startLogSubscription() {
        Task {
            await core.subscribeLogcat { [logStore] message in
                logStore.append(level: message.level.rawValue, message: message.message)
                return true
            }
        }
    }

    private func startStatusTimer() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 1, repeating: 1)

        timer.setEventHandler { [weak self] in
            guard let self else { return }

            Task {
                self.writeStatus(running: true)
            }
        }

        timer.resume()
        statusTimer = timer
    }

    private func writeStatus(running: Bool) {
        Task {
            let mode = (try? await core.queryTunnelState().mode.rawValue) ?? "unknown"
            let now = await core.trafficNow()
            let total = await core.trafficTotal()

            let status: [String: Any] = [
                "running": running,
                "mode": mode,
                "up": now.upload,
                "down": now.download,
                "totalUp": total.upload,
                "totalDown": total.download,
                "profile": profilePath,
                "startedAt": Int(startedAt.timeIntervalSince1970),
                "updatedAt": Int(Date().timeIntervalSince1970),
            ]

            if let data = try? JSONSerialization.data(withJSONObject: status),
               let text = String(data: data, encoding: .utf8) {
                ClashShared.defaults.set(text, forKey: "tunnel.status")
            }
        }
    }

    private func handle(message: Data) async -> Data? {
        guard let request = (try? JSONSerialization.jsonObject(with: message)) as? [String: Any],
              let action = request["action"] as? String else {
            return Self.encode(["ok": false, "error": "invalid request"])
        }

        do {
            switch action {
            case "status":
                let now = await core.trafficNow()
                let total = await core.trafficTotal()
                let mode = try await core.queryTunnelState().mode.rawValue

                return Self.encode([
                    "ok": true,
                    "data": [
                        "mode": mode,
                        "up": now.upload,
                        "down": now.download,
                        "totalUp": total.upload,
                        "totalDown": total.download,
                        "profile": profilePath,
                    ],
                ])

            case "groups":
                let names = try await core.queryGroupNames()
                return Self.encode(["ok": true, "data": names])

            case "group":
                guard let name = request["name"] as? String else {
                    return Self.encode(["ok": false, "error": "missing name"])
                }

                let group = try await core.queryGroup(name: name)
                let data = try JSONEncoder().encode(group)

                return Self.encode([
                    "ok": true,
                    "data": (try? JSONSerialization.jsonObject(with: data)) ?? [:],
                ])

            case "select":
                guard let group = request["group"] as? String,
                      let name = request["name"] as? String else {
                    return Self.encode(["ok": false, "error": "missing group/name"])
                }

                let changed = await core.patchSelector(selector: group, name: name)
                return Self.encode(["ok": changed])

            case "healthCheck":
                if let name = request["name"] as? String {
                    await core.healthCheck(name: name)
                } else {
                    await core.healthCheckAll()
                }

                return Self.encode(["ok": true])

            case "providers":
                let providers = try await core.queryProviders()
                let data = try JSONEncoder().encode(providers)

                return Self.encode([
                    "ok": true,
                    "data": (try? JSONSerialization.jsonObject(with: data)) ?? [],
                ])

            case "updateProvider":
                guard let kind = request["type"] as? String,
                      let name = request["name"] as? String,
                      let providerKind = ProviderInfo.Kind(rawValue: kind) else {
                    return Self.encode(["ok": false, "error": "invalid provider"])
                }

                try await core.updateProvider(kind: providerKind, name: name)
                return Self.encode(["ok": true])

            case "reload":
                guard let path = request["path"] as? String else {
                    return Self.encode(["ok": false, "error": "missing path"])
                }

                profilePath = path
                try await core.load(path: URL(fileURLWithPath: path))

                return Self.encode(["ok": true])

            case "override.get":
                let slot = request["session"] as? Bool == true ? OverrideSlot.session : .persist
                let content = await core.readOverride(slot)

                return Self.encode(["ok": true, "data": content])

            case "override.set", "override.clear":
                let slot = request["session"] as? Bool == true ? OverrideSlot.session : .persist
                let content = request["content"] as? String ?? "{}"

                if action == "override.clear" {
                    await core.clearOverride(slot)
                } else {
                    await core.writeOverride(slot, content: content)
                }

                return Self.encode(["ok": true])

            case "logs":
                let lines = logStore.tail()
                return Self.encode(["ok": true, "data": lines])

            case "stop":
                stopTunnel(with: .userInitiated) {}
                return Self.encode(["ok": true])

            case "suspend":
                await core.suspend(request["suspended"] as? Bool ?? false)
                return Self.encode(["ok": true])

            default:
                return Self.encode(["ok": false, "error": "unknown action \(action)"])
            }
        } catch {
            return Self.encode(["ok": false, "error": error.localizedDescription])
        }
    }

    private static func encode(_ object: Any) -> Data? {
        try? JSONSerialization.data(withJSONObject: object)
    }

    private static let privateRoutesV4: [NEIPv4Route] = [
        NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.0.0.0"),
        NEIPv4Route(destinationAddress: "172.16.0.0", subnetMask: "255.240.0.0"),
        NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0"),
        NEIPv4Route(destinationAddress: "169.254.0.0", subnetMask: "255.255.0.0"),
        NEIPv4Route(destinationAddress: "100.64.0.0", subnetMask: "255.192.0.0"),
        NEIPv4Route(destinationAddress: "127.0.0.0", subnetMask: "255.0.0.0"),
        NEIPv4Route(destinationAddress: "224.0.0.0", subnetMask: "240.0.0.0"),
    ]

    private static let privateRoutesV6: [NEIPv6Route] = [
        NEIPv6Route(destinationAddress: "fe80::", networkPrefixLength: 10),
        NEIPv6Route(destinationAddress: "fc00::", networkPrefixLength: 7),
        NEIPv6Route(destinationAddress: "ff00::", networkPrefixLength: 8),
    ]
}

final class ProviderLogStore {
    private let lock = NSLock()
    private var buffer: [[String: Any]] = []
    private let maxLines = 500

    func append(level: String, message: String) {
        lock.lock()
        defer { lock.unlock() }

        buffer.append(["level": level, "message": message, "time": Int(Date().timeIntervalSince1970 * 1000)])

        if buffer.count > maxLines {
            buffer.removeFirst(buffer.count - maxLines)
        }
    }

    func tail() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }

        let lines = Array(buffer.suffix(200))

        if let data = try? JSONSerialization.data(withJSONObject: lines),
           let text = String(data: data, encoding: .utf8) {
            ClashShared.defaults.set(text, forKey: "tunnel.logs")
        }

        return lines
    }

    func flush() {
        _ = tail()
    }
}
