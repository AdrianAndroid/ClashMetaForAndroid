import Foundation

public final class TunCallbackBox {
    public let markSocket: (Int32) -> Void
    public let queryUid: (Int32, String, String) -> Int32

    public init(markSocket: @escaping (Int32) -> Void, queryUid: @escaping (Int32, String, String) -> Int32) {
        self.markSocket = markSocket
        self.queryUid = queryUid
    }
}

/// Swift facade of the Go core. Mirrors `core/Clash.kt` of ClashMetaForAndroid one to one.
public actor ClashCore {
    public static let shared = ClashCore()

    private var initialized = false
    private var logcatTokens: [Int: UnsafeMutableRawPointer] = [:]
    private let decoder = JSONDecoder()

    public init() {}

    public func initialize(home: URL, versionName: String, gitVersion: String, platformVersion: Int32 = 34) {
        CallbackBridge.install()

        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        home.path.withCString { homePtr in
            versionName.withCString { versionPtr in
                gitVersion.withCString { gitPtr in
                    coreInit(homePtr, versionPtr, gitPtr, platformVersion)
                }
            }
        }

        initialized = true
    }

    public var isInitialized: Bool { initialized }

    public func reset() {
        resetCore()
    }

    public func forceGc() {
        forceGcCore()
    }

    public func suspend(_ suspended: Bool) {
        suspendCore(suspended ? 1 : 0)
    }

    public func queryTunnelState() throws -> TunnelState {
        guard let raw = queryTunnelStateJson() else {
            throw ClashCoreError("queryTunnelState returned nil")
        }

        defer { freeCString(raw) }

        return try decoder.decode(TunnelState.self, from: Data(bytes: raw, count: strlen(raw)))
    }

    public func trafficNow() -> TrafficSnapshot {
        var upload: UInt64 = 0
        var download: UInt64 = 0

        queryNowTraffic(&upload, &download)

        return TrafficSnapshot(upload: upload, download: download)
    }

    public func trafficTotal() -> TrafficSnapshot {
        var upload: UInt64 = 0
        var download: UInt64 = 0

        queryTotalTraffic(&upload, &download)

        return TrafficSnapshot(upload: upload, download: download)
    }

    public func notifyDnsChanged(_ servers: [String]) {
        servers.joined(separator: ",").withCString { notifyDnsChangedString($0) }
    }

    public func notifyTimeZoneChanged(name: String, offset: Int32) {
        name.withCString { notifyTimeZoneChangedString($0, offset) }
    }

    public func notifyInstalledAppsChanged(_ uids: [(Int32, String)]) {
        let list = uids.map { "\($0.0):\($0.1)" }.joined(separator: ",")
        list.withCString { notifyInstalledAppsChangedString($0) }
    }

    public func startTun(
        fd: Int32,
        stack: String,
        gateway: String,
        portal: String,
        dns: String,
        markSocket: @escaping (Int32) -> Void,
        queryUid: @escaping (Int32, String, String) -> Int32
    ) throws {
        let box = TunCallbackBox(markSocket: markSocket, queryUid: queryUid)
        let token = ObjectRegistry.shared.retain(box)

        let result: Int32 = stack.withCString { stackPtr in
            gateway.withCString { gatewayPtr in
                portal.withCString { portalPtr in
                    dns.withCString { dnsPtr in
                        startTunBridge(fd, stackPtr, gatewayPtr, portalPtr, dnsPtr, token)
                    }
                }
            }
        }

        if result != 0 {
            ObjectRegistry.shared.release(token)
            throw ClashCoreError("startTun failed")
        }
    }

    public func stopTun() {
        stopTunBridge()
    }

    public func startHttp(listenAt: String) throws -> String {
        let result = listenAt.withCString { startHttpBridge($0) }

        guard let result else {
            throw ClashCoreError("startHttp failed")
        }

        defer { freeCString(result) }

        return String(cString: result)
    }

    public func stopHttp() {
        stopHttpBridge()
    }

    public func load(path: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let box = CompletionBox { error in
                if let error, !error.isEmpty {
                    continuation.resume(throwing: ClashCoreError(error))
                } else {
                    continuation.resume()
                }
            }

            let token = ObjectRegistry.shared.retain(box)

            path.path.withCString { loadBridge(token, $0) }
        }
    }

    public func fetchAndValid(
        path: URL,
        url: String,
        force: Bool,
        onStatus: @escaping (FetchStatus) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let box = FetchBox { json in
                guard let status = try? self.decoder.decode(FetchStatus.self, from: Data(json.utf8)) else {
                    return
                }

                onStatus(status)
            } onComplete: { error in
                if let error, !error.isEmpty {
                    continuation.resume(throwing: ClashCoreError(error))
                } else {
                    continuation.resume()
                }
            }

            let token = ObjectRegistry.shared.retain(box)

            path.path.withCString { pathPtr in
                url.withCString { urlPtr in
                    fetchAndValidBridge(token, pathPtr, urlPtr, force ? 1 : 0)
                }
            }
        }
    }

    public func queryGroupNames(excludeNotSelectable: Bool = false) throws -> [String] {
        guard let raw = queryGroupNamesJson(excludeNotSelectable ? 1 : 0) else {
            throw ClashCoreError("queryGroupNames returned nil")
        }

        defer { freeCString(raw) }

        return try decoder.decode([String].self, from: Data(bytes: raw, count: strlen(raw)))
    }

    public func queryGroup(name: String, sort: ProxySort = .default) throws -> ProxyGroup {
        let raw = name.withCString { namePtr in
            sort.rawValue.withCString { sortPtr in
                queryGroupJson(namePtr, sortPtr)
            }
        }

        guard let raw else {
            return ProxyGroup(type: "Unknown", proxies: [], now: "")
        }

        defer { freeCString(raw) }

        return try decoder.decode(ProxyGroup.self, from: Data(bytes: raw, count: strlen(raw)))
    }

    public func healthCheck(name: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let box = CompletionBox { _ in
                continuation.resume()
            }

            let token = ObjectRegistry.shared.retain(box)

            name.withCString { healthCheckBridge(token, $0) }
        }
    }

    public func healthCheckAll() {
        healthCheckAllBridge()
    }

    public func patchSelector(selector: String, name: String) -> Bool {
        let result = selector.withCString { selectorPtr in
            name.withCString { namePtr in
                patchSelectorBridge(selectorPtr, namePtr)
            }
        }

        return result == 1
    }

    public func queryProviders() throws -> [ProviderInfo] {
        guard let raw = queryProvidersJson() else {
            throw ClashCoreError("queryProviders returned nil")
        }

        defer { freeCString(raw) }

        return try decoder.decode([ProviderInfo].self, from: Data(bytes: raw, count: strlen(raw)))
    }

    public func updateProvider(kind: ProviderInfo.Kind, name: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let box = CompletionBox { error in
                if let error, !error.isEmpty {
                    continuation.resume(throwing: ClashCoreError(error))
                } else {
                    continuation.resume()
                }
            }

            let token = ObjectRegistry.shared.retain(box)

            kind.rawValue.withCString { kindPtr in
                name.withCString { namePtr in
                    updateProviderBridge(token, kindPtr, namePtr)
                }
            }
        }
    }

    public func readOverride(_ slot: OverrideSlot) -> String {
        guard let raw = readOverrideBridge(slot.rawValue) else { return "{}" }

        defer { freeCString(raw) }

        return String(cString: raw)
    }

    public func writeOverride(_ slot: OverrideSlot, content: String) {
        content.withCString { writeOverrideBridge(slot.rawValue, $0) }
    }

    public func clearOverride(_ slot: OverrideSlot) {
        clearOverrideBridge(slot.rawValue)
    }

    @discardableResult
    public func subscribeLogcat(_ handler: @escaping (LogMessage) -> Bool) -> Int {
        let key = Int(Date().timeIntervalSince1970 * 1000) ^ Int.random(in: 0..<1000)
        let box = LogcatBox { json in
            guard let data = json.data(using: .utf8),
                  let message = try? JSONDecoder().decode(LogMessage.self, from: data) else {
                return true
            }

            return handler(message)
        }

        let token = ObjectRegistry.shared.retain(box)
        logcatTokens[key] = token

        subscribeLogcatBridge(token)

        return key
    }

    public func unsubscribeLogcat(_ key: Int) {
        logcatTokens.removeValue(forKey: key)
    }

    public func setAgeSecretKey(_ key: String?) {
        if let key {
            key.withCString { setAgeSecretKeyBridge($0) }
        } else {
            setAgeSecretKeyBridge(nil)
        }
    }

    public func genX25519KeyPair() -> AgeKeyPair? {
        decodeAgeKeyPair(genX25519KeyPairBridge())
    }

    public func genHybridKeyPair() -> AgeKeyPair? {
        decodeAgeKeyPair(genHybridKeyPairBridge())
    }

    public func verifySecretKeys(_ keys: String) -> Bool {
        keys.withCString { verifySecretKeysBridge($0) == 1 }
    }

    public func toPublicKeys(_ keys: String) -> [String] {
        guard let raw = keys.withCString({ toPublicKeysBridge($0) }) else { return [] }

        defer { freeCString(raw) }

        return (try? decoder.decode([String].self, from: Data(bytes: raw, count: strlen(raw)))) ?? []
    }

    public func verifyPublicKeys(_ keys: String) -> Bool {
        keys.withCString { verifyPublicKeysBridge($0) == 1 }
    }

    private func decodeAgeKeyPair(_ raw: UnsafeMutablePointer<CChar>?) -> AgeKeyPair? {
        guard let raw else { return nil }

        defer { freeCString(raw) }

        return try? decoder.decode(AgeKeyPair.self, from: Data(bytes: raw, count: strlen(raw)))
    }
}
