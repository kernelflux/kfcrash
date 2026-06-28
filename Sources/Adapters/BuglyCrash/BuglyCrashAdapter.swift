import KFCAPI
import Bugly

/// Forwards user-reported exceptions to Bugly and handles SDK initialization.
///
/// Initialize **before** kfcrash so Bugly registers its crash handler first —
/// kfcrash will chain to it for native crashes.
public struct BuglyCrashAdapter: CrashReportSink {

    /// - Parameters:
    ///   - appId: Bugly 后台分配的 AppId
    ///   - channel: 渠道标记，默认 nil
    ///   - debug: 是否开启调试模式，默认 false
    public init(appId: String, channel: String? = nil, debug: Bool = false) {
        let config = BuglyConfig()
        config.channel = channel
        config.debugMode = debug
        Bugly.start(withAppId: appId, config: config)
    }

    public func didCapture(report: CrashReport) {
        Bugly.reportException(
            withCategory: 4,
            name: report.name,
            reason: report.reason ?? "",
            callStack: report.stackTrace,
            extraInfo: [:],
            terminateApp: false
        )
    }
}
