import Foundation
import KFCrash
import KFCAPI

/// Default crash reporting implementation — bridges the ObjC KFCrash engine.
public final class DefaultKFCrashService: KFCrashService {
    private var engine: KFCrash { KFCrash.shared }
    private var reportStore: CrashReportStore { engine.reportStore! }
    private var privacyRedactFields: [String] = []
    private var config: KFCrashConfig?

    public var crashedLastLaunch: Bool {
        engine.crashedLastLaunch
    }

    public var launchesSinceLastCrash: Int { engine.launchesSinceLastCrash }

    public var sessionsSinceLastCrash: Int { engine.sessionsSinceLastCrash }

    public var sessionsSinceLaunch: Int { engine.sessionsSinceLaunch }

    public var activeDurationSinceLastCrash: TimeInterval { engine.activeDurationSinceLastCrash }

    public init() {}

    public func initialize(config: KFCrashConfig) throws {
        self.config = config
        privacyRedactFields = config.privacyRedactFields

        let objcConfig = KFCrashConfiguration()

        objcConfig.setValue(NSNumber(value: config.monitorTypes.rawValue), forKey: "monitors")
        objcConfig.reportStoreConfiguration.maxReportCount = config.maxReportCount
        if let path = config.installPath { objcConfig.installPath = path }
        if let userInfo = config.userInfo { objcConfig.userInfoJSON = userInfo }
        objcConfig.deadlockWatchdogInterval = config.deadlockWatchdogInterval
        objcConfig.addConsoleLogToReport = config.addConsoleLogToReport
        objcConfig.enableSigTermMonitoring = config.enableSigTermMonitoring
        objcConfig.enableQueueNameSearch = config.enableQueueNameSearch
        objcConfig.enableMemoryIntrospection = config.enableMemoryIntrospection
        if let classes = config.doNotIntrospectClasses { objcConfig.doNotIntrospectClasses = classes }

        try engine.install(with: objcConfig)
    }

    public func reportUserException(
        name: String,
        reason: String?,
        language: String?,
        stackTrace: [String]?,
        terminateProgram: Bool
    ) {
        engine.reportUserException(
            name,
            reason: reason,
            language: language,
            lineOfCode: nil as String?,
            stackTrace: stackTrace,
            logAllThreads: true,
            terminateProgram: terminateProgram
        )

        if let sink = config?.sink {
            let report = CrashReport(
                reportID: UUID().uuidString,
                name: name,
                reason: reason,
                language: language,
                stackTrace: stackTrace ?? [],
                timestamp: Date()
            )
            sink.didCapture(report: report)
        }
    }

    public func reportError(_ error: Error, terminateProgram: Bool) {
        let nsError = error as NSError
        let name = "\(nsError.domain).\(nsError.code)"
        reportUserException(
            name: name,
            reason: error.localizedDescription,
            language: "Swift.Error",
            stackTrace: Thread.callStackSymbols,
            terminateProgram: terminateProgram
        )
    }

    // MARK: - Report management

    public var reportCount: Int { reportStore.reportCount }

    public var reportIDs: [String] {
        reportStore.reportIDs.map { $0.stringValue }
    }

    public func report(for id: String) -> String? {
        guard let reportID = Int64(id),
              var json = reportStore.reportString(for: reportID) else { return nil }
        if !privacyRedactFields.isEmpty, let data = json.data(using: .utf8),
           var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for field in privacyRedactFields {
                Self.redactKeyPath(&dict, field)
            }
            if let cleanData = try? JSONSerialization.data(withJSONObject: dict),
               let cleanJSON = String(data: cleanData, encoding: .utf8) {
                json = cleanJSON
            }
        }
        return json
    }

    public func shareReportURL(for id: String) -> URL? {
        guard let json = report(for: id) else { return nil }
        return writeTempReport(json: json, name: "crash_report_\(id).json")
    }

    public func allReportURLs() -> [URL] {
        reportIDs.compactMap { shareReportURL(for: $0) }
    }

    public func deleteReport(_ id: String) {
        guard let reportID = Int64(id) else { return }
        reportStore.deleteReport(with: reportID)
    }

    public func deleteAllReports() {
        reportStore.deleteAllReports()
    }

    // MARK: - Breadcrumbs

    public func addBreadcrumb(_ message: String) {
        engine.addBreadcrumb(message)
    }

    public func clearBreadcrumbs() {
        engine.clearBreadcrumbs()
    }

    // MARK: - Custom Keys

    public func setCustomValue(_ value: String, forKey key: String) {
        engine.setCustomValue(value, forKey: key)
    }

    public func removeCustomKey(_ key: String) {
        engine.removeCustomKey(key)
    }

    public func clearCustomKeys() {
        engine.clearCustomKeys()
    }

    public func unInit() {
        // Crash handlers stay installed for the process lifetime.
    }

    // MARK: - User Identifier

    public func setUserIdentifier(_ identifier: String?) {
        engine.setUserIdentifier(identifier)
    }

    private func writeTempReport(json: String, name: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("KFCrashReports", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent(name)
        do {
            try json.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }

    /// Recursively remove a dot-separated key path from the dictionary.
    private static func redactKeyPath(_ dict: inout [String: Any], _ path: String) {
        let components = path.components(separatedBy: ".")
        guard let first = components.first else { return }
        if components.count == 1 {
            dict.removeValue(forKey: first)
        } else if var nested = dict[first] as? [String: Any] {
            redactKeyPath(&nested, components.dropFirst().joined(separator: "."))
            dict[first] = nested
        }
    }
}
