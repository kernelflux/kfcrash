import Foundation
import KFCrash
import KFCAPI

/// Default crash reporting implementation — bridges the ObjC KFCrash engine.
final class DefaultKFCrashService: KFCrashService {
    private var engine: KFCrash { KFCrash.shared }
    private var reportStore: CrashReportStore { engine.reportStore! }
    private var privacyRedactFields: [String] = []

    var crashedLastLaunch: Bool {
        engine.crashedLastLaunch
    }

    var launchesSinceLastCrash: Int { engine.launchesSinceLastCrash }

    var sessionsSinceLastCrash: Int { engine.sessionsSinceLastCrash }

    var sessionsSinceLaunch: Int { engine.sessionsSinceLaunch }

    var activeDurationSinceLastCrash: TimeInterval { engine.activeDurationSinceLastCrash }

    func install(config: KFCrashConfig) throws {
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

    func reportUserException(
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
    }

    func reportError(_ error: Error, terminateProgram: Bool) {
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

    var reportCount: Int { reportStore.reportCount }

    var reportIDs: [String] {
        reportStore.reportIDs.map { $0.stringValue }
    }

    func report(for id: String) -> String? {
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

    func shareReportURL(for id: String) -> URL? {
        guard let json = report(for: id) else { return nil }
        return writeTempReport(json: json, name: "crash_report_\(id).json")
    }

    func allReportURLs() -> [URL] {
        reportIDs.compactMap { shareReportURL(for: $0) }
    }

    func deleteReport(_ id: String) {
        guard let reportID = Int64(id) else { return }
        reportStore.deleteReport(with: reportID)
    }

    func deleteAllReports() {
        reportStore.deleteAllReports()
    }

    // MARK: - Breadcrumbs

    func addBreadcrumb(_ message: String) {
        engine.addBreadcrumb(message)
    }

    func clearBreadcrumbs() {
        engine.clearBreadcrumbs()
    }

    // MARK: - Custom Keys

    func setCustomValue(_ value: String, forKey key: String) {
        engine.setCustomValue(value, forKey: key)
    }

    func removeCustomKey(_ key: String) {
        engine.removeCustomKey(key)
    }

    func clearCustomKeys() {
        engine.clearCustomKeys()
    }

    // MARK: - User Identifier

    func setUserIdentifier(_ identifier: String?) {
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
