//
//  KFCrashInstallationConsole.m
//  KFCrash-iOS
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

#import "KFCrashInstallationConsole.h"
#import "KFCrashInstallation+Private.h"
#import "KFCrashReportFilterAppleFmt.h"
#import "KFCrashReportFilterBasic.h"
#import "KFCrashReportFilterJSON.h"
#import "KFCrashReportFilterStringify.h"
#import "KFCrashReportSinkConsole.h"

@implementation KFCrashInstallationConsole

+ (instancetype)sharedInstance
{
    static KFCrashInstallationConsole *sharedInstance = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        sharedInstance = [[KFCrashInstallationConsole alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _printAppleFormat = NO;
    }
    return self;
}

- (id<KFCrashReportFilter>)sink
{
    id<KFCrashReportFilter> formatFilter;
    if (self.printAppleFormat) {
        formatFilter = [[KFCrashReportFilterAppleFmt alloc] initWithReportStyle:KSAppleReportStyleSymbolicated];
    } else {
        formatFilter = [[KFCrashReportFilterPipeline alloc] initWithFilters:@[
            [[KFCrashReportFilterJSONEncode alloc] initWithOptions:KSJSONEncodeOptionPretty | KSJSONEncodeOptionSorted],
            [KFCrashReportFilterStringify new],
        ]];
    }

    return [[KFCrashReportFilterPipeline alloc] initWithFilters:@[ formatFilter, [KFCrashReportSinkConsole new] ]];
}

@end
