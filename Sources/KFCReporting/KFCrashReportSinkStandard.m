//
//  KFCrashReportSinkStandard.m
//
//  Created by Karl Stenerud on 2012-02-18.
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

#import "KFCrashReportSinkStandard.h"

#import "KFCrashReport.h"
#import "KFCGZipHelper.h"
#import "KFCHTTPMultipartPostBody.h"
#import "KFCHTTPRequestSender.h"
#import "KFCJSONCodecObjC.h"
#import "KFCReachabilityKFCrash.h"

// #define KSLogger_LocalLevel TRACE
#import "KFCLogger.h"

@interface KFCrashReportSinkStandard ()

@property(nonatomic, readwrite, strong) NSURL *url;
@property(nonatomic, readwrite, copy, nullable) NSDictionary<NSString *, NSString *> *headers;
@property(nonatomic, readwrite, assign) NSTimeInterval timeout;

@property(nonatomic, readwrite, strong) KSReachableOperationKSCrash *reachableOperation;

@end

@implementation KFCrashReportSinkStandard

- (instancetype)initWithURL:(NSURL *)url
{
    return [self initWithURL:url headers:nil timeout:15];
}

- (instancetype)initWithURL:(NSURL *)url
                    headers:(NSDictionary<NSString *, NSString *> *)headers
                    timeout:(NSTimeInterval)timeout
{
    if ((self = [super init])) {
        _url = url;
        _headers = [headers copy];
        _timeout = timeout;
    }
    return self;
}

- (id<KFCrashReportFilter>)defaultCrashReportFilterSet
{
    return self;
}

- (void)filterReports:(NSArray<id<KFCrashReport>> *)reports onCompletion:(KFCrashReportFilterCompletion)onCompletion
{
    NSError *error = nil;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:self.timeout];
    KFCHTTPMultipartPostBody *body = [KFCHTTPMultipartPostBody body];
    NSMutableArray *jsonArray = [NSMutableArray array];
    for (id<KFCrashReport> report in reports) {
        if ([report isKindOfClass:[KFCrashReportDictionary class]]) {
            KFCrashReportDictionary *dReport = report;
            if (dReport.value != nil) {
                [jsonArray addObject:dReport.value];
            }
        } else if ([report isKindOfClass:[KFCrashReportString class]]) {
            KFCrashReportString *sReport = report;
            if (sReport.value != nil) {
                [jsonArray addObject:sReport.value];
            }
        } else {
            KFCLOG_ERROR(@"Unexpected non-dictionary/non-string report: %@", report);
        }
    }
    NSData *jsonData = [KFCJSONCodec encode:jsonArray options:KSJSONEncodeOptionSorted error:&error];
    if (jsonData == nil) {
        kfcrash_callCompletion(onCompletion, reports, error);
        return;
    }

    [body appendData:jsonData name:@"reports" contentType:@"application/json" filename:@"reports.json"];
    // TODO: Disabled gzip compression until support is added server side,
    // and I've fixed a bug in appendUTF8String.
    //    [body appendUTF8String:@"json"
    //                      name:@"encoding"
    //               contentType:@"string"
    //                  filename:nil];

    request.HTTPMethod = @"POST";
    request.HTTPBody = [body data];
    [request setValue:body.contentType forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"KFCrashReporter" forHTTPHeaderField:@"User-Agent"];
    for (NSString *headerName in self.headers) {
        [request setValue:self.headers[headerName] forHTTPHeaderField:headerName];
    }

    //    [request setHTTPBody:[[body data] gzippedWithError:nil]];
    //    [request setValue:@"gzip" forHTTPHeaderField:@"Content-Encoding"];

    self.reachableOperation = [KSReachableOperationKSCrash
        operationWithHost:[self.url host]
                allowWWAN:YES
                    block:^{
                        [[KFCHTTPRequestSender sender] sendRequest:request
                            onSuccess:^(__unused NSHTTPURLResponse *response, __unused NSData *data) {
                                kfcrash_callCompletion(onCompletion, reports, nil);
                            }
                            onFailure:^(NSHTTPURLResponse *response, NSData *data) {
                                NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                                kfcrash_callCompletion(
                                    onCompletion, reports,
                                    [NSError
                                        errorWithDomain:[[self class] description]
                                                   code:response.statusCode
                                               userInfo:[NSDictionary dictionaryWithObject:text
                                                                                    forKey:NSLocalizedDescriptionKey]]);
                            }
                            onError:^(NSError *error2) {
                                kfcrash_callCompletion(onCompletion, reports, error2);
                            }];
                    }];
}

@end
