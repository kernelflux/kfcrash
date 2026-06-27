import Foundation

/// Crash monitor types that can be enabled.
public struct CrashMonitorTypes: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let machException      = CrashMonitorTypes(rawValue: 1 << 0)
    public static let signal             = CrashMonitorTypes(rawValue: 1 << 1)
    public static let cppException       = CrashMonitorTypes(rawValue: 1 << 2)
    public static let nsException        = CrashMonitorTypes(rawValue: 1 << 3)
    public static let mainThreadDeadlock = CrashMonitorTypes(rawValue: 1 << 4)
    public static let userReported       = CrashMonitorTypes(rawValue: 1 << 5)
    public static let system             = CrashMonitorTypes(rawValue: 1 << 6)
    public static let applicationState   = CrashMonitorTypes(rawValue: 1 << 7)
    public static let zombie             = CrashMonitorTypes(rawValue: 1 << 8)
    public static let memoryTermination  = CrashMonitorTypes(rawValue: 1 << 9)

    /// Fatal crash monitors: Mach exception, signal, C++ exception, NSException.
    public static let fatal: CrashMonitorTypes = [
        .machException, .signal, .cppException, .nsException
    ]

    /// Production-safe minimal set: Mach exception + signal.
    public static let productionSafeMinimal: CrashMonitorTypes = [
        .machException, .signal
    ]

    /// All available monitor types.
    public static let all: CrashMonitorTypes = [
        .fatal, .mainThreadDeadlock, .userReported, .system,
        .applicationState, .zombie, .memoryTermination
    ]
}

/// User-facing configuration for crash reporting.
public struct KFCrashConfig {
    /// Which crash monitor types to enable. Default: `.productionSafeMinimal`.
    public var monitorTypes: CrashMonitorTypes

    /// Maximum number of crash reports to keep on disk. Default: 5.
    public var maxReportCount: Int

    /// Custom install path. nil uses the default cache directory.
    public var installPath: String?

    /// User-supplied info included in every crash report. Must be JSON-safe.
    public var userInfo: [String: Any]?

    /// Main thread deadlock watchdog interval in seconds. 0 disables. Default: 0.
    public var deadlockWatchdogInterval: TimeInterval

    /// If true, include recent KFLog output in crash reports. Default: false.
    public var addConsoleLogToReport: Bool

    /// If true, monitor SIGTERM (can produce false positives). Default: false.
    public var enableSigTermMonitoring: Bool

    /// If true, attempt to fetch dispatch queue names for each thread. Default: false.
    public var enableQueueNameSearch: Bool

    /// If true, introspect memory near the crash point. Default: false.
    public var enableMemoryIntrospection: Bool

    /// Objective-C classes excluded from memory introspection.
    public var doNotIntrospectClasses: [String]?

    /// If true, forward unhandled exceptions to crash handlers installed before
    /// KFCrash (e.g. Bugly, Firebase Crashlytics). Default: true.
    ///
    /// When enabled, KFCrash acts as the primary handler, writes its own report,
    /// then chains the exception to the previous handler. Install third-party
    /// SDKs first, then install KFCrash last to ensure correct ordering.
    public var chainToExistingHandlers: Bool

    /// Report fields to redact for privacy compliance. Fields are stripped
    /// from reports when read via `report(for:)` or `shareReportURL(for:)`.
    /// Supports dot-notation for nested paths (e.g. `system.processPath`).
    public var privacyRedactFields: [String]

    public init(
        monitorTypes: CrashMonitorTypes = .productionSafeMinimal,
        maxReportCount: Int = 5,
        installPath: String? = nil,
        userInfo: [String: Any]? = nil,
        deadlockWatchdogInterval: TimeInterval = 0,
        addConsoleLogToReport: Bool = false,
        enableSigTermMonitoring: Bool = false,
        enableQueueNameSearch: Bool = false,
        enableMemoryIntrospection: Bool = false,
        doNotIntrospectClasses: [String]? = nil,
        chainToExistingHandlers: Bool = true,
        privacyRedactFields: [String] = []
    ) {
        self.monitorTypes = monitorTypes
        self.maxReportCount = maxReportCount
        self.installPath = installPath
        self.userInfo = userInfo
        self.deadlockWatchdogInterval = deadlockWatchdogInterval
        self.addConsoleLogToReport = addConsoleLogToReport
        self.enableSigTermMonitoring = enableSigTermMonitoring
        self.enableQueueNameSearch = enableQueueNameSearch
        self.enableMemoryIntrospection = enableMemoryIntrospection
        self.doNotIntrospectClasses = doNotIntrospectClasses
        self.chainToExistingHandlers = chainToExistingHandlers
        self.privacyRedactFields = privacyRedactFields
    }
}
