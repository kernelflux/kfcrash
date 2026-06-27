//
//  KFCrash.m
//
//  Created by Karl Stenerud on 2012-01-28.
//
//  Copyright (c) 2012 Karl Stenerud. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall remain in place
// in this source code.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

#import "KFCrash.h"
#import "KFCrash+Private.h"

#import "KFCCompilerDefines.h"
#import "KFCrashC.h"
#import "KFCrashConfiguration+Private.h"
#import "KFCrashMonitorContext.h"
#import "KFCrashMonitor_AppState.h"
#import "KFCrashMonitor_Memory.h"
#import "KFCrashMonitor_System.h"
#import "KFCrashReport.h"
#import "KFCrashReportFields.h"
#import "KFCJSONCodecObjC.h"
#import "KFCNSErrorHelper.h"
#import "KFCSystemCapabilities.h"

// #define KSLogger_LocalLevel TRACE
#import "KFCLogger.h"

#include <inttypes.h>
#if KFCRASH_HAS_UIKIT
#import <UIKit/UIKit.h>
#endif

// ============================================================================
#pragma mark - Globals -
// ============================================================================

@interface KFCrash ()

@property(nonatomic, readwrite, copy) NSString *bundleName;
@property(nonatomic, strong) KFCrashConfiguration *configuration;

@end

static BOOL gIsSharedInstanceCreated = NO;

NSString *kfcrash_getBundleName(void)
{
    NSString *bundleName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleName"];
    if (bundleName == nil) {
        bundleName = @"Unknown";
    }
    return bundleName;
}

NSString *kfcrash_getDefaultInstallPath(void)
{
    NSArray *directories = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    if ([directories count] == 0) {
        KFCLOG_ERROR(@"Could not locate cache directory path.");
        return nil;
    }
    NSString *cachePath = [directories objectAtIndex:0];
    if ([cachePath length] == 0) {
        KFCLOG_ERROR(@"Could not locate cache directory path.");
        return nil;
    }
    NSString *pathEnd = [KFCRASH_NS_STRING(@"KFCrash") stringByAppendingPathComponent:kfcrash_getBundleName()];
    return [cachePath stringByAppendingPathComponent:pathEnd];
}

static void currentSnapshotUserReportedExceptionHandler(NSException *exception)
{
    if (!gIsSharedInstanceCreated) {
        KFCLOG_ERROR(@"Shared instance must exist before this function is called.");
        return;
    }
    [[KFCrash sharedInstance] reportNSException:exception logAllThreads:YES];
}

@implementation KFCrash

// ============================================================================
#pragma mark - Lifecycle -
// ============================================================================

+ (void)load
{
    [[self class] classDidBecomeLoaded];
}

+ (void)initialize
{
    if (self == [KFCrash class]) {
        [[self class] subscribeToNotifications];
    }
}

+ (instancetype)sharedInstance
{
    static KFCrash *sharedInstance = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        sharedInstance = [[KFCrash alloc] init];
        gIsSharedInstanceCreated = YES;
    });
    return sharedInstance;
}

static void onNSExceptionHandlingEnabled(NSUncaughtExceptionHandler *uncaughtExceptionHandler,
                                         KSCrashCustomNSExceptionReporter *customNSExceptionReporter)
{
    KFCrash.sharedInstance.uncaughtExceptionHandler = uncaughtExceptionHandler;
    KFCrash.sharedInstance.customNSExceptionReporter = customNSExceptionReporter;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _bundleName = kfcrash_getBundleName();
        _currentSnapshotUserReportedExceptionHandler = &currentSnapshotUserReportedExceptionHandler;
        kfccm_nsexception_setOnEnabledHandler(onNSExceptionHandlingEnabled);
    }
    return self;
}

// ============================================================================
#pragma mark - API -
// ============================================================================

- (NSDictionary *)userInfo
{
    const char *userInfoJSON = kfcrash_getUserInfoJSON();
    if (userInfoJSON != NULL && strlen(userInfoJSON) > 0) {
        NSError *error = nil;
        NSData *jsonData = [NSData dataWithBytes:userInfoJSON length:strlen(userInfoJSON)];
        NSDictionary *userInfoDict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
        free((void *)userInfoJSON);  // Free the allocated memory

        if (userInfoDict == nil) {
            KFCLOG_ERROR(@"Error parsing JSON: %@", error.localizedDescription);
            return nil;
        }
        return userInfoDict;
    }
    return nil;
}

- (void)setUserInfo:(NSDictionary *)userInfo
{
    NSError *error = nil;
    NSData *userInfoJSON = nil;

    if (userInfo != nil) {
        userInfoJSON = [NSJSONSerialization dataWithJSONObject:userInfo options:NSJSONWritingSortedKeys error:&error];

        if (userInfoJSON == nil) {
            KFCLOG_ERROR(@"Could not serialize user info: %@", error.localizedDescription);
            return;
        }
    }

    NSString *userInfoString =
        userInfoJSON ? [[NSString alloc] initWithData:userInfoJSON encoding:NSUTF8StringEncoding] : nil;
    kfcrash_setUserInfoJSON(userInfoString.UTF8String);
}

- (BOOL)reportsMemoryTerminations
{
    return ksmemory_get_fatal_reports_enabled();
}

- (void)setReportsMemoryTerminations:(BOOL)reportsMemoryTerminations
{
    ksmemory_set_fatal_reports_enabled(reportsMemoryTerminations);
}

- (NSDictionary *)systemInfo
{
    KFCrash_MonitorContext fakeEvent = { 0 };
    kfccm_system_getAPI()->addContextualInfoToEvent(&fakeEvent);
    NSMutableDictionary *dict = [NSMutableDictionary new];

#define COPY_STRING(A) \
    if (fakeEvent.System.A) dict[@ #A] = [NSString stringWithUTF8String:fakeEvent.System.A]
#define COPY_PRIMITIVE(A) dict[@ #A] = @(fakeEvent.System.A)
    COPY_STRING(systemName);
    COPY_STRING(systemVersion);
    COPY_STRING(machine);
    COPY_STRING(model);
    COPY_STRING(kernelVersion);
    COPY_STRING(osVersion);
    COPY_PRIMITIVE(isJailbroken);
    COPY_PRIMITIVE(procTranslated);
    COPY_STRING(bootTime);  // this field is populated in an optional monitor
    COPY_STRING(appStartTime);
    COPY_STRING(executablePath);
    COPY_STRING(executableName);
    COPY_STRING(bundleID);
    COPY_STRING(bundleName);
    COPY_STRING(bundleVersion);
    COPY_STRING(bundleShortVersion);
    COPY_STRING(appID);
    COPY_STRING(cpuArchitecture);
    COPY_STRING(binaryArchitecture);
    COPY_STRING(clangVersion);
    COPY_PRIMITIVE(cpuType);
    COPY_PRIMITIVE(cpuSubType);
    COPY_PRIMITIVE(binaryCPUType);
    COPY_PRIMITIVE(binaryCPUSubType);
    COPY_STRING(timezone);
    COPY_STRING(processName);
    COPY_PRIMITIVE(processID);
    COPY_PRIMITIVE(parentProcessID);
    COPY_STRING(deviceAppHash);
    COPY_STRING(buildType);
    COPY_PRIMITIVE(storageSize);      // this field is populated in an optional monitor
    COPY_PRIMITIVE(freeStorageSize);  // this field is populated in an optional monitor
    COPY_PRIMITIVE(memorySize);
    COPY_PRIMITIVE(freeMemory);
    COPY_PRIMITIVE(usableMemory);

    return [dict copy];
}

- (BOOL)installWithConfiguration:(KFCrashConfiguration *)configuration error:(NSError **)error
{
    self.configuration = [configuration copy] ?: [KFCrashConfiguration new];
    self.configuration.installPath = configuration.installPath ?: kfcrash_getDefaultInstallPath();

    if (self.configuration.reportStoreConfiguration.appName == nil) {
        self.configuration.reportStoreConfiguration.appName = self.bundleName;
    }
    if (self.configuration.reportStoreConfiguration.reportsPath == nil) {
        self.configuration.reportStoreConfiguration.reportsPath = [self.configuration.installPath
            stringByAppendingPathComponent:[KFCrashReportStore defaultInstallSubfolder]];
    }
    KFCrashReportStore *reportStore =
        [KFCrashReportStore storeWithConfiguration:self.configuration.reportStoreConfiguration error:error];
    if (reportStore == nil) {
        return NO;
    }

    KFCrashCConfiguration config = [self.configuration toCConfiguration];
    KSCrashInstallErrorCode result =
        kfcrash_install(self.bundleName.UTF8String, self.configuration.installPath.UTF8String, &config);
    KFCrashCConfiguration_Release(&config);
    if (result != KSCrashInstallErrorNone) {
        if (error != NULL) {
            *error = [KFCrash errorForInstallErrorCode:result];
        }
        return NO;
    }

    _reportStore = reportStore;
    return YES;
}

- (void)reportUserException:(NSString *)name
                     reason:(NSString *)reason
                   language:(NSString *)language
                 lineOfCode:(NSString *)lineOfCode
                 stackTrace:(NSArray *)stackTrace
              logAllThreads:(BOOL)logAllThreads
           terminateProgram:(BOOL)terminateProgram KS_KEEP_FUNCTION_IN_STACKTRACE
{
    const char *cName = [name cStringUsingEncoding:NSUTF8StringEncoding];
    const char *cReason = [reason cStringUsingEncoding:NSUTF8StringEncoding];
    const char *cLanguage = [language cStringUsingEncoding:NSUTF8StringEncoding];
    const char *cLineOfCode = [lineOfCode cStringUsingEncoding:NSUTF8StringEncoding];
    const char *cStackTrace = NULL;

    if (stackTrace != nil) {
        NSError *error = nil;
        NSData *jsonData = [KFCJSONCodec encode:stackTrace options:0 error:&error];
        if (jsonData == nil) {
            KFCLOG_ERROR(@"Error encoding stack trace to JSON: %@", error);
            // Don't return, since we can still record other useful information.
        }
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        cStackTrace = [jsonString cStringUsingEncoding:NSUTF8StringEncoding];
    }

    kfcrash_reportUserException(cName, cReason, cLanguage, cLineOfCode, cStackTrace, logAllThreads, terminateProgram);
    KS_THWART_TAIL_CALL_OPTIMISATION
}

- (void)reportNSException:(NSException *)exception logAllThreads:(BOOL)logAllThreads KS_KEEP_FUNCTION_IN_STACKTRACE
{
    if (_customNSExceptionReporter == NULL) {
        KFCLOG_ERROR(@"NSExcepttion monitor needs to be installed before reporting custom exceptions");
        return;
    }
    _customNSExceptionReporter(exception, logAllThreads);
    KS_THWART_TAIL_CALL_OPTIMISATION
}

// ============================================================================
#pragma mark - Breadcrumbs -
// ============================================================================

- (void)addBreadcrumb:(NSString *)message
{
    kfcrash_addBreadcrumb(message.UTF8String);
}

- (void)clearBreadcrumbs
{
    kfcrash_clearBreadcrumbs();
}

// ============================================================================
#pragma mark - Custom Keys -
// ============================================================================

- (void)setCustomValue:(NSString *)value forKey:(NSString *)key
{
    kfcrash_setCustomKey(key.UTF8String, value.UTF8String);
}

- (void)removeCustomKey:(NSString *)key
{
    kfcrash_removeCustomKey(key.UTF8String);
}

- (void)clearCustomKeys
{
    kfcrash_clearCustomKeys();
}

// ============================================================================
#pragma mark - User Identifier -
// ============================================================================

- (void)setUserIdentifier:(NSString *)identifier
{
    NSMutableDictionary *userInfo = [[self userInfo] mutableCopy] ?: [NSMutableDictionary new];
    if (identifier.length > 0) {
        userInfo[@"userID"] = identifier;
    } else {
        [userInfo removeObjectForKey:@"userID"];
    }
    self.userInfo = userInfo;
}

// ============================================================================
#pragma mark - Advanced API -
// ============================================================================

#define SYNTHESIZE_CRASH_STATE_PROPERTY(TYPE, NAME) \
    -(TYPE)NAME { return kfcrashstate_currentState()->NAME; }

SYNTHESIZE_CRASH_STATE_PROPERTY(NSTimeInterval, activeDurationSinceLastCrash)
SYNTHESIZE_CRASH_STATE_PROPERTY(NSTimeInterval, backgroundDurationSinceLastCrash)
SYNTHESIZE_CRASH_STATE_PROPERTY(NSInteger, launchesSinceLastCrash)
SYNTHESIZE_CRASH_STATE_PROPERTY(NSInteger, sessionsSinceLastCrash)
SYNTHESIZE_CRASH_STATE_PROPERTY(NSTimeInterval, activeDurationSinceLaunch)
SYNTHESIZE_CRASH_STATE_PROPERTY(NSTimeInterval, backgroundDurationSinceLaunch)
SYNTHESIZE_CRASH_STATE_PROPERTY(NSInteger, sessionsSinceLaunch)
SYNTHESIZE_CRASH_STATE_PROPERTY(BOOL, crashedLastLaunch)

// ============================================================================
#pragma mark - Utility -
// ============================================================================

+ (NSError *)errorForInstallErrorCode:(KSCrashInstallErrorCode)errorCode
{
    NSString *errorDescription;
    switch (errorCode) {
        case KSCrashInstallErrorNone:
            return nil;
        case KSCrashInstallErrorAlreadyInstalled:
            errorDescription = @"KFCrash is already installed";
            break;
        case KSCrashInstallErrorInvalidParameter:
            errorDescription = @"Invalid parameter provided";
            break;
        case KSCrashInstallErrorPathTooLong:
            errorDescription = @"Path is too long";
            break;
        case KSCrashInstallErrorCouldNotCreatePath:
            errorDescription = @"Could not create path";
            break;
        case KSCrashInstallErrorCouldNotInitializeStore:
            errorDescription = @"Could not initialize crash report store";
            break;
        case KSCrashInstallErrorCouldNotInitializeMemory:
            errorDescription = @"Could not initialize memory management";
            break;
        case KSCrashInstallErrorCouldNotInitializeCrashState:
            errorDescription = @"Could not initialize crash state";
            break;
        case KSCrashInstallErrorCouldNotSetLogFilename:
            errorDescription = @"Could not set log filename";
            break;
        case KSCrashInstallErrorNoActiveMonitors:
            errorDescription = @"No crash monitors were activated";
            break;
        default:
            errorDescription = @"Unknown error occurred";
            break;
    }
    return [NSError errorWithDomain:KSCrashErrorDomain
                               code:errorCode
                           userInfo:@{ NSLocalizedDescriptionKey : errorDescription }];
}

// ============================================================================
#pragma mark - Notifications -
// ============================================================================

+ (void)subscribeToNotifications
{
#if KFCRASH_HAS_UIAPPLICATION
    NSNotificationCenter *nCenter = [NSNotificationCenter defaultCenter];
    [nCenter addObserver:self
                selector:@selector(applicationDidBecomeActive)
                    name:UIApplicationDidBecomeActiveNotification
                  object:nil];
    [nCenter addObserver:self
                selector:@selector(applicationWillResignActive)
                    name:UIApplicationWillResignActiveNotification
                  object:nil];
    [nCenter addObserver:self
                selector:@selector(applicationDidEnterBackground)
                    name:UIApplicationDidEnterBackgroundNotification
                  object:nil];
    [nCenter addObserver:self
                selector:@selector(applicationWillEnterForeground)
                    name:UIApplicationWillEnterForegroundNotification
                  object:nil];
    [nCenter addObserver:self
                selector:@selector(applicationWillTerminate)
                    name:UIApplicationWillTerminateNotification
                  object:nil];
#endif
#if KFCRASH_HAS_NSEXTENSION
    NSNotificationCenter *nCenter = [NSNotificationCenter defaultCenter];
    [nCenter addObserver:self
                selector:@selector(applicationDidBecomeActive)
                    name:NSExtensionHostDidBecomeActiveNotification
                  object:nil];
    [nCenter addObserver:self
                selector:@selector(applicationWillResignActive)
                    name:NSExtensionHostWillResignActiveNotification
                  object:nil];
    [nCenter addObserver:self
                selector:@selector(applicationDidEnterBackground)
                    name:NSExtensionHostDidEnterBackgroundNotification
                  object:nil];
    [nCenter addObserver:self
                selector:@selector(applicationWillEnterForeground)
                    name:NSExtensionHostWillEnterForegroundNotification
                  object:nil];
#endif
}

+ (void)classDidBecomeLoaded
{
    kfcrash_notifyObjCLoad();
}

+ (void)applicationDidBecomeActive
{
    kfcrash_notifyAppActive(true);
}

+ (void)applicationWillResignActive
{
    kfcrash_notifyAppActive(false);
}

+ (void)applicationDidEnterBackground
{
    kfcrash_notifyAppInForeground(false);
}

+ (void)applicationWillEnterForeground
{
    kfcrash_notifyAppInForeground(true);
}

+ (void)applicationWillTerminate
{
    kfcrash_notifyAppTerminate();
}

@end

//! Project version number for KSCrashFramework.
const double KFCrashFrameworkVersionNumber = 2.0501;

//! Project version string for KSCrashFramework.
const unsigned char KFCrashFrameworkVersionString[] = "2.5.1";
