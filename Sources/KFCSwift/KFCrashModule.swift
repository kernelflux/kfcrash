import KFCAPI
import KFService
@_exported import KFCAPI

/// KFCrash service module — registers the default crash reporter with ServiceFactory.
///
///     KFCrashModule(config: ...).start()
///     ServiceFactory.resolve((any KFCrashService).self).crashedLastLaunch
public struct KFCrashModule {
    private let config: KFCrashConfig

    public init(config: KFCrashConfig = KFCrashConfig()) {
        self.config = config
    }

    /// Register KFCrashService with ServiceFactory.
    public func start() {
        ServiceFactory.register((any KFCrashService).self) {
            let service = DefaultKFCrashService()
            try! service.install(config: config)
            return service
        }
    }
}
