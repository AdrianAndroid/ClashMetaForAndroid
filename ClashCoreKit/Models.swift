import Foundation

public struct Proxy: Codable, Identifiable, Hashable {
    public let name: String
    public let title: String
    public let subtitle: String
    public let type: String
    public let delay: Int
    public let isGroup: Bool

    public var id: String { name }

    public init(name: String, title: String, subtitle: String, type: String, delay: Int, isGroup: Bool) {
        self.name = name
        self.title = title
        self.subtitle = subtitle
        self.type = type
        self.delay = delay
        self.isGroup = isGroup
    }

    enum CodingKeys: String, CodingKey {
        case name, title, subtitle, type, delay, isGroup
    }
}

public struct ProxyGroup: Codable, Identifiable, Hashable {
    public let type: String
    public let proxies: [Proxy]
    public let now: String

    public var id: String { now }

    public init(type: String, proxies: [Proxy], now: String) {
        self.type = type
        self.proxies = proxies
        self.now = now
    }
}

public enum ProxySort: String, Codable {
    case `default` = "Default"
    case title = "Title"
    case delay = "Delay"
}

public enum TunnelMode: String, Codable {
    case direct, global, rule, script, unknown

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = TunnelMode(rawValue: value) ?? .unknown
    }
}

public struct TunnelState: Codable {
    public let mode: TunnelMode
}

public struct ProviderInfo: Codable, Identifiable, Hashable {
    public enum Kind: String, Codable {
        case proxy = "Proxy"
        case rule = "Rule"
    }

    public let name: String
    public let type: Kind
    public let vehicleType: String
    public let updatedAt: Int64

    public var id: String { "\(type.rawValue)/\(name)" }
}

public struct LogMessage: Codable, Identifiable, Hashable {
    public enum Level: String, Codable {
        case debug, info, warning, error, silent, unknown
    }

    public let level: Level
    public let message: String
    public let time: Int64

    public var id: String { "\(time)-\(message.hashValue)" }

    public init(level: Level, message: String, time: Int64) {
        self.level = level
        self.message = message
        self.time = time
    }
}

public struct FetchStatus: Codable {
    public enum Action: String, Codable {
        case fetchConfiguration = "FetchConfiguration"
        case fetchProviders = "FetchProviders"
        case subscriptionInfo = "SubscriptionInfo"
        case verifying = "Verifying"
        case unknown

        public init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer().decode(String.self)
            self = Action(rawValue: value) ?? .unknown
        }
    }

    public let action: Action
    public let args: [String]
    public let progress: Int
    public let max: Int
    public let subUpload: Int64?
    public let subDownload: Int64?
    public let subTotal: Int64?
    public let subExpire: Int64?
    public let subUpdateInterval: Int64?
}

public struct TrafficSnapshot {
    public let upload: UInt64
    public let download: UInt64

    public init(upload: UInt64, download: UInt64) {
        self.upload = upload
        self.download = download
    }
}

public struct AgeKeyPair: Codable {
    public let secretKey: String
    public let publicKey: String
}

public struct ClashCoreError: LocalizedError {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

public enum OverrideSlot: Int32 {
    case persist = 0
    case session = 1
}

public enum TunStack: String {
    case system, gvisor, mixed
}
