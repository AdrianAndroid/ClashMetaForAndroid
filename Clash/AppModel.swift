import ClashCoreKit
import Foundation
import SwiftUI

struct LogLine: Identifiable, Hashable {
    let id = UUID()
    let level: String
    let message: String
    let time: Int64
}

@MainActor
final class AppModel: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var activeProfileID: String?
    @Published var running = false
    @Published var status = TunnelStatus.disconnected
    @Published var groupNames: [String] = []
    @Published var groups: [String: ProxyGroup] = [:]
    @Published var logs: [LogLine] = []
    @Published var settings = TunnelSettings.load()
    @Published var busy = false
    @Published var errorMessage: String?

    let tunnel = TunnelManager()
    private let store = ProfileStore()
    private var pollTask: Task<Void, Never>?

    var activeProfile: Profile? {
        profiles.first { $0.id == activeProfileID }
    }

    init() {
        ClashShared.ensureDirectories()
        profiles = store.load()
        activeProfileID = ClashShared.defaults.string(forKey: "active.profile") ?? profiles.first?.id
        running = tunnel.isRunning

        Task {
            await refreshTunnelStatus()
        }
    }

    /// True when running inside the simulator, where NetworkExtension is not available.
    var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    func bootstrap() async {
        // NetworkExtension is unavailable in the simulator, so a failure here is
        // expected and must not be presented to the user.
        try? await tunnel.prepare()

        running = tunnel.isRunning

        if running {
            startPolling()
        }
    }

    func importProfile(url: String, name: String) async {
        busy = true
        defer { busy = false }

        let id = UUID().uuidString

        do {
            let downloader = ProfileDownloader()
            let result = try await downloader.download(url: url)

            store.createDirectory(for: id)

            let profile = Profile(
                id: id,
                name: name.isEmpty ? (URL(string: url)?.host ?? "Profile") : name,
                source: .url,
                url: url,
                updatedAt: Int64(Date().timeIntervalSince1970 * 1000),
                updateInterval: result.updateInterval ?? 24 * 3600,
                upload: result.upload,
                download: result.download,
                total: result.total,
                expire: result.expire
            )

            try FileManager.default.createDirectory(at: profile.directory, withIntermediateDirectories: true)
            try result.data.write(to: profile.configURL, options: .atomic)

            profiles.append(profile)
            store.save(profiles)

            if activeProfileID == nil {
                setActive(profile.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateProfile(_ profile: Profile) async {
        busy = true
        defer { busy = false }

        do {
            let downloader = ProfileDownloader()
            let result = try await downloader.download(url: profile.url)

            try FileManager.default.createDirectory(at: profile.directory, withIntermediateDirectories: true)
            try result.data.write(to: profile.configURL, options: .atomic)

            var updated = profile
            updated.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
            updated.upload = result.upload
            updated.download = result.download
            updated.total = result.total
            updated.expire = result.expire

            replace(updated)

            if running, profile.id == activeProfileID {
                _ = try? await tunnel.send([
                    "action": "reload",
                    "path": updated.directory.path,
                ])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ profile: Profile) {
        store.delete(profile)
        profiles.removeAll { $0.id == profile.id }
        store.save(profiles)

        if activeProfileID == profile.id {
            activeProfileID = profiles.first?.id
            ClashShared.defaults.set(activeProfileID, forKey: "active.profile")
        }
    }

    func setActive(_ id: String) {
        activeProfileID = id
        ClashShared.defaults.set(id, forKey: "active.profile")
    }

    func startTunnel() async {
        if isSimulator {
            errorMessage = "The Network Extension cannot run in the simulator. Use a real device."
            return
        }

        guard let profile = activeProfile else {
            errorMessage = "Select a profile first"
            return
        }

        busy = true
        defer { busy = false }

        do {
            try await tunnel.start(profile: profile, settings: settings)
            running = true
            startPolling()
        } catch {
            errorMessage = error.localizedDescription
            running = false
        }
    }

    func stopTunnel() {
        tunnel.stop()
        running = false
        status = .disconnected
        stopPolling()
    }

    func refreshGroups() async {
        guard running else { return }

        do {
            let response = try await tunnel.send(["action": "groups"])
            groupNames = response["data"] as? [String] ?? []

            for name in groupNames {
                await refreshGroup(name)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshGroup(_ name: String) async {
        do {
            let response = try await tunnel.send(["action": "group", "name": name])

            guard let data = response["data"],
                  let encoded = try? JSONSerialization.data(withJSONObject: data),
                  let group = try? JSONDecoder().decode(ProxyGroup.self, from: encoded) else {
                return
            }

            groups[name] = group
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(group: String, proxy: String) async {
        do {
            _ = try await tunnel.send([
                "action": "select",
                "group": group,
                "name": proxy,
            ])

            await refreshGroup(group)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func healthCheck(group: String) async {
        _ = try? await tunnel.send(["action": "healthCheck", "name": group])
        await refreshGroup(group)
    }

    func refreshLogs() async {
        do {
            let lines = try await tunnel.logs()
            logs = lines.compactMap { line in
                guard let level = line["level"] as? String,
                      let message = line["message"] as? String else {
                    return nil
                }

                return LogLine(level: level, message: message, time: line["time"] as? Int64 ?? 0)
            }
        } catch {
            // tunnel may be stopped
        }
    }

    func saveSettings() {
        settings.save()
    }

    func refreshTunnelStatus() async {
        running = tunnel.isRunning

        if let text = ClashShared.defaults.string(forKey: "tunnel.status"),
           let data = text.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            status = TunnelStatus(
                running: object["running"] as? Bool ?? false,
                mode: object["mode"] as? String ?? "unknown",
                upload: UInt64(object["up"] as? Int64 ?? 0),
                download: UInt64(object["down"] as? Int64 ?? 0),
                totalUpload: UInt64(object["totalUp"] as? Int64 ?? 0),
                totalDownload: UInt64(object["totalDown"] as? Int64 ?? 0)
            )
        } else if !running {
            status = .disconnected
        }
    }

    func startPolling() {
        stopPolling()

        pollTask = Task {
            while !Task.isCancelled {
                await refreshTunnelStatus()

                if running {
                    await refreshLogs()
                }

                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func replace(_ profile: Profile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }

        profiles[index] = profile
        store.save(profiles)
    }
}
