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
| `KFCAPI` | Swift | Protocol-only: `KFCrashService`, `KFCrashConfig`, `CrashReportSink` | nothing |
| `KFCSwift` | Swift | Swift impl + KFService integration | `KFCrash`, `KFCReporting`, `KFCAPI`, `KFService` |
| `KFCrashChina` | Swift | `KFCSwift` + `BuglyCrashAdapter` (Bugly 2.6.1) | `bugly-spm` → `Bugly` |
| `KFCrashGlobal` | Swift | `KFCSwift` + `FirebaseCrashlyticsAdapter` (Firebase 12.15.0) | `firebase-ios-sdk` → `FirebaseCrashlytics` |

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
    var sink: (any CrashReportSink)?           // third-party forwarding for user-reported exceptions
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

## CrashReportSink — Third-party Forwarding

KFCrash handles native crashes (Mach exceptions, signals, NSExceptions) through a handler chain — make sure commercial SDKs initialize **before** KFCrash. The `CrashReportSink` protocol is for **user-reported exceptions** only (`reportUserException` / `reportError`).

```swift
// Bugly initializes first (installs its NSException handler)
// KFCrash initializes second (saves Bugly's handler, chains to it)

var config = KFCrashConfig(...)
config.sink = BuglyCrashAdapter(appId: "YOUR_BUGLY_APP_ID", channel: "App Store")
```

Each adapter initializes the underlying SDK internally — just pass credentials.

### BuglyCrashAdapter (China)

```swift
import KFCAPI
import Bugly

// config.sink = BuglyCrashAdapter(appId:id, channel:"App Store", debug:false)
```

Forwards user-reported exceptions via `Bugly.reportException(withCategory:name:reason:callStack:extraInfo:terminateApp:)`.  
Dependency: `bugly-spm` → `Bugly` (2.6.1).

### FirebaseCrashlyticsAdapter (Global)

```swift
import KFCAPI
import FirebaseCrashlytics

// config.sink = FirebaseCrashlyticsAdapter()
```

Forwards user-reported exceptions via `Crashlytics.crashlytics().record(exceptionModel:)`.  
Dependency: `firebase-ios-sdk` → `FirebaseCrashlytics` (12.15.0).

> Firebase itself must be configured via `FirebaseApp.configure()` in the host app before use.

### Initialization Order

```
1. Bugly.start(...)           ← commercial SDK first (installs NSException handler)
2. KFCrash.install()          ← KFCrash second (saves previous handler, chains to it)
```

This ensures native crashes are captured by both systems without overwriting each other's handlers.

### User-Reported Exception Flow

```
App code
   │
   ▼
KFCrash.reportUserException(...)          ← user-reported exception
   │
   ├─► Write JSON report to KFCrash store ← always
   │
   └─► CrashReportSink.didCapture(...)    ← forwarded to adapter
          │
          ├─► Bugly.reportException(...)   ← if KFCrashChina
          │
          └─► Crashlytics.record(...)     ← if KFCrashGlobal
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
├── KFCAPI/               ← KFCrashService protocol, KFCrashConfig, CrashReportSink, CrashMonitorTypes
├── KFCSwift/             ← DefaultKFCrashService, KFCrashAssembly, KFCrashStartupModule
└── Adapters/
    ├── BuglyCrash/        ← BuglyCrashAdapter (KFCrashChina)
    └── FirebaseCrashlytics/ ← FirebaseCrashlyticsAdapter (KFCrashGlobal)
```

## License

[MIT](LICENSE) — Copyright (c) 2015 Karl Stenerud, Copyright (c) 2026 KernelFlux

This project is built on [KSCrash](https://github.com/kstenerud/KSCrash) and inherits its MIT license.
