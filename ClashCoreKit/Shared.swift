import Foundation

public enum ClashShared {
    /// Must match the App Group configured in both targets' entitlements.
    public static let appGroupIdentifier = "group.com.adrianandroid.clash"

    public static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return url
        }

        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Mirrors Android's `filesDir/clash`: the home directory handed to `coreInit`.
    public static var homeDirectory: URL {
        containerURL.appendingPathComponent("clash", isDirectory: true)
    }

    public static var profilesDirectory: URL {
        homeDirectory.appendingPathComponent("profiles", isDirectory: true)
    }

    public static var logsDirectory: URL {
        homeDirectory.appendingPathComponent("logs", isDirectory: true)
    }

    public static var profileIndexURL: URL {
        homeDirectory.appendingPathComponent("profiles.json")
    }

    public static func profileDirectory(for uuid: String) -> URL {
        profilesDirectory.appendingPathComponent(uuid, isDirectory: true)
    }

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    public static func ensureDirectories() {
        let manager = FileManager.default

        for url in [homeDirectory, profilesDirectory, logsDirectory] {
            try? manager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}

public struct TunnelSettings: Codable, Equatable {
    public var stack: String
    public var ipv6: Bool
    public var bypassPrivateNetwork: Bool
    public var dnsHijacking: Bool
    public var mtu: Int

    public static let `default` = TunnelSettings(
        stack: TunStack.gvisor.rawValue,
        ipv6: false,
        bypassPrivateNetwork: true,
        dnsHijacking: true,
        mtu: 9000
    )

    public init(stack: String, ipv6: Bool, bypassPrivateNetwork: Bool, dnsHijacking: Bool, mtu: Int) {
        self.stack = stack
        self.ipv6 = ipv6
        self.bypassPrivateNetwork = bypassPrivateNetwork
        self.dnsHijacking = dnsHijacking
        self.mtu = mtu
    }

    public static func load() -> TunnelSettings {
        guard let data = ClashShared.defaults.data(forKey: "tunnel.settings"),
              let settings = try? JSONDecoder().decode(TunnelSettings.self, from: data) else {
            return .default
        }

        return settings
    }

    public func save() {
        if let data = try? JSONEncoder().encode(self) {
            ClashShared.defaults.set(data, forKey: "tunnel.settings")
        }
    }
}

public enum TunnelKeys {
    public static let profilePath = "profile"
    public static let home = "home"
    public static let stack = "stack"
    public static let ipv6 = "ipv6"
    public static let bypassPrivateNetwork = "bypassPrivateNetwork"
    public static let dnsHijacking = "dnsHijacking"
    public static let mtu = "mtu"
}
