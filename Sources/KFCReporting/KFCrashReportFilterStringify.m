//
//  KFCrashReportFilterStringify.m
//  KFCrash
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

#import "KFCrashReportFilterStringify.h"
#import "KFCrashReport.h"

// #define KSLogger_LocalLevel TRACE
#import "KFCLogger.h"

@implementation KFCrashReportFilterStringify

- (NSString *)stringifyReport:(id<KFCrashReport>)report
{
    if ([report isKindOfClass:[KFCrashReportString class]]) {
        return ((KFCrashReportString *)report).value;
    }
    if ([report isKindOfClass:[KFCrashReportData class]]) {
        NSData *value = ((KFCrashReportData *)report).value;
        return [[NSString alloc] initWithData:value encoding:NSUTF8StringEncoding];
    }
    if ([report isKindOfClass:[KFCrashReportDictionary class]]) {
        NSDictionary *value = ((KFCrashReportDictionary *)report).value;
        if ([NSJSONSerialization isValidJSONObject:value]) {
            NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
            return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
        return [NSString stringWithFormat:@"%@", value];
    }
    return [report description] ?: @"Unknown";
}

- (void)filterReports:(NSArray<id<KFCrashReport>> *)reports onCompletion:(KFCrashReportFilterCompletion)onCompletion
{
    NSMutableArray<id<KFCrashReport>> *filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for (id<KFCrashReport> report in reports) {
        NSString *reportString = [self stringifyReport:report];
        [filteredReports addObject:[KFCrashReportString reportWithValue:reportString]];
    }

    kfcrash_callCompletion(onCompletion, filteredReports, nil);
}

@end
