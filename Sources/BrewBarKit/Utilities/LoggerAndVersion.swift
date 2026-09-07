import Foundation

public enum LogLevel: String, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
}

public struct Logger: Sendable {
    public static let shared = Logger()
    private let subsystem: String

    public init(subsystem: String = "com.dennesssy.brewbar") {
        self.subsystem = subsystem
    }

    public func log(_ message: String, level: LogLevel = .info, file: String = #file, line: Int = #line) {
        let filename = (file as NSString).lastPathComponent
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("[\(timestamp)] [\(level.rawValue)] [\(subsystem)] [\(filename):\(line)] \(message)")
    }

    public func debug(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .debug, file: file, line: line)
    }

    public func info(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .info, file: file, line: line)
    }

    public func warning(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .warning, file: file, line: line)
    }

    public func error(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .error, file: file, line: line)
    }
}

public struct VersionComparator: Sendable {
    public init() {}

    /// Compares two semver / version strings.
    /// Returns .orderedAscending if v1 < v2, .orderedDescending if v1 > v2, .orderedSame if equal.
    public static func compare(_ v1: String, _ v2: String) -> ComparisonResult {
        let parts1 = v1.components(separatedBy: CharacterSet(charactersIn: ".-_")).compactMap { Int($0) }
        let parts2 = v2.components(separatedBy: CharacterSet(charactersIn: ".-_")).compactMap { Int($0) }

        let count = max(parts1.count, parts2.count)
        for i in 0..<count {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0

            if p1 < p2 { return .orderedAscending }
            if p1 > p2 { return .orderedDescending }
        }

        return v1.compare(v2, options: .numeric)
    }

    public static func isOutdated(current: String, latest: String) -> Bool {
        return compare(current, latest) == .orderedAscending
    }
}
