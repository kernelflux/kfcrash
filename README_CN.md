# KFCrash

生产级 iOS 崩溃上报 —— signal/Mach/NSException 多监控器、磁盘报告存储、隐私脱敏、面包屑追踪、与现有 handler 链式转发。

基于 [KSCrash](https://github.com/kstenerud/KSCrash) 2.5.1，重构适配 KernelFlux 组件库。

[English](README.md)

## 特性

- **多监控器崩溃捕获** — Mach 异常、POSIX 信号、C++ 异常、NSException、主线程死锁看门狗
- **磁盘报告存储** — JSON 格式崩溃报告持久化到磁盘，可配置保留数量
- **Swift 协议 API** — `KFCrashService` 提供独立于 ObjC 内部的清晰接口
- **隐私脱敏** — 导出前通过键路径配置剥离报告中的敏感字段
- **面包屑** — 轻量级事件轨迹，捕获到崩溃报告用于取证上下文
- **自定义键值** — 向崩溃报告附加任意键值对
- **链式转发** — 捕获后将异常转发给已有 handler（Firebase Crashlytics、Bugly）
- **KFService 集成** — `KFCrashModule` 以最高优先级自动注册到服务管理器

## 安装

**Swift Package Manager**

```
https://github.com/kernelflux/kfcrash.git
```

或在 `Package.swift` 中：

```swift
.package(url: "https://github.com/kernelflux/kfcrash.git", from: "1.0.0")
```

按需添加 target：

| Product | 语言 | 说明 | 依赖 |
|---------|------|------|------|
| `KFCrash` | ObjC | 录制层：监控器封装、报告存储 | `KFCCore` |
| `KFCReporting` | ObjC | 上报管道：过滤器、接收器、安装策略 | `KFCrash` |
| `KFCAPI` | Swift | 纯协议：`KFCrashService`、`KFCrashConfig` | 无 |
| `KFCSwift` | Swift | Swift 实现 + KFService 注册 | `KFCrash`、`KFCReporting`、`KFCAPI`、`KFService` |

## 架构

```
KFCrash
├── KFCCore/             ← C/C++（signal/Mach handler、状态机、符号表）
├── KFCrash/             ← ObjC（监控器封装、报告存储、KFCrashConfiguration）
├── KFCReporting/        ← ObjC（过滤器、接收器、安装策略）
├── KFCAPI/              ← Swift 协议（KFCrashService）+ 配置（KFCrashConfig）
└── KFCSwift/            ← DefaultKFCrashService、KFCrashModule
```

## 快速开始

### 配合 KFService 使用（推荐）

```swift
import KFService
import KFCSwift

// App 启动时注册 —— priority 10 确保最先启动
KFServiceManager.register(module: KFCrashModule())

// 查询崩溃状态
let service = KFServiceManager.resolve((any KFCrashService).self)
if service.crashedLastLaunch {
    print("上次启动发生了崩溃")
}

// 读取报告
for id in service.reportIDs {
    if let json = service.report(for: id) {
        upload(json)
        service.deleteReport(id)
    }
}
```

### 独立使用（无需 KFService）

```swift
import KFCSwift
import KFCAPI

let service = DefaultKFCrashService()
try service.install(config: KFCrashConfig(
    monitorTypes: .fatal,
    maxReportCount: 10,
    addConsoleLogToReport: true
))

print("上次启动是否崩溃: \(service.crashedLastLaunch)")
```

## 配置

```swift
public struct KFCrashConfig {
    var monitorTypes: CrashMonitorTypes         // 默认: .productionSafeMinimal
    var maxReportCount: Int                     // 默认: 5
    var installPath: String?                    // nil = 默认缓存目录
    var userInfo: [String: Any]?                // JSON 安全字典，附入每份报告
    var deadlockWatchdogInterval: TimeInterval  // 0 = 禁用
    var addConsoleLogToReport: Bool             // 是否包含 KFLog 输出
    var enableSigTermMonitoring: Bool
    var enableQueueNameSearch: Bool
    var enableMemoryIntrospection: Bool
    var doNotIntrospectClasses: [String]?
    var chainToExistingHandlers: Bool           // 默认: true
    var privacyRedactFields: [String]           // 点分键路径
}
```

### CrashMonitorTypes

```swift
.fatal                   // Mach + signal + C++ + NSException
.productionSafeMinimal   // 仅 Mach + signal
.all                     // 全部监控器，包括 zombie、memory termination
```

## API 参考

### KFCrashService 协议

```swift
public protocol KFCrashService: AnyObject {
    // 崩溃状态
    var crashedLastLaunch: Bool { get }
    var launchesSinceLastCrash: Int { get }
    var sessionsSinceLastCrash: Int { get }

    // 安装
    func install(config: KFCrashConfig) throws

    // 用户报告
    func reportUserException(name:reason:language:stackTrace:terminateProgram:)
    func reportError(_ error: Error, terminateProgram: Bool)

    // 报告管理
    var reportCount: Int { get }
    var reportIDs: [String] { get }
    func report(for id: String) -> String?
    func shareReportURL(for id: String) -> URL?
    func allReportURLs() -> [URL]
    func deleteReport(_ id: String)
    func deleteAllReports()

    // 面包屑
    func addBreadcrumb(_ message: String)
    func clearBreadcrumbs()

    // 自定义键值
    func setCustomValue(_ value: String, forKey key: String)
    func removeCustomKey(_ key: String)
    func clearCustomKeys()

    // 用户标识
    func setUserIdentifier(_ identifier: String?)
}
```

### 上报错误

```swift
// 非致命 —— 写入崩溃报告但不终止进程
service.reportError(MyError.invalidState, terminateProgram: false)

// 致命 —— 写入崩溃报告并终止进程
service.reportError(MyError.corruptDatabase, terminateProgram: true)
```

### 隐私脱敏

```swift
let config = KFCrashConfig(
    privacyRedactFields: ["user.name", "system.processPath", "binary_images"]
)
// report(for:) / shareReportURL(for:) 返回的报告会在 JSON 离开内存前剥离这些字段
```

## KFCrashModule

```swift
KFServiceManager.register(module: KFCrashModule(
    config: KFCrashConfig(
        monitorTypes: .fatal,
        maxReportCount: 10,
        privacyRedactFields: ["user.name", "user.email"]
    )
))
// priority: 10 —— 在 KV 存储、日志、网络之前启动
```

## 源文件结构

```
Sources/
├── KFCCore/              ← C/C++（signal/Mach/NSException handler、状态机、符号表）
├── KFCrash/              ← ObjC（KFCrash、KFCrashConfiguration、监控器封装）
├── KFCReporting/         ← ObjC（过滤器、接收器、KFCrashInstallationStandard 等）
├── KFCAPI/               ← KFCrashService 协议、KFCrashConfig、CrashMonitorTypes
└── KFCSwift/             ← DefaultKFCrashService、KFCrashModule
```

## 许可证

[MIT](LICENSE) — Copyright (c) 2015 Karl Stenerud，Copyright (c) 2026 KernelFlux

本项目基于 [KSCrash](https://github.com/kstenerud/KSCrash)，继承其 MIT 许可证。
