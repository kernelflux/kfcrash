//
//  KFCrashReportStore.m
//
//  Created by Nikolay Volosatov on 2024-08-28.
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

#import "KFCrashReportStore.h"

#import "KFCrash+Private.h"
#import "KFCrashConfiguration+Private.h"
#import "KFCrashReport.h"
#import "KFCrashReportFields.h"
#import "KFCrashReportFilter.h"
#import "KFCrashReportStoreC.h"
#import "KFCJSONCodecObjC.h"
#import "KFCNSErrorHelper.h"

// #define KSLogger_LocalLevel TRACE
#import "KFCLogger.h"

@implementation KFCrashReportStore {
    KFCrashReportStoreCConfiguration _cConfig;
}

+ (NSString *)defaultInstallSubfolder
{
    return @KSCRS_DEFAULT_REPORTS_FOLDER;
}

+ (instancetype)defaultStoreWithError:(NSError **)error
{
    return [KFCrashReportStore storeWithConfiguration:nil error:error];
}

+ (instancetype)storeWithConfiguration:(KFCrashReportStoreConfiguration *)configuration error:(NSError **)error
{
    return [[KFCrashReportStore alloc] initWithConfiguration:configuration error:error];
}

- (nullable instancetype)initWithConfiguration:(KFCrashReportStoreConfiguration *)configuration error:(NSError **)error
{
    self = [super init];
    if (self != nil) {
        KFCrashReportStoreConfiguration *resolvedConfiguration = configuration ?: [KFCrashReportStoreConfiguration new];
        _cConfig = [resolvedConfiguration toCConfiguration];
        _reportCleanupPolicy = resolvedConfiguration.reportCleanupPolicy;

        kscrs_initialize(&_cConfig);
    }
    return self;
}

- (void)dealloc
{
    KFCrashReportStoreCConfiguration_Release(&_cConfig);
}

- (NSInteger)reportCount
{
    return kscrs_getReportCount(&_cConfig);
}

- (void)sendAllReportsWithCompletion:(KFCrashReportFilterCompletion)onCompletion
{
    NSArray *reports = [self allReports];

    KFCLOG_INFO(@"Sending %d crash reports", [reports count]);

    __unsafe_unretained __typeof(self) weakSelf = self;
    [self sendReports:reports
         onCompletion:^(NSArray *filteredReports, NSError *error) {
             KFCLOG_DEBUG(@"Process finished");
             if (error != nil) {
                 KFCLOG_ERROR(@"Failed to send reports: %@", error);
             }
             if ((self.reportCleanupPolicy == KFCrashReportCleanupPolicyOnSuccess && error == nil) ||
                 self.reportCleanupPolicy == KFCrashReportCleanupPolicyAlways) {
                 [weakSelf deleteAllReports];
             }
             kfcrash_callCompletion(onCompletion, filteredReports, error);
         }];
}

- (void)deleteAllReports
{
    kscrs_deleteAllReports(&_cConfig);
}

- (void)deleteReportWithID:(int64_t)reportID
{
    kscrs_deleteReportWithID(reportID, &_cConfig);
}

#pragma mark - Private API

- (void)sendReports:(NSArray<id<KFCrashReport>> *)reports onCompletion:(KFCrashReportFilterCompletion)onCompletion
{
    if ([reports count] == 0) {
        kfcrash_callCompletion(onCompletion, reports, nil);
        return;
    }

    if (self.sink == nil) {
        kfcrash_callCompletion(onCompletion, reports,
                               [KSNSErrorHelper errorWithDomain:[[self class] description]
                                                           code:0
                                                    description:@"No sink set. Crash reports not sent."]);
        return;
    }

    [self.sink filterReports:reports
                onCompletion:^(NSArray *filteredReports, NSError *error) {
                    kfcrash_callCompletion(onCompletion, filteredReports, error);
                }];
}

- (NSData *)loadCrashReportJSONWithID:(int64_t)reportID
{
    char *report = kscrs_readReport(reportID, &_cConfig);
    if (report != NULL) {
        return [NSData dataWithBytesNoCopy:report length:strlen(report) freeWhenDone:YES];
    }
    return nil;
}

- (NSArray<NSNumber *> *)reportIDs
{
    int reportCount = kscrs_getReportCount(&_cConfig);
    if (reportCount <= 0) {
        return @[];
    }
    int64_t *reportIDsC = malloc(sizeof(int64_t) * (size_t)reportCount);
    if (!reportIDsC) {
        return @[];
    }
    reportCount = kscrs_getReportIDs(reportIDsC, reportCount, &_cConfig);
    NSMutableArray *reportIDs = [NSMutableArray arrayWithCapacity:(NSUInteger)reportCount];
    for (int i = 0; i < reportCount; i++) {
        [reportIDs addObject:[NSNumber numberWithLongLong:reportIDsC[i]]];
    }
    free(reportIDsC);
    return [reportIDs copy];
}

- (KFCrashReportDictionary *)reportForID:(int64_t)reportID
{
    NSData *jsonData = [self loadCrashReportJSONWithID:reportID];
    if (jsonData == nil) {
        return nil;
    }

    NSError *error = nil;
    NSMutableDictionary *crashReport =
        [KFCJSONCodec decode:jsonData
                    options:KSJSONDecodeOptionIgnoreNullInArray | KSJSONDecodeOptionIgnoreNullInObject |
                            KSJSONDecodeOptionKeepPartialObject
                      error:&error];
    if (error != nil) {
        KFCLOG_ERROR(@"Encountered error loading crash report %" PRIx64 ": %@", reportID, error);
    }
    if (crashReport == nil) {
        KFCLOG_ERROR(@"Could not load crash report");
        return nil;
    }

    return [KFCrashReportDictionary reportWithValue:crashReport];
}

- (NSString *)reportStringForID:(int64_t)reportID
{
    NSData *jsonData = [self loadCrashReportJSONWithID:reportID];
    if (jsonData == nil) {
        return nil;
    }
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (NSArray<KFCrashReportDictionary *> *)allReports
{
    int reportCount = kscrs_getReportCount(&_cConfig);
    int64_t reportIDs[reportCount];
    reportCount = kscrs_getReportIDs(reportIDs, reportCount, &_cConfig);
    NSMutableArray<KFCrashReportDictionary *> *reports = [NSMutableArray arrayWithCapacity:(NSUInteger)reportCount];
    for (int i = 0; i < reportCount; i++) {
        KFCrashReportDictionary *report = [self reportForID:reportIDs[i]];
        if (report != nil) {
            [reports addObject:report];
        }
    }

    return reports;
}

@end
