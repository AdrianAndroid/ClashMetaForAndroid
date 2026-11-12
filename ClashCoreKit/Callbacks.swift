import Foundation
import os.log

private let logger = Logger(subsystem: "com.adrianandroid.clash.core", category: "native")

public enum NativeLogLevel: Int {
    case info = 0
    case error = 1
    case warning = 2
    case debug = 3
    case verbose = 4

    init(raw: Int32) {
        switch raw {
        case 1: self = .error
        case 2: self = .warning
        case 3: self = .debug
        case 4: self = .verbose
        default: self = .info
        }
    }
}

public struct NativeLogLine {
    public let level: NativeLogLevel
    public let message: String
}

public final class CompletionBox {
    let handler: (String?) -> Void

    init(handler: @escaping (String?) -> Void) {
        self.handler = handler
    }
}

public final class FetchBox {
    let onReport: (String) -> Void
    let onComplete: (String?) -> Void

    init(onReport: @escaping (String) -> Void, onComplete: @escaping (String?) -> Void) {
        self.onReport = onReport
        self.onComplete = onComplete
    }
}

public final class LogcatBox {
    let onMessage: (String) -> Bool

    init(onMessage: @escaping (String) -> Bool) {
        self.onMessage = onMessage
    }
}

public final class ObjectRegistry {
    public static let shared = ObjectRegistry()

    private let lock = NSLock()
    private var retained: [UInt: AnyObject] = [:]
    private var nextToken: UInt = 1

    private init() {}

    public func retain(_ object: AnyObject) -> UnsafeMutableRawPointer {
        lock.lock()
        defer { lock.unlock() }

        let token = nextToken
        nextToken += 1

        retained[token] = object

        return UnsafeMutableRawPointer(bitPattern: token)!
    }

    public func release(_ pointer: UnsafeMutableRawPointer?) {
        guard let pointer else { return }

        lock.lock()
        defer { lock.unlock() }

        retained.removeValue(forKey: UInt(bitPattern: pointer))
    }

    public func object<T>(_ pointer: UnsafeMutableRawPointer?, as type: T.Type) -> T? {
        guard let pointer else { return nil }

        lock.lock()
        defer { lock.unlock() }

        return retained[UInt(bitPattern: pointer)] as? T
    }
}

public enum CallbackBridge {
    private static let installLock = NSLock()
    private static var installed = false

    public static var logHandler: ((NativeLogLine) -> Void)? {
        didSet {
            install()
        }
    }

    public static func install() {
        installLock.lock()
        defer { installLock.unlock() }

        guard !installed else { return }
        installed = true

        var callbacks = clash_callbacks()
        callbacks.log = clashLogCallback
        callbacks.mark_socket = clashMarkSocketCallback
        callbacks.query_socket_uid = clashQuerySocketUidCallback
        callbacks.complete = clashCompleteCallback
        callbacks.fetch_report = clashFetchReportCallback
        callbacks.fetch_complete = clashFetchCompleteCallback
        callbacks.logcat_received = clashLogcatReceivedCallback
        callbacks.open_content = nil
        callbacks.release_object = clashReleaseObjectCallback

        coreRegisterCallbacks(&callbacks)
    }
}

private func clashLogCallback(_ level: Int32, _ message: UnsafePointer<CChar>?) {
    let text = message.map { String(cString: $0) } ?? ""

    logger.log(level: OSLogType.default, "\(text, privacy: .public)")

    CallbackBridge.logHandler?(NativeLogLine(level: NativeLogLevel(raw: level), message: text))
}

private func clashMarkSocketCallback(_ context: UnsafeMutableRawPointer?, _ fd: Int32) {
    guard let box = ObjectRegistry.shared.object(context, as: TunCallbackBox.self) else { return }

    box.markSocket(fd)
}

private func clashQuerySocketUidCallback(
    _ context: UnsafeMutableRawPointer?,
    _ protocol: Int32,
    _ source: UnsafePointer<CChar>?,
    _ target: UnsafePointer<CChar>?
) -> Int32 {
    guard let box = ObjectRegistry.shared.object(context, as: TunCallbackBox.self) else { return -1 }

    return box.queryUid(
        `protocol`,
        source.map { String(cString: $0) } ?? "",
        target.map { String(cString: $0) } ?? ""
    )
}

private func clashCompleteCallback(_ context: UnsafeMutableRawPointer?, _ error: UnsafePointer<CChar>?) {
    guard let box = ObjectRegistry.shared.object(context, as: CompletionBox.self) else { return }

    box.handler(error.map { String(cString: $0) })
}

private func clashFetchReportCallback(_ context: UnsafeMutableRawPointer?, _ status: UnsafePointer<CChar>?) {
    guard let box = ObjectRegistry.shared.object(context, as: FetchBox.self) else { return }

    box.onReport(status.map { String(cString: $0) } ?? "{}")
}

private func clashFetchCompleteCallback(_ context: UnsafeMutableRawPointer?, _ error: UnsafePointer<CChar>?) {
    guard let box = ObjectRegistry.shared.object(context, as: FetchBox.self) else { return }

    box.onComplete(error.map { String(cString: $0) })
}

private func clashLogcatReceivedCallback(_ context: UnsafeMutableRawPointer?, _ payload: UnsafePointer<CChar>?) -> Int32 {
    guard let box = ObjectRegistry.shared.object(context, as: LogcatBox.self) else { return 1 }

    let keepGoing = box.onMessage(payload.map { String(cString: $0) } ?? "{}")

    return keepGoing ? 0 : 1
}

private func clashReleaseObjectCallback(_ context: UnsafeMutableRawPointer?) {
    ObjectRegistry.shared.release(context)
}

public final class SocketProtectorCallbackBox {
    let handler: (Int32) -> Void

    init(handler: @escaping (Int32) -> Void) {
        self.handler = handler
    }
}

public final class UidQueryCallbackBox {
    let handler: (Int32, String, String) -> Int32

    init(handler: @escaping (Int32, String, String) -> Int32) {
        self.handler = handler
    }
}
