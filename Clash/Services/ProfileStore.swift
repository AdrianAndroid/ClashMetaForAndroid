import ClashCoreKit
import Foundation

final class ProfileStore {
    private let lock = NSLock()
    private let decoder = JSONDecoder()

    func load() -> [Profile] {
        ClashShared.ensureDirectories()

        guard let data = try? Data(contentsOf: ClashShared.profileIndexURL),
              let profiles = try? decoder.decode([Profile].self, from: data) else {
            return []
        }

        return profiles
    }

    func save(_ profiles: [Profile]) {
        lock.lock()
        defer { lock.unlock() }

        ClashShared.ensureDirectories()

        guard let data = try? JSONEncoder().encode(profiles) else { return }

        try? data.write(to: ClashShared.profileIndexURL, options: .atomic)
    }

    func createDirectory(for id: String) {
        try? FileManager.default.createDirectory(
            at: ClashShared.profileDirectory(for: id).appendingPathComponent("providers"),
            withIntermediateDirectories: true
        )
    }

    func delete(_ profile: Profile) {
        try? FileManager.default.removeItem(at: profile.directory)
    }
}

final class ProfileDownloader {
    struct Result {
        var data: Data
        var upload: Int64?
        var download: Int64?
        var total: Int64?
        var expire: Int64?
        var updateInterval: Int64?
    }

    enum DownloadError: LocalizedError {
        case invalidURL
        case badStatus(Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid subscription URL"
            case .badStatus(let code):
                return "HTTP \(code)"
            }
        }
    }

    func download(url: String) async throws -> Result {
        guard let parsed = URL(string: url) else { throw DownloadError.invalidURL }

        var request = URLRequest(url: parsed)
        request.timeoutInterval = 60
        request.setValue(
            "ClashMetaForIOS/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DownloadError.badStatus(http.statusCode)
        }

        var result = Result(data: data)

        if let http = response as? HTTPURLResponse {
            if let userInfo = http.value(forHTTPHeaderField: "subscription-userinfo") {
                let parsed = Self.parseSubscriptionInfo(userInfo)
                result.upload = parsed.upload
                result.download = parsed.download
                result.total = parsed.total
                result.expire = parsed.expire
            }

            if let interval = http.value(forHTTPHeaderField: "profile-update-interval"),
               let hours = Int64(interval.trimmingCharacters(in: .whitespaces)) {
                result.updateInterval = max(hours, 0) * 3600
            }
        }

        return result
    }

    static func parseSubscriptionInfo(_ value: String) -> (upload: Int64?, download: Int64?, total: Int64?, expire: Int64?) {
        var upload: Int64?
        var download: Int64?
        var total: Int64?
        var expire: Int64?

        for pair in value.split(separator: ";") {
            let parts = pair.split(separator: "=")

            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let number = Int64(parts[1].trimmingCharacters(in: .whitespaces))

            switch key {
            case "upload": upload = number
            case "download": download = number
            case "total": total = number
            case "expire": expire = number
            default: break
            }
        }

        return (upload, download, total, expire)
    }
}
