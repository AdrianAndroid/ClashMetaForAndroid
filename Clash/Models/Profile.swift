import ClashCoreKit
import Foundation

struct Profile: Codable, Identifiable, Hashable {
    enum Source: String, Codable {
        case url
        case file
    }

    var id: String
    var name: String
    var source: Source
    var url: String
    var updatedAt: Int64
    var updateInterval: Int64
    var upload: Int64?
    var download: Int64?
    var total: Int64?
    var expire: Int64?

    var directory: URL {
        ClashShared.profileDirectory(for: id)
    }

    var configURL: URL {
        directory.appendingPathComponent("config.yaml")
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: configURL.path)
    }

    var expireDate: Date? {
        guard let expire, expire > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(expire) / 1000)
    }

    var usedTraffic: Int64? {
        guard let upload, let download else { return nil }
        return upload + download
    }
}

struct TunnelStatus {
    var running: Bool
    var mode: String
    var upload: UInt64
    var download: UInt64
    var totalUpload: UInt64
    var totalDownload: UInt64

    static let disconnected = TunnelStatus(
        running: false,
        mode: "unknown",
        upload: 0,
        download: 0,
        totalUpload: 0,
        totalDownload: 0
    )
}
