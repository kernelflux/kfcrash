//
//  KSCrashC.c
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

#include "KFCrashC.h"

#include "KFCBinaryImageCache.h"
#include "KFCCompilerDefines.h"
#include "KFCrashExceptionHandlingPlan+Private.h"
#include "KFCrashMonitor.h"
#include "KFCrashMonitorContext.h"
#include "KFCrashMonitorType.h"
#include "KFCrashMonitor_AppState.h"
#include "KFCrashMonitor_CPPException.h"
#include "KFCrashMonitor_Deadlock.h"
#include "KFCrashMonitor_MachException.h"
#include "KFCrashMonitor_Memory.h"
#include "KFCrashMonitor_NSException.h"
#include "KFCrashMonitor_Signal.h"
#include "KFCrashMonitor_System.h"
#include "KFCrashMonitor_User.h"
#include "KFCrashMonitor_Zombie.h"
#include "KFCrashReportC.h"
#include "KFCrashReportFixer.h"
#include "KFCrashReportStoreC+Private.h"
#include "KFCrashUserData.h"
#include "KFCFileUtils.h"
#include "KFCObjC.h"
#include "KFCString.h"
#include "KFCSystemCapabilities.h"
#include "KFCThreadCache.h"

// #define KSLogger_LocalLevel TRACE
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "KFCLogger.h"

#define KSC_MAX_APP_NAME_LENGTH 100

typedef enum {
    KSApplicationStateNone,
    KSApplicationStateDidBecomeActive,
    KSApplicationStateWillResignActiveActive,
    KSApplicationStateDidEnterBackground,
    KSApplicationStateWillEnterForeground,
    KSApplicationStateWillTerminate
} KSApplicationState;

static const struct KFCrashMonitorMapping {
    KFCrashMonitorType type;
    KFCrashMonitorAPI *(*getAPI)(void);
} g_monitorMappings[] = { { KFCrashMonitorTypeMachException, kfccm_machexception_getAPI },
                          { KFCrashMonitorTypeSignal, kfccm_signal_getAPI },
                          { KFCrashMonitorTypeCPPException, kfccm_cppexception_getAPI },
                          { KFCrashMonitorTypeNSException, kfccm_nsexception_getAPI },
                          { KFCrashMonitorTypeMainThreadDeadlock, kfccm_deadlock_getAPI },
                          { KFCrashMonitorTypeUserReported, kfccm_user_getAPI },
                          { KFCrashMonitorTypeSystem, kfccm_system_getAPI },
                          { KFCrashMonitorTypeApplicationState, kfccm_appstate_getAPI },
                          { KFCrashMonitorTypeZombie, kfccm_zombie_getAPI },
                          { KFCrashMonitorTypeMemoryTermination, kfccm_memory_getAPI } };

static const size_t g_monitorMappingCount = sizeof(g_monitorMappings) / sizeof(g_monitorMappings[0]);

// ============================================================================
#pragma mark - Globals -
// ============================================================================

/** True if KFCrash has been installed. */
/** Maximum size for mmap crash report buffers (2 MB).
 *  Covers 99.9%+ of crash reports; overflow triggers graceful truncation. */
#define KFCRASH_MMAP_BUFFER_SIZE (2 * 1024 * 1024)

static volatile bool g_installed = 0;

static bool g_shouldAddConsoleLogToReport = false;
static bool g_shouldPrintPreviousLog = false;
static char g_consoleLogPath[KSFU_MAX_PATH_LENGTH];
static KFCrashMonitorType g_monitoring = KFCrashMonitorTypeProductionSafeMinimal;
static char g_lastCrashReportFilePath[KSFU_MAX_PATH_LENGTH];
static KFCrashReportStoreCConfiguration g_reportStoreConfig;

/** Pre-allocated mmap buffers for crash-time report writing. */
static char g_crashMmapPath[KSFU_MAX_PATH_LENGTH];
static char g_recrashMmapPath[KSFU_MAX_PATH_LENGTH];
char *g_crashMmapBuffer;
char *g_recrashMmapBuffer;
// TODO: Remove in 3.0
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static KSReportWriteCallback g_legacyCrashNotifyCallback;
static KSReportWrittenCallback g_legacyReportWrittenCallback;
#pragma clang diagnostic pop
static KSCrashWillWriteReportCallback g_willWriteReportCallback;
static KSCrashIsWritingReportCallback g_isWritingReportCallback;
static KSCrashDidWriteReportCallback g_didWriteReportCallback;
static KSApplicationState g_lastApplicationState = KSApplicationStateNone;

// ============================================================================
#pragma mark - Utility -
// ============================================================================

static void printPreviousLog(const char *filePath)
{
    char *data;
    int length;
    if (ksfu_readEntireFile(filePath, &data, &length, 0)) {
        printf("\nvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv Previous Log vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv\n\n");
        printf("%s\n", data);
        free(data);
        printf("^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n\n");
        fflush(stdout);
    }
}

// ============================================================================
#pragma mark - Callback Adapters -
// ============================================================================

/** Adapter function that bridges legacy crash notify callback to new signature.
 * This allows old callbacks without plan awareness to be used with the new system.
 */
static void legacyCrashNotifyCallbackAdapter(__unused const KFCrash_ExceptionHandlingPlan *const plan,
                                             const KFCrashReportWriter *writer)
{
    if (g_legacyCrashNotifyCallback) {
        KFCLOG_WARN(
            "Using deprecated crash notify callback without plan awareness. "
            "Consider upgrading to isWritingReportCallback.");
        g_legacyCrashNotifyCallback(writer);
    }
}

/** Adapter function that bridges legacy report written callback to new signature.
 * This allows old callbacks without plan awareness to be used with the new system.
 */
static void legacyReportWrittenCallbackAdapter(__unused const KFCrash_ExceptionHandlingPlan *const plan,
                                               int64_t reportID)
{
    if (g_legacyReportWrittenCallback) {
        KFCLOG_WARN(
            "Using deprecated report written callback without plan awareness. "
            "Consider upgrading to didWriteReportCallback.");
        g_legacyReportWrittenCallback(reportID);
    }
}

static void notifyOfBeforeInstallationState(void)
{
    KFCLOG_DEBUG("Notifying of pre-installation state");
    switch (g_lastApplicationState) {
        case KSApplicationStateDidBecomeActive:
            return kfcrash_notifyAppActive(true);
        case KSApplicationStateWillResignActiveActive:
            return kfcrash_notifyAppActive(false);
        case KSApplicationStateDidEnterBackground:
            return kfcrash_notifyAppInForeground(false);
        case KSApplicationStateWillEnterForeground:
            return kfcrash_notifyAppInForeground(true);
        case KSApplicationStateWillTerminate:
            return kfcrash_notifyAppTerminate();
        default:
            return;
    }
}

// ============================================================================
#pragma mark - Callbacks -
// ============================================================================

/** Called when a crash occurs.
 *
 * This function gets passed as a callback to a crash handler.
 */
static void onExceptionEvent(struct KFCrash_MonitorContext *monitorContext)
{
    // Check if the user wants to modify the plan for this crash.
    if (g_willWriteReportCallback) {
        KFCrash_ExceptionHandlingPlan plan = kfcexc_monitorContextToPlan(monitorContext);
        g_willWriteReportCallback(&plan, monitorContext);
        kfcexc_modifyMonitorContextUsingPlan(monitorContext, &plan);
    }

    // If we shouldn't write a report, then there's nothing left to do here.
    if (!monitorContext->requirements.shouldWriteReport) {
        return;
    }

    if (monitorContext->currentSnapshotUserReported == false) {
        KFCLOG_DEBUG("Updating application state to note crash.");
        kfcrashstate_notifyAppCrash();
    }
    monitorContext->consoleLogPath = g_shouldAddConsoleLogToReport ? g_consoleLogPath : NULL;

    if (monitorContext->requirements.crashedDuringExceptionHandling) {
        kfcrashreport_writeRecrashReport(monitorContext, g_lastCrashReportFilePath);
    } else if (monitorContext->reportPath) {
        kfcrashreport_writeStandardReport(monitorContext, monitorContext->reportPath);
    } else {
        char crashReportFilePath[KSFU_MAX_PATH_LENGTH];
        int64_t reportID = kscrs_getNextCrashReport(crashReportFilePath, &g_reportStoreConfig);
        strncpy(g_lastCrashReportFilePath, crashReportFilePath, sizeof(g_lastCrashReportFilePath));
        kfcrashreport_writeStandardReport(monitorContext, crashReportFilePath);

        if (g_didWriteReportCallback != NULL) {
            KFCrash_ExceptionHandlingPlan plan = kfcexc_monitorContextToPlan(monitorContext);
            g_didWriteReportCallback(&plan, reportID);
        }
    }
}

static void setMonitors(KFCrashMonitorType monitorTypes)
{
    g_monitoring = monitorTypes;

    for (size_t i = 0; i < g_monitorMappingCount; i++) {
        KFCrashMonitorAPI *api = g_monitorMappings[i].getAPI();
        if (api != NULL) {
            if (monitorTypes & g_monitorMappings[i].type) {
                kfccm_addMonitor(api);
            } else {
                kfccm_removeMonitor(api);
            }
        }
    }
}

static void handleConfiguration(KFCrashCConfiguration *configuration)
{
    g_reportStoreConfig = KFCrashReportStoreCConfiguration_Copy(&configuration->reportStoreConfiguration);

    if (configuration->userInfoJSON != NULL) {
        kfcrashreport_setUserInfoJSON(configuration->userInfoJSON);
    }
#if KFCRASH_HAS_OBJC
    kfccm_setDeadlockHandlerWatchdogInterval(configuration->deadlockWatchdogInterval);
#endif
    kfctc_setSearchQueueNames(configuration->enableQueueNameSearch);
    kfcrashreport_setIntrospectMemory(configuration->enableMemoryIntrospection);
    kfccm_signal_sigterm_setMonitoringEnabled(configuration->enableSigTermMonitoring);

    if (configuration->doNotIntrospectClasses.strings != NULL) {
        kfcrashreport_setDoNotIntrospectClasses(configuration->doNotIntrospectClasses.strings,
                                                configuration->doNotIntrospectClasses.length);
    }

    // TODO: Remove in 3.0 - Set up deprecated callbacks for backward compatibility
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    g_legacyCrashNotifyCallback = configuration->crashNotifyCallback;
    g_legacyReportWrittenCallback = configuration->reportWrittenCallback;
#pragma clang diagnostic pop

    if (configuration->isWritingReportCallback) {
        g_isWritingReportCallback = configuration->isWritingReportCallback;
    } else if (g_legacyCrashNotifyCallback) {
        g_isWritingReportCallback = legacyCrashNotifyCallbackAdapter;
    } else {
        g_isWritingReportCallback = NULL;
    }

    if (configuration->didWriteReportCallback) {
        g_didWriteReportCallback = configuration->didWriteReportCallback;
    } else if (g_legacyReportWrittenCallback) {
        g_didWriteReportCallback = legacyReportWrittenCallbackAdapter;
    } else {
        g_didWriteReportCallback = NULL;
    }

    kfcrashreport_setIsWritingReportCallback(g_isWritingReportCallback);
    g_shouldAddConsoleLogToReport = configuration->addConsoleLogToReport;
    g_shouldPrintPreviousLog = configuration->printPreviousLogOnStartup;
    g_willWriteReportCallback = configuration->willWriteReportCallback;

    if (configuration->enableSwapCxaThrow) {
        kfccm_enableSwapCxaThrow();
    }
}
// ============================================================================
#pragma mark - Mmap Recovery -
// ============================================================================

/** Recover any crash data left in the mmap buffers from a previous run.
 *  Called at install time (non-crash path), so any APIs are safe. */
static void kfcrash_recoverMmapReport(const char *mmapPath)
{
    // mmap files don't exist on first launch — skip silently.
    if (access(mmapPath, F_OK) != 0) {
        return;
    }
    char *data = NULL;
    int length = 0;
    if (!ksfu_readEntireFile(mmapPath, &data, &length, 0) || length <= 0) {
        free(data);
        return;
    }
    // Trim trailing mmap zero-fill to get actual JSON length.
    int actualLength = length;
    while (actualLength > 0 && data[actualLength - 1] == '\0') {
        actualLength--;
    }
    if (actualLength > 0) {
        KFCLOG_INFO("Recovering crash report from mmap buffer: %s (%d bytes)", mmapPath, actualLength);
        kscrs_addUserReport(data, actualLength, &g_reportStoreConfig);
    }
    free(data);
}

// ============================================================================
#pragma mark - API -
// ============================================================================

KSCrashInstallErrorCode kfcrash_install(const char *appName, const char *const installPath,
                                        KFCrashCConfiguration *configuration)
{
    KFCLOG_DEBUG("Installing crash reporter.");

    if (g_installed) {
        KFCLOG_DEBUG("Crash reporter already installed.");
        return KSCrashInstallErrorAlreadyInstalled;
    }

    if (appName == NULL || installPath == NULL) {
        KFCLOG_ERROR("Invalid parameters: appName or installPath is NULL.");
        return KSCrashInstallErrorInvalidParameter;
    }

    handleConfiguration(configuration);

    if (g_reportStoreConfig.appName == NULL) {
        g_reportStoreConfig.appName = strdup(appName);
    }

    char path[KSFU_MAX_PATH_LENGTH];
    if (g_reportStoreConfig.reportsPath == NULL) {
        if (snprintf(path, sizeof(path), "%s/" KSCRS_DEFAULT_REPORTS_FOLDER, installPath) >= (int)sizeof(path)) {
            KFCLOG_ERROR("Reports path is too long.");
            return KSCrashInstallErrorPathTooLong;
        }
        g_reportStoreConfig.reportsPath = strdup(path);
    }

    kscrs_initialize(&g_reportStoreConfig);

    if (snprintf(path, sizeof(path), "%s/Data", installPath) >= (int)sizeof(path)) {
        KFCLOG_ERROR("Data path is too long.");
        return KSCrashInstallErrorPathTooLong;
    }
    if (ksfu_makePath(path) == false) {
        KFCLOG_ERROR("Could not create path: %s", path);
        return KSCrashInstallErrorCouldNotCreatePath;
    }
    ksmemory_initialize(path);

    // Pre-allocate mmap crash buffers (zero-syscall crash writing).
    if (snprintf(g_crashMmapPath, sizeof(g_crashMmapPath), "%s/CrashBuffer.mmap", path) >=
        (int)sizeof(g_crashMmapPath)) {
        KFCLOG_ERROR("Crash mmap path is too long.");
        return KSCrashInstallErrorPathTooLong;
    }
    if (snprintf(g_recrashMmapPath, sizeof(g_recrashMmapPath), "%s/CrashBuffer.old", path) >=
        (int)sizeof(g_recrashMmapPath)) {
        KFCLOG_ERROR("Recrash mmap path is too long.");
        return KSCrashInstallErrorPathTooLong;
    }
    // Recover any reports left in mmap buffers from the previous run.
    kfcrash_recoverMmapReport(g_crashMmapPath);
    kfcrash_recoverMmapReport(g_recrashMmapPath);

    g_crashMmapBuffer = ksfu_mmap(g_crashMmapPath, KFCRASH_MMAP_BUFFER_SIZE);
    if (g_crashMmapBuffer == NULL) {
        KFCLOG_ERROR("Could not mmap crash buffer.");
        return KSCrashInstallErrorCouldNotCreatePath;
    }
    g_recrashMmapBuffer = ksfu_mmap(g_recrashMmapPath, KFCRASH_MMAP_BUFFER_SIZE);
    if (g_recrashMmapBuffer == NULL) {
        KFCLOG_ERROR("Could not mmap recrash buffer.");
        return KSCrashInstallErrorCouldNotCreatePath;
    }

    if (snprintf(path, sizeof(path), "%s/Data/CrashState.json", installPath) >= (int)sizeof(path)) {
        KFCLOG_ERROR("Crash state path is too long.");
        return KSCrashInstallErrorPathTooLong;
    }
    kfcrashstate_initialize(path);

    if (snprintf(g_consoleLogPath, sizeof(g_consoleLogPath), "%s/Data/ConsoleLog.txt", installPath) >=
        (int)sizeof(g_consoleLogPath)) {
        KFCLOG_ERROR("Console log path is too long.");
        return KSCrashInstallErrorPathTooLong;
    }
    if (g_shouldPrintPreviousLog) {
        printPreviousLog(g_consoleLogPath);
    }
    kfclog_setLogFilename(g_consoleLogPath, true);

    kfctc_init(60);

    ksbic_init();

    kfccm_setEventCallback(onExceptionEvent);
    setMonitors(configuration->monitors);
    if (kfccm_activateMonitors() == false) {
        KFCLOG_ERROR("No crash monitors are active");
        return KSCrashInstallErrorNoActiveMonitors;
    }

    g_installed = true;
    KFCLOG_DEBUG("Installation complete.");

    notifyOfBeforeInstallationState();
    return KSCrashInstallErrorNone;
}

void kfcrash_setUserInfoJSON(const char *const userInfoJSON) { kfcrashreport_setUserInfoJSON(userInfoJSON); }

const char *kfcrash_getUserInfoJSON(void) { return kfcrashreport_getUserInfoJSON(); }

void kfcrash_reportUserException(const char *name, const char *reason, const char *language, const char *lineOfCode,
                                 const char *stackTrace, bool logAllThreads,
                                 bool terminateProgram) KS_KEEP_FUNCTION_IN_STACKTRACE
{
    kfccm_reportUserException(name, reason, language, lineOfCode, stackTrace, logAllThreads, terminateProgram);
    if (g_shouldAddConsoleLogToReport) {
        kfclog_clearLogFile();
    }
    KS_THWART_TAIL_CALL_OPTIMISATION
}

void kfcrash_notifyObjCLoad(void) { kfcrashstate_notifyObjCLoad(); }

void kfcrash_notifyAppActive(bool isActive)
{
    if (g_installed) {
        kfcrashstate_notifyAppActive(isActive);
    }
    g_lastApplicationState = isActive ? KSApplicationStateDidBecomeActive : KSApplicationStateWillResignActiveActive;
}

void kfcrash_notifyAppInForeground(bool isInForeground)
{
    if (g_installed) {
        kfcrashstate_notifyAppInForeground(isInForeground);
    }
    g_lastApplicationState =
        isInForeground ? KSApplicationStateWillEnterForeground : KSApplicationStateDidEnterBackground;
}

void kfcrash_notifyAppTerminate(void)
{
    if (g_installed) {
        kfcrashstate_notifyAppTerminate();
    }
    g_lastApplicationState = KSApplicationStateWillTerminate;
}

void kfcrash_notifyAppCrash(void) { kfcrashstate_notifyAppCrash(); }

int64_t kfcrash_addUserReport(const char *report, int reportLength)
{
    return kscrs_addUserReport(report, reportLength, &g_reportStoreConfig);
}
