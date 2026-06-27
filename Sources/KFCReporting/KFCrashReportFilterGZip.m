//
//  KFCrashReportFilterGZip.m
//
//  Created by Karl Stenerud on 2012-05-10.
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

#import "KFCrashReportFilterGZip.h"
#import "KFCrashReport.h"
#import "KFCGZipHelper.h"

// #define KSLogger_LocalLevel TRACE
#import "KFCLogger.h"

@interface KFCrashReportFilterGZipCompress ()

@property(nonatomic, readwrite, assign) NSInteger compressionLevel;

@end

@implementation KFCrashReportFilterGZipCompress

- (instancetype)initWithCompressionLevel:(NSInteger)compressionLevel
{
    if ((self = [super init])) {
        _compressionLevel = compressionLevel;
    }
    return self;
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
        NSData *compressedData = [KFCGZipHelper gzippedData:report.value
                                          compressionLevel:(int)self.compressionLevel
                                                     error:&error];
        if (compressedData == nil) {
            kfcrash_callCompletion(onCompletion, filteredReports, error);
            return;
        } else {
            [filteredReports addObject:[KFCrashReportData reportWithValue:compressedData]];
        }
    }

    kfcrash_callCompletion(onCompletion, filteredReports, nil);
}

@end

@implementation KFCrashReportFilterGZipDecompress

- (void)filterReports:(NSArray<id<KFCrashReport>> *)reports onCompletion:(KFCrashReportFilterCompletion)onCompletion
{
    NSMutableArray<id<KFCrashReport>> *filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for (KFCrashReportData *report in reports) {
        if ([report isKindOfClass:[KFCrashReportData class]] == NO) {
            KFCLOG_ERROR(@"Unexpected non-data report: %@", report);
            continue;
        }

        NSError *error = nil;
        NSData *decompressedData = [KFCGZipHelper gunzippedData:report.value error:&error];
        if (decompressedData == nil) {
            kfcrash_callCompletion(onCompletion, filteredReports, error);
            return;
        } else {
            [filteredReports addObject:[KFCrashReportData reportWithValue:decompressedData]];
        }
    }

    kfcrash_callCompletion(onCompletion, filteredReports, nil);
}

@end
