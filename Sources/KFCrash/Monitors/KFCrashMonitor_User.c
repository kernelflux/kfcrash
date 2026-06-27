//
//  KFCrashMonitor_User.c
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

#include "KFCrashMonitor_User.h"

#include "KFCCompilerDefines.h"
#include "KFCrashMonitorContext.h"
#include "KFCrashMonitorHelper.h"
#include "KFCID.h"
#include "KFCStackCursor_SelfThread.h"
#include "KFCThread.h"

// #define KSLogger_LocalLevel TRACE
#include <memory.h>
#include <stdlib.h>

#include "KFCLogger.h"

/** Context to fill with crash information. */

static volatile bool g_isEnabled = false;

static KFCrash_ExceptionHandlerCallbacks g_callbacks;

void kfccm_reportUserException(const char *name, const char *reason, const char *language, const char *lineOfCode,
                              const char *stackTrace, bool logAllThreads,
                              bool terminateProgram) KS_KEEP_FUNCTION_IN_STACKTRACE
{
    if (!g_isEnabled) {
        KFCLOG_WARN("User-reported exception monitor is not installed. Exception has not been recorded.");
        return;
    }

    thread_t thisThread = (thread_t)kfcthread_self();
    KFCrash_MonitorContext *ctx = g_callbacks.notify(
        thisThread, (KFCrash_ExceptionHandlingRequirements) { .asyncSafety = false,
                                                              .isFatal = terminateProgram,
                                                              .shouldRecordAllThreads = logAllThreads,
                                                              .shouldWriteReport = true });
    if (ctx->requirements.shouldExitImmediately) {
        goto exit_immediately;
    }

    KSMachineContext machineContext = { 0 };
    ksmc_getContextForThread(thisThread, &machineContext, true);
    KSStackCursor stackCursor;
    kssc_initSelfThread(&stackCursor, 3);

    KFCLOG_DEBUG("Filling out context.");
    kfccm_fillMonitorContext(ctx, kfccm_user_getAPI());
    ctx->offendingMachineContext = &machineContext;
    ctx->registersAreValid = false;
    ctx->crashReason = reason;
    ctx->userException.name = name;
    ctx->userException.language = language;
    ctx->userException.lineOfCode = lineOfCode;
    ctx->userException.customStackTrace = stackTrace;
    ctx->stackCursor = &stackCursor;
    ctx->currentSnapshotUserReported = true;

    g_callbacks.handle(ctx);

exit_immediately:
    if (terminateProgram) {
        kfccm_exit(1, kfccexc_requiresAsyncSafety(ctx->requirements));
    }

    KS_THWART_TAIL_CALL_OPTIMISATION
}

static const char *monitorId(void) { return "UserReported"; }

static void setEnabled(bool isEnabled) { g_isEnabled = isEnabled; }

static bool isEnabled(void) { return g_isEnabled; }

static void init(KFCrash_ExceptionHandlerCallbacks *callbacks) { g_callbacks = *callbacks; }

KFCrashMonitorAPI *kfccm_user_getAPI(void)
{
    static KFCrashMonitorAPI api = { 0 };
    if (kfccma_initAPI(&api)) {
        api.init = init;
        api.monitorId = monitorId;
        api.setEnabled = setEnabled;
        api.isEnabled = isEnabled;
    }
    return &api;
}
