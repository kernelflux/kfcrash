import KFCAPI
import KFService
@_exported import KFCAPI

/// KFCrash service module — registers the default crash reporter with KFServiceManager.
///
///     KFServiceManager.register(module: KFCrashModule(config: ...))
///     KFServiceManager.resolve((any KFCrashService).self).crashedLastLaunch
public struct KFCrashModule: KFModule {
    private let config: KFCrashConfig

    public init(config: KFCrashConfig = KFCrashConfig()) {
        self.config = config
    }

    public func register() {
        KFServiceManager.register((any KFCrashService).self) {
            let service = DefaultKFCrashService()
            try! service.install(config: config)
            return service
        }
    }
}
