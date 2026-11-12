import ClashCoreKit
import Foundation
import NetworkExtension

@MainActor
final class TunnelManager {
    enum TunnelError: LocalizedError {
        case missingProfile
        case coreError(String)

        var errorDescription: String? {
            switch self {
            case .missingProfile:
                return "Profile is not installed"
            case .coreError(let message):
                return message
            }
        }
    }

    private var manager: NETunnelProviderManager?

    var providerBundleIdentifier: String {
        (Bundle.main.bundleIdentifier ?? "com.adrianandroid.clash") + ".tunnel"
    }

    var isInstalled: Bool {
        manager != nil
    }

    var isRunning: Bool {
        manager?.connection.status == .connected || manager?.connection.status == .connecting
    }

    func prepare() async throws {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()

        if let existing = managers.first(where: { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == providerBundleIdentifier }) {
            manager = existing
            return
        }

        let manager = NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = providerBundleIdentifier
        proto.serverAddress = "127.0.0.1"

        manager.protocolConfiguration = proto
        manager.localizedDescription = "Clash"
        manager.isEnabled = true

        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()

        self.manager = manager
    }

    func start(profile: Profile, settings: TunnelSettings) async throws {
        try await prepare()

        guard let manager, profile.isInstalled else { throw TunnelError.missingProfile }

        let proto = manager.protocolConfiguration as? NETunnelProviderProtocol
        proto?.providerConfiguration = [
            TunnelKeys.home: ClashShared.homeDirectory.path,
            TunnelKeys.profilePath: profile.directory.path,
            TunnelKeys.stack: settings.stack,
            TunnelKeys.ipv6: settings.ipv6,
            TunnelKeys.mtu: settings.mtu,
        ]

        manager.isEnabled = true
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()

        guard let session = manager.connection as? NETunnelProviderSession else {
            throw TunnelError.coreError("connection is not a tunnel session")
        }

        try session.startVPNTunnel(options: [:])
    }

    func stop() {
        manager?.connection.stopVPNTunnel()
    }

    func send(_ request: [String: Any]) async throws -> [String: Any] {
        guard let session = manager?.connection as? NETunnelProviderSession else {
            throw TunnelError.coreError("tunnel session is not available")
        }

        let payload = try JSONSerialization.data(withJSONObject: request)

        let response: Data? = await withCheckedContinuation { continuation in
            do {
                try session.sendProviderMessage(payload) { data in
                    continuation.resume(returning: data)
                }
            } catch {
                continuation.resume(returning: nil)
            }
        }

        guard let response,
              let object = try JSONSerialization.jsonObject(with: response) as? [String: Any] else {
            throw TunnelError.coreError("no response from tunnel")
        }

        if object["ok"] as? Bool == false {
            throw TunnelError.coreError(object["error"] as? String ?? "unknown error")
        }

        return object
    }

    func logs() async throws -> [[String: Any]] {
        let response = try await send(["action": "logs"])

        return response["data"] as? [[String: Any]] ?? []
    }
}
