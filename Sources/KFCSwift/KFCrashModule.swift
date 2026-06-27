import KFCAPI
import KFService

/// KFCrash module — implements ModuleProtocol for DAG startup.
///
///     try await Engine.run(graph: graph)
///     ServiceFactory.resolve((any KFCrashService).self).crashedLastLaunch
public final class KFCrashModule: ModuleProtocol {
    public static var dependencies: [ModuleID] { [] }

    private let config: KFCrashConfig

    public init(config: KFCrashConfig = KFCrashConfig()) {
        self.config = config
    }

    public func performInit() async {
        ServiceFactory.register((any KFCrashService).self) {
            let service = DefaultKFCrashService()
            try! service.install(config: config)
            return service
        }
    }
}
