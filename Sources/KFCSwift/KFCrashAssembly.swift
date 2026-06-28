import KFService
import KFCAPI

public struct KFCrashAssembly: ServiceAssembly {
    public init() {}
    public func assemble(container: ServiceContainer) {
        container.register(KFCrashService.self) { DefaultKFCrashService() }
    }
}
