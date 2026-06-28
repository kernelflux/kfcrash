# KFCrash

Production-grade iOS crash reporting — signal/Mach/NSException monitors, on-disk report store, privacy redaction, breadcrumbs, and chaining to existing handlers.

Built on [KSCrash](https://github.com/kstenerud/KSCrash) 2.5.1, restructured and adapted for the KernelFlux component library.

## Features

- **Multi-monitor crash capture** — Mach exceptions, POSIX signals, C++ exceptions, NSExceptions, deadlock watchdog
- **On-disk report store** — JSON-format crash reports persisted to disk, with configurable retention
- **Swift protocol API** — `KFCrashService` provides a clean interface independent of ObjC internals
- **Privacy redaction** — strip sensitive fields from reports via key-path configuration before export
- **Breadcrumbs** — lightweight event trail captured in crash reports for forensic context
- **Custom keys** — attach arbitrary key-value pairs to crash reports
- **Chaining** — forward exceptions to existing handlers (Firebase Crashlytics, Bugly) after capturing
- **KFService integration** — `KFCrashAssembly` + `KFCrashStartupModule` for DI and startup orchestration

## Installation

**Swift Package Manager**

```
https://github.com/kernelflux/kfcrash.git
```

Or in `Package.swift`:

```swift
.package(url: "https://github.com/kernelflux/kfcrash.git", from: "1.0.0")
```

Then add the target you need:

| Product | Language | Description | Depends on |
|---------|----------|-------------|------------|
| `KFCrash` | ObjC | Recording layer: monitor wrappers, report store | `KFCCore` |
| `KFCReporting` | ObjC | Reporting pipeline: filters, sinks, installations | `KFCrash` |
| `KFCAPI` | Swift | Protocol-only: `KFCrashService`, `KFCrashConfig` | nothing |
| `KFCSwift` | Swift | Swift impl + KFService integration | `KFCrash`, `KFCReporting`, `KFCAPI`, `KFService` |

## Architecture

```
KFCrash
├── KFCCore/             ← C/C++ (signal/Mach handlers, state machine, symbolication)
├── KFCrash/             ← ObjC (monitor wrappers, report store, KFCrashConfiguration)
├── KFCReporting/        ← ObjC (filters, sinks, installation strategies)
├── KFCAPI/              ← Swift protocol (KFCrashService) + config (KFCrashConfig)
└── KFCSwift/            ← DefaultKFCrashService, KFCrashAssembly, KFCrashStartupModule
```

## Quick Start

### Using KFService (recommended)

```swift
import KFService
import KFCSwift

// In App init — register via assembly
ServiceContainer.shared.install(KFCrashAssembly())

// In App.task — run startup (high priority boots early)
try await Engine.run(modules: [
    KFCrashStartupModule(config: KFCrashConfig(
        monitorTypes: .productionSafeMinimal,
        maxReportCount: 20,
        addConsoleLogToReport: true
    )),
])
```

Resolve and use anywhere:

```swift
let service = try ServiceContainer.shared.resolve(KFCrashService.self)

// Check crash state
if service.crashedLastLaunch {
    print("App crashed on previous launch")
}

// Read reports
for id in service.reportIDs {
    if let json = service.report(for: id) {
        upload(json)
        service.deleteReport(id)
    }
}
```

### Standalone (no KFService)

```swift
import KFCSwift
import KFCAPI

let service = DefaultKFCrashService()
try service.initialize(config: KFCrashConfig(
    monitorTypes: .fatal,
    maxReportCount: 10,
    addConsoleLogToReport: true
))

print("Crashed last launch: \(service.crashedLastLaunch)")
```

## Configuration

```swift
public struct KFCrashConfig {
    var monitorTypes: CrashMonitorTypes         // default: .productionSafeMinimal
    var maxReportCount: Int                     // default: 5
    var installPath: String?                    // nil = default cache dir
    var userInfo: [String: Any]?                // JSON-safe dict per report
    var deadlockWatchdogInterval: TimeInterval  // 0 = disabled
    var addConsoleLogToReport: Bool             // include KFLog output
    var enableSigTermMonitoring: Bool
    var enableQueueNameSearch: Bool
    var enableMemoryIntrospection: Bool
    var doNotIntrospectClasses: [String]?
    var chainToExistingHandlers: Bool           // default: true
    var privacyRedactFields: [String]           // dot-notation key paths
}
```

### CrashMonitorTypes

```swift
.fatal                   // Mach + signal + C++ + NSException
.productionSafeMinimal   // Mach + signal only
.all                     // all monitors including zombie, memory termination
```

## API Reference

### KFCrashService Protocol

```swift
public protocol KFCrashService: AnyObject {
    // Crash state
    var crashedLastLaunch: Bool { get }
    var launchesSinceLastCrash: Int { get }
    var sessionsSinceLastCrash: Int { get }
    var sessionsSinceLaunch: Int { get }
    var activeDurationSinceLastCrash: TimeInterval { get }

    // Lifecycle
    func initialize(config: KFCrashConfig) throws
    func unInit()

    // User reports
    func reportUserException(name:reason:language:stackTrace:terminateProgram:)
    func reportError(_ error: Error, terminateProgram: Bool)

    // Report management
    var reportCount: Int { get }
    var reportIDs: [String] { get }
    func report(for id: String) -> String?
    func shareReportURL(for id: String) -> URL?
    func allReportURLs() -> [URL]
    func deleteReport(_ id: String)
    func deleteAllReports()

    // Breadcrumbs
    func addBreadcrumb(_ message: String)
    func clearBreadcrumbs()

    // Custom keys
    func setCustomValue(_ value: String, forKey key: String)
    func removeCustomKey(_ key: String)
    func clearCustomKeys()

    // User identifier
    func setUserIdentifier(_ identifier: String?)
}
```

### Reporting an Error

```swift
// Non-fatal — write a crash report but don't terminate
service.reportError(MyError.invalidState, terminateProgram: false)

// Fatal — write a crash report and terminate
service.reportError(MyError.corruptDatabase, terminateProgram: true)
```

### Privacy Redaction

```swift
let config = KFCrashConfig(
    privacyRedactFields: ["user.name", "system.processPath", "binary_images"]
)
// Reports returned by report(for:) / shareReportURL(for:) will have
// these fields stripped before the JSON leaves memory.
```

## KFService Integration

| Type | Role |
|------|------|
| `KFCrashAssembly` | Implements `ServiceAssembly` — registers `KFCrashService` → `DefaultKFCrashService` |
| `KFCrashStartupModule` | Implements `StartupModule` — provides `KFCrashStartupTask` with config |

```swift
// Install (sync, in App init)
ServiceContainer.shared.install(KFCrashAssembly())

// Override with custom impl — last write wins
ServiceContainer.shared.register(KFCrashService.self) { MyCustomCrashService() }

// Run (async, in App.task) — priority 10 boots before KV, logger, network
try await Engine.run(modules: [
    KFCrashStartupModule(config: KFCrashConfig(monitorTypes: .fatal, maxReportCount: 10)),
])
```

## Source Layout

```
Sources/
├── KFCCore/              ← C/C++ (signal/Mach/NSException handlers, state, symbolication)
├── KFCrash/              ← ObjC (KFCrash, KFCrashConfiguration, monitor wrappers)
├── KFCReporting/         ← ObjC (filters, sinks, KFCrashInstallationStandard, etc.)
├── KFCAPI/               ← KFCrashService protocol, KFCrashConfig, CrashMonitorTypes
└── KFCSwift/             ← DefaultKFCrashService, KFCrashAssembly, KFCrashStartupModule
```

## License

[MIT](LICENSE) — Copyright (c) 2015 Karl Stenerud, Copyright (c) 2026 KernelFlux

This project is built on [KSCrash](https://github.com/kstenerud/KSCrash) and inherits its MIT license.
