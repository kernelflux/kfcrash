//
//  KFCrashExceptionHandlingPlan+Private.h
//
//  Created by Karl Stenerud on 2025-08-24.
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

#ifndef HDR_KFCrashExceptionHandlingPlanPrivate_h
#define HDR_KFCrashExceptionHandlingPlanPrivate_h

#include "KFCrashExceptionHandlingPlan.h"
#include "KFCrashMonitorContext.h"

static inline KFCrash_ExceptionHandlingPlan kfcexc_monitorContextToPlan(const KFCrash_MonitorContext *const context)
{
    return (KFCrash_ExceptionHandlingPlan) {
        .shouldRecordAllThreads = context->requirements.shouldRecordAllThreads,
        .shouldWriteReport = context->requirements.shouldWriteReport,
        .isFatal = context->requirements.isFatal,
        .requiresAsyncSafety = kfccexc_requiresAsyncSafety(context->requirements),
        .crashedDuringExceptionHandling = context->requirements.crashedDuringExceptionHandling,
    };
}

static inline void kfcexc_modifyMonitorContextUsingPlan(KFCrash_MonitorContext *const context,
                                                       KFCrash_ExceptionHandlingPlan *plan)
{
    context->requirements.shouldRecordAllThreads = plan->shouldRecordAllThreads;
    context->requirements.shouldWriteReport = plan->shouldWriteReport;
}

#endif  // HDR_KFCrashExceptionHandlingPlanPrivate_h
