import Foundation

/// A crash report captured by kfcrash, ready for forwarding to a third-party SDK.
public struct CrashReport: Sendable {
    public let reportID: String
    public let name: String
    public let reason: String?
    public let language: String?
    public let stackTrace: [String]
    public let timestamp: Date

    public init(
        reportID: String,
        name: String,
        reason: String? = nil,
        language: String? = nil,
        stackTrace: [String] = [],
        timestamp: Date = Date()
    ) {
        self.reportID = reportID
        self.name = name
        self.reason = reason
        self.language = language
        self.stackTrace = stackTrace
        self.timestamp = timestamp
    }
}

/// Receives crash reports after kfcrash has written them to disk.
/// Adapters implement this protocol to forward reports to third-party crash SDKs.
public protocol CrashReportSink: Sendable {
    func didCapture(report: CrashReport)
}

public struct NoOpCrashReportSink: CrashReportSink {
    public func didCapture(report: CrashReport) {}
    public init() {}
}
