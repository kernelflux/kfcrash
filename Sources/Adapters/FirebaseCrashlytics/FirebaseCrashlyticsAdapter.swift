import KFCAPI
import FirebaseCrashlytics

/// Forwards user-reported exceptions to Firebase Crashlytics.
/// Firebase must be configured via `FirebaseApp.configure()` before use.
///
/// For native crashes: Firebase Crashlytics must be initialized before kfcrash
/// so it registers its handler first. kfcrash chains to it automatically.
public struct FirebaseCrashlyticsAdapter: CrashReportSink {
    public init() {}

    public func didCapture(report: CrashReport) {
        let ex = ExceptionModel(name: report.name, reason: report.reason ?? "")
        ex.stackTrace = report.stackTrace
        Crashlytics.crashlytics().record(exceptionModel: ex)
    }
}
