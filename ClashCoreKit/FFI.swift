import Foundation

// Thin, non-overloaded wrappers around the generated C API.
// Keeping them separate avoids name clashes between Swift methods and C functions
// (the Go side exports names such as `reset`, `load`, `suspend`).

@inline(__always)
func resetCore() {
    reset()
}

@inline(__always)
func forceGcCore() {
    forceGc()
}

@inline(__always)
func suspendCore(_ suspended: Int32) {
    suspend(suspended)
}

@inline(__always)
func queryTunnelStateJson() -> UnsafeMutablePointer<CChar>? {
    queryTunnelState()
}

@inline(__always)
func queryNowTraffic(_ upload: UnsafeMutablePointer<UInt64>?, _ download: UnsafeMutablePointer<UInt64>?) {
    queryNow(upload, download)
}

@inline(__always)
func queryTotalTraffic(_ upload: UnsafeMutablePointer<UInt64>?, _ download: UnsafeMutablePointer<UInt64>?) {
    queryTotal(upload, download)
}

@inline(__always)
func notifyDnsChangedString(_ servers: UnsafePointer<CChar>?) {
    notifyDnsChanged(servers)
}

@inline(__always)
func notifyTimeZoneChangedString(_ name: UnsafePointer<CChar>?, _ offset: Int32) {
    notifyTimeZoneChanged(name, offset)
}

@inline(__always)
func notifyInstalledAppsChangedString(_ list: UnsafePointer<CChar>?) {
    notifyInstalledAppsChanged(list)
}

@inline(__always)
func startTunBridge(
    _ fd: Int32,
    _ stack: UnsafePointer<CChar>?,
    _ gateway: UnsafePointer<CChar>?,
    _ portal: UnsafePointer<CChar>?,
    _ dns: UnsafePointer<CChar>?,
    _ callback: UnsafeMutableRawPointer?
) -> Int32 {
    startTun(fd, stack, gateway, portal, dns, callback)
}

@inline(__always)
func stopTunBridge() {
    stopTun()
}

@inline(__always)
func startHttpBridge(_ listenAt: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    startHttp(listenAt)
}

@inline(__always)
func stopHttpBridge() {
    stopHttp()
}

@inline(__always)
func loadBridge(_ completable: UnsafeMutableRawPointer?, _ path: UnsafePointer<CChar>?) {
    load(completable, path)
}

@inline(__always)
func fetchAndValidBridge(
    _ callback: UnsafeMutableRawPointer?,
    _ path: UnsafePointer<CChar>?,
    _ url: UnsafePointer<CChar>?,
    _ force: Int32
) {
    fetchAndValid(callback, path, url, force)
}

@inline(__always)
func queryGroupNamesJson(_ excludeNotSelectable: Int32) -> UnsafeMutablePointer<CChar>? {
    queryGroupNames(excludeNotSelectable)
}

@inline(__always)
func queryGroupJson(_ name: UnsafePointer<CChar>?, _ sort: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    queryGroup(name, sort)
}

@inline(__always)
func healthCheckBridge(_ completable: UnsafeMutableRawPointer?, _ name: UnsafePointer<CChar>?) {
    healthCheck(completable, name)
}

@inline(__always)
func healthCheckAllBridge() {
    healthCheckAll()
}

@inline(__always)
func patchSelectorBridge(_ selector: UnsafePointer<CChar>?, _ name: UnsafePointer<CChar>?) -> Int32 {
    patchSelector(selector, name)
}

@inline(__always)
func queryProvidersJson() -> UnsafeMutablePointer<CChar>? {
    queryProviders()
}

@inline(__always)
func updateProviderBridge(_ completable: UnsafeMutableRawPointer?, _ type: UnsafePointer<CChar>?, _ name: UnsafePointer<CChar>?) {
    updateProvider(completable, type, name)
}

@inline(__always)
func readOverrideBridge(_ slot: Int32) -> UnsafeMutablePointer<CChar>? {
    readOverride(slot)
}

@inline(__always)
func writeOverrideBridge(_ slot: Int32, _ content: UnsafePointer<CChar>?) {
    writeOverride(slot, content)
}

@inline(__always)
func clearOverrideBridge(_ slot: Int32) {
    clearOverride(slot)
}

@inline(__always)
func subscribeLogcatBridge(_ callback: UnsafeMutableRawPointer?) {
    subscribeLogcat(callback)
}

@inline(__always)
func setAgeSecretKeyBridge(_ key: UnsafePointer<CChar>?) {
    setAgeSecretKey(key)
}

@inline(__always)
func genX25519KeyPairBridge() -> UnsafeMutablePointer<CChar>? {
    genX25519KeyPair()
}

@inline(__always)
func genHybridKeyPairBridge() -> UnsafeMutablePointer<CChar>? {
    genHybridKeyPair()
}

@inline(__always)
func verifySecretKeysBridge(_ keys: UnsafePointer<CChar>?) -> Int32 {
    veritySecretKeys(keys)
}

@inline(__always)
func toPublicKeysBridge(_ keys: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    toPublicKeys(keys)
}

@inline(__always)
func verifyPublicKeysBridge(_ keys: UnsafePointer<CChar>?) -> Int32 {
    verityPublicKeys(keys)
}

@inline(__always)
func freeCString(_ pointer: UnsafeMutablePointer<CChar>?) {
    free(pointer)
}
