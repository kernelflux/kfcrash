import Foundation

/// Crash reporting service interface — capture, persistence, report management, and user-reported exceptions.
public protocol KFCrashService: AnyObject {
    /// Whether the app crashed on the previous launch.
    var crashedLastLaunch: Bool { get }

    /// Number of app launches since the last crash.
    var launchesSinceLastCrash: Int { get }

    /// Number of sessions (launch, resume from suspend) since last crash.
    var sessionsSinceLastCrash: Int { get }

    /// Number of sessions since app launch.
    var sessionsSinceLaunch: Int { get }

    /// Total active (foreground) time elapsed since the last crash.
    var activeDurationSinceLastCrash: TimeInterval { get }

    /// Install the crash reporter with the given configuration.
    /// Once installed, the crash reporter remains active for the lifetime of the process.
    func install(config: KFCrashConfig) throws

    /// Report a custom user exception.
    /// - Parameters:
    ///   - name: The exception name (for namespacing exception types).
    ///   - reason: A description of why the exception occurred.
    ///   - language: A unique language identifier.
    ///   - stackTrace: An array of frames representing the call stack.
    ///   - terminateProgram: If true, terminate the program instead of returning.
    func reportUserException(
        name: String,
        reason: String?,
        language: String?,
        stackTrace: [String]?,
        terminateProgram: Bool
    )

    /// Report an error as a non-fatal crash report with automatic stack trace capture.
    /// - Parameters:
    ///   - error: The error to report.
    ///   - terminateProgram: If true, terminate the program after writing the report.
    func reportError(_ error: Error, terminateProgram: Bool)

    // MARK: - Report management

    /// Number of unsent crash reports on disk.
    var reportCount: Int { get }

    /// IDs of all unsent crash reports.
    var reportIDs: [String] { get }

    /// Read a crash report by ID. Returns raw JSON string.
    func report(for id: String) -> String?

    /// Write a crash report to a temporary .json file and return its URL.
    /// Use with `ShareLink(item:url)` or `UIActivityViewController` for sharing.
    func shareReportURL(for id: String) -> URL?

    /// Write all unsent crash reports to temporary .json files and return their URLs.
    /// Use for bulk packaging (zip + email, etc.).
    func allReportURLs() -> [URL]

    /// Delete a specific crash report.
    func deleteReport(_ id: String)

    /// Delete all unsent crash reports.
    func deleteAllReports()

    // MARK: - Breadcrumbs

    /// Add a breadcrumb to be included in crash reports.
    /// - Parameter message: A short message describing the event (max 255 bytes).
    func addBreadcrumb(_ message: String)

    /// Clear all breadcrumbs.
    func clearBreadcrumbs()

    // MARK: - Custom Keys

    /// Set a custom key-value pair to be included in crash reports.
    /// - Parameters:
    ///   - value: The value for the key.
    ///   - key: The key name (max 127 bytes).
    func setCustomValue(_ value: String, forKey key: String)

    /// Remove a custom key from crash reports.
    func removeCustomKey(_ key: String)

    /// Clear all custom keys.
    func clearCustomKeys()

    // MARK: - User Identifier

    /// Set a user identifier to be included in crash reports.
    /// Stored in the reportʼs ``user`` section under ``userID``.
    /// Pass nil to clear.
    func setUserIdentifier(_ identifier: String?)
}
