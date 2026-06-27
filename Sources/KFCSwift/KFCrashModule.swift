import KFCAPI
import KFService

/// KFCrash module — provides DAG startup hook after registration.
///
/// Host registers KFCrashService in init():
///     ServiceFactory.register((any KFCrashService).self) { DefaultKFCrashService() }
///
/// Engine calls performInit() after dependencies are ready.
public final class KFCrashModule: ModuleProtocol {
    public static var dependencies: [ModuleID] { [] }
    public init() {}

    public func performInit() async {
        // Any async setup after crash service is registered.
    }
}
