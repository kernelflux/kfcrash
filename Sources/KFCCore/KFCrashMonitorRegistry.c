//
//  KFCrashMonitorRegistry.c
//
//  Created by Karl Stenerud on 2025-08-09.
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

#include "KFCrashMonitorRegistry.h"

#include <stdatomic.h>

#include "KFCDebug.h"

// #define KFCLogger_LocalLevel TRACE
#include "KFCLogger.h"

bool kfccmr_addMonitor(KFCrashMonitorAPIList *monitorList, const KFCrashMonitorAPI *api)
{
    if (api == NULL) {
        return false;
    }

    bool added = false;
    for (size_t i = 0; i < KFCRASH_MONITOR_API_COUNT; i++) {
        if (atomic_load(monitorList->apis + i) == api) {
            KFCLOG_DEBUG("Monitor %s already exists. Skipping addition.", api->monitorId());
            return false;
        }

        // Make sure we're swapping from null to our API, and not something else that got swapped in meanwhile.
        const KFCrashMonitorAPI *expectedAPI = NULL;
        if (atomic_compare_exchange_strong(monitorList->apis + i, &expectedAPI, api)) {
            added = true;
            break;
        }
    }

    if (!added) {
        // This should never happen, but never say never!
        KFCLOG_ERROR("Failed to add monitor API \"%s\"", api->monitorId());
        return false;
    }

    // Check for and remove duplicates in case another thread also just added the same API.
    bool found = false;
    for (size_t i = 0; i < KFCRASH_MONITOR_API_COUNT; i++) {
        if (atomic_load(monitorList->apis + i) == api) {
            if (!found) {
                // Leave the first copy alone.
                found = true;
            } else {
                // Make sure we're swapping from our API to null, and not something else that got swapped in meanwhile.
                const KFCrashMonitorAPI *expectedAPI = api;
                atomic_compare_exchange_strong(monitorList->apis + i, &expectedAPI, NULL);
            }
        }
    }

    KFCLOG_DEBUG("Monitor %s injected.", api->monitorId());
    return true;
}

void kfccmr_removeMonitor(KFCrashMonitorAPIList *monitorList, const KFCrashMonitorAPI *api)
{
    if (api == NULL) {
        return;
    }

    for (size_t i = 0; i < KFCRASH_MONITOR_API_COUNT; i++) {
        // Make sure we're swapping from our API to null, and not something else that got swapped in meanwhile.
        const KFCrashMonitorAPI *expectedAPI = api;
        if (atomic_compare_exchange_strong(monitorList->apis + i, &expectedAPI, NULL)) {
            api->setEnabled(false);
        }
    }
}

bool kfccmr_activateMonitors(KFCrashMonitorAPIList *monitorList)
{
    // Check for debugger and async safety
    bool isDebuggerUnsafe = ksdebug_isBeingTraced();

    if (isDebuggerUnsafe) {
        static bool hasWarned = false;
        if (!hasWarned) {
            hasWarned = true;
            KFCLOGBASIC_WARN("    ************************ Crash Handler Notice ************************");
            KFCLOGBASIC_WARN("    *     App is running in a debugger. Masking out unsafe monitors.     *");
            KFCLOGBASIC_WARN("    * This means that most crashes WILL NOT BE RECORDED while debugging! *");
            KFCLOGBASIC_WARN("    **********************************************************************");
        }
    }

    // Enable or disable monitors
    bool anyMonitorActive = false;
    for (size_t i = 0; i < KFCRASH_MONITOR_API_COUNT; i++) {
        const KFCrashMonitorAPI *api = monitorList->apis[i];
        if (api == NULL) {
            // Found a hole. Skip it.
            continue;
        }
        KFCrashMonitorFlag flags = api->monitorFlags();
        bool shouldEnable = true;

        if (isDebuggerUnsafe && (flags & KFCrashMonitorFlagDebuggerUnsafe)) {
            shouldEnable = false;
        }

        api->setEnabled(shouldEnable);
        bool isEnabled = api->isEnabled();
        anyMonitorActive |= isEnabled;
        KFCLOG_DEBUG("Monitor %s is now %sabled.", api->monitorId(), isEnabled ? "en" : "dis");
    }

    for (size_t i = 0; i < KFCRASH_MONITOR_API_COUNT; i++) {
        const KFCrashMonitorAPI *api = monitorList->apis[i];
        if (api != NULL && api->isEnabled()) {
            api->notifyPostSystemEnable();
        }
    }

    return anyMonitorActive;
}

void kfccmr_disableAllMonitors(KFCrashMonitorAPIList *monitorList)
{
    for (size_t i = 0; i < KFCRASH_MONITOR_API_COUNT; i++) {
        const KFCrashMonitorAPI *api = monitorList->apis[i];
        if (api != NULL) {
            api->setEnabled(false);
        }
    }
    KFCLOG_DEBUG("All monitors have been disabled.");
}

void kfccmr_addContextualInfoToEvent(KFCrashMonitorAPIList *monitorList, struct KFCrash_MonitorContext *ctx)
{
    for (size_t i = 0; i < KFCRASH_MONITOR_API_COUNT; i++) {
        const KFCrashMonitorAPI *api = monitorList->apis[i];
        if (api != NULL && api->isEnabled()) {
            api->addContextualInfoToEvent(ctx);
        }
    }
}

