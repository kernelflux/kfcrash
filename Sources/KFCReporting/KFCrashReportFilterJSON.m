//
//  KFCrashReportFilterJSON.m
//
//  Created by Karl Stenerud on 2012-05-09.
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

#import "KFCrashReportFilterJSON.h"
#import "KFCrashReport.h"

// #define KSLogger_LocalLevel TRACE
#import "KFCLogger.h"

@interface KFCrashReportFilterJSONEncode ()

@property(nonatomic, readwrite, assign) KSJSONEncodeOption encodeOptions;

@end

@implementation KFCrashReportFilterJSONEncode

- (instancetype)initWithOptions:(KSJSONEncodeOption)options
{
    if ((self = [super init])) {
        _encodeOptions = options;
    }
    return self;
}

- (instancetype)init
{
    return [self initWithOptions:KSJSONEncodeOptionNone];
}

- (void)filterReports:(NSArray<id<KFCrashReport>> *)reports onCompletion:(KFCrashReportFilterCompletion)onCompletion
{
    NSMutableArray<id<KFCrashReport>> *filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for (KFCrashReportDictionary *report in reports) {
        if ([report isKindOfClass:[KFCrashReportDictionary class]] == NO) {
            KFCLOG_ERROR(@"Unexpected non-dictionary report: %@", report);
            continue;
        }

        NSError *error = nil;
        NSData *jsonData = [KFCJSONCodec encode:report.value options:self.encodeOptions error:&error];
        if (jsonData == nil) {
            kfcrash_callCompletion(onCompletion, filteredReports, error);
            return;
        } else {
            [filteredReports addObject:[KFCrashReportData reportWithValue:jsonData]];
        }
    }

    kfcrash_callCompletion(onCompletion, filteredReports, nil);
}

@end

@interface KFCrashReportFilterJSONDecode ()

@property(nonatomic, readwrite, assign) KSJSONDecodeOption decodeOptions;

@end

@implementation KFCrashReportFilterJSONDecode

- (instancetype)initWithOptions:(KSJSONDecodeOption)options
{
    if ((self = [super init])) {
        _decodeOptions = options;
    }
    return self;
}

- (instancetype)init
{
    return [self initWithOptions:KSJSONDecodeOptionNone];
}

- (void)filterReports:(NSArray<id<KFCrashReport>> *)reports onCompletion:(KFCrashReportFilterCompletion)onCompletion
{
    NSMutableArray<id<KFCrashReport>> *filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for (KFCrashReportData *report in reports) {
        if ([report isKindOfClass:[KFCrashReportData class]] == NO) {
            KFCLOG_ERROR(@"Unexpected non-data report: %@", report);
            continue;
        }

        NSError *error = nil;
        NSDictionary *decodedReport = [KFCJSONCodec decode:report.value options:self.decodeOptions error:&error];
        if (decodedReport == nil || [decodedReport isKindOfClass:[NSDictionary class]] == NO) {
            kfcrash_callCompletion(onCompletion, filteredReports, error);
            return;
        } else {
            [filteredReports addObject:[KFCrashReportDictionary reportWithValue:decodedReport]];
        }
    }

    kfcrash_callCompletion(onCompletion, filteredReports, nil);
}

@end
