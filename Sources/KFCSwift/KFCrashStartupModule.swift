import KFService
import KFCAPI

final class KFCrashStartupTask: BaseStartupTask {
    override var identifier: String { "com.kernelflux.crash" }
    override var actorRequirement: ActorRequirement { .mainActor }

    private let config: KFCrashConfig

    init(config: KFCrashConfig) { self.config = config }

    override func run() async throws {
        let crash = try ServiceContainer.shared.resolve(KFCrashService.self)
        try crash.initialize(config: config)
    }
}

public struct KFCrashStartupModule: StartupModule {
    private let config: KFCrashConfig
    public var tasks: [any StartupTask] { [KFCrashStartupTask(config: config)] }
    public init(config: KFCrashConfig) { self.config = config }
}
