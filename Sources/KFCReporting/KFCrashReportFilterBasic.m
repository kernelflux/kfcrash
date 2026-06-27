//
//  KFCrashReportFilterBasic.m
//
//  Created by Karl Stenerud on 2012-05-11.
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

#import "KFCrashReportFilterBasic.h"
#import "KFCrashReport.h"
#import "KFCNSDictionaryHelper.h"
#import "KFCNSErrorHelper.h"
#import "KFCVarArgs.h"

// #define KSLogger_LocalLevel TRACE
#import "KFCLogger.h"

@implementation KFCrashReportFilterPassthrough

- (void)filterReports:(NSArray<id<KFCrashReport>> *)reports onCompletion:(KFCrashReportFilterCompletion)onCompletion
{
    kfcrash_callCompletion(onCompletion, reports, nil);
}

@end

@interface KFCrashReportFilterCombine ()

@property(nonatomic, readwrite, copy) NSArray<id<KFCrashReportFilter>> *filters;
@property(nonatomic, readwrite, copy) NSArray<NSString *> *keys;

@end

@implementation KFCrashReportFilterCombine

- (instancetype)initWithFilters:(NSDictionary<NSString *, id<KFCrashReportFilter>> *)filterDictionary
{
    if ((self = [super init])) {
        _filters = [filterDictionary.allValues copy];
        _keys = [filterDictionary.allKeys copy];
    }
    return self;
}

- (void)filterReports:(NSArray<id<KFCrashReport>> *)reports onCompletion:(KFCrashReportFilterCompletion)onCompletion
{
    NSArray *filters = self.filters;
    NSArray *keys = self.keys;
    NSUInteger filterCount = [filters count];

    if (filterCount == 0) {
        kfcrash_callCompletion(onCompletion, reports, nil);
        return;
    }

    if (filterCount != [keys count]) {
        kfcrash_callCompletion(
            onCompletion, reports,
            [KSNSErrorHelper errorWithDomain:[[self class] description]
                                        code:0
                                 description:@"Key/filter mismatch (%d keys, %d filters", [keys count], filterCount]);
        return;
    }

    NSMutableArray *reportSets = [NSMutableArray arrayWithCapacity:filterCount];

    __block NSUInteger iFilter = 0;
    __block KFCrashReportFilterCompletion filterCompletion = nil;
    __block __unsafe_unretained KFCrashReportFilterCompletion weakFilterCompletion = nil;
    dispatch_block_t disposeOfCompletion = [^{
        // Release self-reference on the main thread.
        dispatch_async(dispatch_get_main_queue(), ^{
            filterCompletion = nil;
        });
    } copy];
    filterCompletion = [^(NSArray<id<KFCrashReport>> *filteredReports, NSError *filterError) {
        if (filterError != nil || filteredReports == nil) {
            if (filterError != nil) {
                kfcrash_callCompletion(onCompletion, filteredReports, filterError);
            } else if (filteredReports == nil) {
                kfcrash_callCompletion(onCompletion, filteredReports,
                                       [KSNSErrorHelper errorWithDomain:[[self class] description]
                                                                   code:0
                                                            description:@"filteredReports was nil"]);
            }
            disposeOfCompletion();
            return;
        }

        // Normal run until all filters exhausted.
        [reportSets addObject:filteredReports];
        if (++iFilter < filterCount) {
            id<KFCrashReportFilter> filter = [filters objectAtIndex:iFilter];
            [filter filterReports:reports onCompletion:weakFilterCompletion];
            return;
        }

        // All filters complete, or a filter failed.
        // Build final "filteredReports" array.
        NSUInteger reportCount = [(NSArray *)[reportSets objectAtIndex:0] count];
        NSMutableArray<id<KFCrashReport>> *combinedReports = [NSMutableArray arrayWithCapacity:reportCount];
        for (NSUInteger iReport = 0; iReport < reportCount; iReport++) {
            NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:filterCount];
            for (NSUInteger iSet = 0; iSet < filterCount; iSet++) {
                NSString *key = keys[iSet];
                NSArray *reportSet = reportSets[iSet];
                if (iReport < reportSet.count) {
                    id<KFCrashReport> report = reportSet[iReport];
                    dict[key] = report.untypedValue;
                }
            }
            id<KFCrashReport> report = [KFCrashReportDictionary reportWithValue:dict];
            [combinedReports addObject:report];
        }

        kfcrash_callCompletion(onCompletion, combinedReports, filterError);
        disposeOfCompletion();
    } copy];
    weakFilterCompletion = filterCompletion;

    // Initial call with first filter to start everything going.
    id<KFCrashReportFilter> filter = [filters objectAtIndex:iFilter];
    [filter filterReports:reports onCompletion:filterCompletion];
}

@end

@interface KFCrashReportFilterPipeline ()

@property(nonatomic, readwrite, copy) NSArray<id<KFCrashReportFilter>> *filters;

@end

@implementation KFCrashReportFilterPipeline

- (instancetype)initWithFilters:(NSArray<id<KFCrashReportFilter>> *)filters
{
    if ((self = [super init])) {
        _filters = [filters copy];
    }
    return self;
}

- (void)addFilter:(id<KFCrashReportFilter>)filter
{
    self.filters = [@[ filter ] arrayByAddingObjectsFromArray:self.filters];
}

- (void)filterReports:(NSArray<id<KFCrashReport>> *)reports onCompletion:(KFCrashReportFilterCompletion)onCompletion
{
    NSArray *filters = self.filters;
    NSUInteger filterCount = [filters count];

    if (filterCount == 0) {
        kfcrash_callCompletion(onCompletion, reports, nil);
        return;
    }

    __block NSUInteger iFilter = 0;
    __block KFCrashReportFilterCompletion filterCompletion;
    __block __unsafe_unretained KFCrashReportFilterCompletion weakFilterCompletion = nil;
    dispatch_block_t disposeOfCompletion = [^{
        // Release self-reference on the main thread.
        dispatch_async(dispatch_get_main_queue(), ^{
            filterCompletion = nil;
        });
    } copy];
    filterCompletion = [^(NSArray<id<KFCrashReport>> *filteredReports, NSError *filterError) {
        if (filterError != nil || filteredReports == nil) {
            if (filterError != nil) {
                kfcrash_callCompletion(onCompletion, filteredReports, filterError);
            } else if (filteredReports == nil) {
                kfcrash_callCompletion(onCompletion, filteredReports,
                                       [KSNSErrorHelper errorWithDomain:[[self class] description]
                                                                   code:0
                                                            description:@"filteredReports was nil"]);
            }
            disposeOfCompletion();
            return;
        }

        // Normal run until all filters exhausted or one
        // filter fails to complete.
        if (++iFilter < filterCount) {
            id<KFCrashReportFilter> filter = [filters objectAtIndex:iFilter];
            [filter filterReports:filteredReports onCompletion:weakFilterCompletion];
            return;
        }

        // All filters complete, or a filter failed.
        kfcrash_callCompletion(onCompletion, filteredReports, filterError);
        disposeOfCompletion();
    } copy];
    weakFilterCompletion = filterCompletion;

    // Initial call with first filter to start everything going.
    id<KFCrashReportFilter> filter = [filters objectAtIndex:iFilter];
    [filter filterReports:reports onCompletion:filterCompletion];
}

@end

@interface KFCrashReportFilterConcatenate ()

@property(nonatomic, readwrite, copy) NSString *separatorFmt;
@property(nonatomic, readwrite, copy) NSArray<NSString *> *keys;

@end

@implementation KFCrashReportFilterConcatenate

- (instancetype)initWithSeparatorFmt:(NSString *)separatorFmt keys:(NSArray<NSString *> *)keys
{
    if ((self = [super init])) {
        NSMutableArray *realKeys = [NSMutableArray array];
        for (id key in keys) {
            if ([key isKindOfClass:[NSArray class]]) {
                [realKeys addObjectsFromArray:(NSArray *)key];
            } else {
                [realKeys addObject:key];
            }
        }

        _separatorFmt = [separatorFmt copy];
        _keys = [realKeys copy];
    }
    return self;
}

- (void)filterReports:(NSArray<id<KFCrashReport>> *)reports onCompletion:(KFCrashReportFilterCompletion)onCompletion
{
    NSMutableArray *filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for (KFCrashReportDictionary *report in reports) {
        if ([report isKindOfClass:[KFCrashReportDictionary class]] == NO) {
            KFCLOG_ERROR(@"Unexpected non-dictionary report: %@", report);
            continue;
        }
        BOOL firstEntry = YES;
        NSMutableString *concatenated = [NSMutableString string];
        for (NSString *key in self.keys) {
            if (firstEntry) {
                firstEntry = NO;
            } else {
                [concatenated appendFormat:self.separatorFmt, key];
            }
            id object = [KFCNSDictionaryHelper objectInDictionary:report.value forKeyPath:key];
            [concatenated appendFormat:@"%@", object];
        }
        [filteredReports addObject:[KFCrashReportString reportWithValue:concatenated]];
    }
    kfcrash_callCompletion(onCompletion, filteredReports, nil);
}

@end

@interface KFCrashReportFilterSubset ()

@property(nonatomic, readwrite, copy) NSArray *keyPaths;

@end

@implementation KFCrashReportFilterSubset

- (instancetype)initWithKeys:(NSArray<NSString *> *)keyPaths
{
    if ((self = [super init])) {
        NSMutableArray *realKeyPaths = [NSMutableArray array];
        for (id keyPath in keyPaths) {
            if ([keyPath isKindOfClass:[NSArray class]]) {
                [realKeyPaths addObjectsFromArray:(NSArray *)keyPath];
            } else {
                [realKeyPaths addObject:keyPath];
            }
        }

        _keyPaths = [realKeyPaths copy];
    }
    return self;
}

- (void)filterReports:(NSArray<id<KFCrashReport>> *)reports onCompletion:(KFCrashReportFilterCompletion)onCompletion
{
    NSMutableArray<id<KFCrashReport>> *filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for (KFCrashReportDictionary *report in reports) {
        if ([report isKindOfClass:[KFCrashReportDictionary class]] == NO) {
            KFCLOG_ERROR(@"Unexpected non-dictionary report: %@", report);
            continue;
        }

        NSMutableDictionary *subset = [NSMutableDictionary dictionary];
        for (NSString *keyPath in self.keyPaths) {
            id object = [KFCNSDictionaryHelper objectInDictionary:report.value forKeyPath:keyPath];
            if (object == nil) {
                kfcrash_callCompletion(onCompletion, filteredReports,
                                       [KSNSErrorHelper errorWithDomain:[[self class] description]
                                                                   code:0
                                                            description:@"Report did not have key path %@", keyPath]);
                return;
            }
            [subset setObject:object forKey:[keyPath lastPathComponent]];
        }
        id<KFCrashReport> subsetReport = [KFCrashReportDictionary reportWithValue:subset];
        [filteredReports addObject:subsetReport];
    }
    kfcrash_callCompletion(onCompletion, filteredReports, nil);
}

@end

@implementation KFCrashReportFilterDataToString

- (void)filterReports:(NSArray<id<KFCrashReport>> *)reports onCompletion:(KFCrashReportFilterCompletion)onCompletion
{
    NSMutableArray<id<KFCrashReport>> *filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for (KFCrashReportData *report in reports) {
        if ([report isKindOfClass:[KFCrashReportData class]] == NO) {
            KFCLOG_ERROR(@"Unexpected non-data report: %@", report);
            continue;
        }

        NSString *converted = [[NSString alloc] initWithData:report.value encoding:NSUTF8StringEncoding];
        if (converted == nil) {
            KFCLOG_ERROR(@"Can't decode UTF8 string from binary data: %@", report);
            continue;
        }
        [filteredReports addObject:[KFCrashReportString reportWithValue:converted]];
    }

    kfcrash_callCompletion(onCompletion, filteredReports, nil);
}

@end

@implementation KFCrashReportFilterStringToData

- (void)filterReports:(NSArray<id<KFCrashReport>> *)reports onCompletion:(KFCrashReportFilterCompletion)onCompletion
{
    NSMutableArray<id<KFCrashReport>> *filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for (KFCrashReportString *report in reports) {
        if ([report isKindOfClass:[KFCrashReportString class]] == NO) {
            KFCLOG_ERROR(@"Unexpected non-string report: %@", report);
            continue;
        }

        NSData *converted = [report.value dataUsingEncoding:NSUTF8StringEncoding];
        if (converted == nil) {
            kfcrash_callCompletion(onCompletion, filteredReports,
                                   [KSNSErrorHelper errorWithDomain:[[self class] description]
                                                               code:0
                                                        description:@"Could not convert report to UTF-8"]);
            return;
        } else {
            [filteredReports addObject:[KFCrashReportData reportWithValue:converted]];
        }
    }

    kfcrash_callCompletion(onCompletion, filteredReports, nil);
}

@end
