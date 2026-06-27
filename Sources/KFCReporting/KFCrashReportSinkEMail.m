//
//  KFCrashReportSinkEMail.m
//
//  Created by Karl Stenerud on 2012-05-06.
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

#import "KFCrashReportSinkEMail.h"

#import "KFCrashReport.h"
#import "KFCrashReportFilterAppleFmt.h"
#import "KFCrashReportFilterBasic.h"
#import "KFCrashReportFilterGZip.h"
#import "KFCrashReportFilterJSON.h"
#import "KFCNSErrorHelper.h"
#import "KFCSystemCapabilities.h"

// #define KSLogger_LocalLevel TRACE
#import "KFCLogger.h"

#if KFCRASH_HAS_MESSAGEUI
#import <MessageUI/MessageUI.h>

@interface KSCrashMailProcess : NSObject <MFMailComposeViewControllerDelegate>

@property(nonatomic, readwrite, copy) NSArray<id<KFCrashReport>> *reports;
@property(nonatomic, readwrite, copy) KFCrashReportFilterCompletion onCompletion;

@property(nonatomic, readwrite, strong) UIViewController *dummyVC;

+ (KSCrashMailProcess *)process;

- (void)startWithController:(MFMailComposeViewController *)controller
                    reports:(NSArray<id<KFCrashReport>> *)reports
                filenameFmt:(NSString *)filenameFmt
               onCompletion:(KFCrashReportFilterCompletion)onCompletion;

- (void)presentModalVC:(UIViewController *)vc;
- (void)dismissModalVC;

@end

@implementation KSCrashMailProcess

+ (KSCrashMailProcess *)process
{
    return [[self alloc] init];
}

- (void)startWithController:(MFMailComposeViewController *)controller
                    reports:(NSArray<id<KFCrashReport>> *)reports
                filenameFmt:(NSString *)filenameFmt
               onCompletion:(KFCrashReportFilterCompletion)onCompletion
{
    self.reports = [reports copy];
    self.onCompletion = onCompletion;

    controller.mailComposeDelegate = self;

    int i = 1;
    for (KFCrashReportData *report in reports) {
        if ([report isKindOfClass:[KFCrashReportData class]] == NO || report.value == nil) {
            KFCLOG_ERROR(@"Unexpected non-data report: %@", report);
            continue;
        }
        [controller addAttachmentData:report.value
                             mimeType:@"binary"
                             fileName:[NSString stringWithFormat:filenameFmt, i++]];
    }

    [self presentModalVC:controller];
}

- (void)mailComposeController:(__unused MFMailComposeViewController *)mailController
          didFinishWithResult:(MFMailComposeResult)result
                        error:(NSError *)error
{
    [self dismissModalVC];

    switch (result) {
        case MFMailComposeResultSent:
            kfcrash_callCompletion(self.onCompletion, self.reports, nil);
            break;
        case MFMailComposeResultSaved:
            kfcrash_callCompletion(self.onCompletion, self.reports, nil);
            break;
        case MFMailComposeResultCancelled:
            kfcrash_callCompletion(self.onCompletion, self.reports,
                                   [KSNSErrorHelper errorWithDomain:[[self class] description]
                                                               code:0
                                                        description:@"User cancelled"]);
            break;
        case MFMailComposeResultFailed:
            kfcrash_callCompletion(self.onCompletion, self.reports, error);
            break;
        default: {
            kfcrash_callCompletion(self.onCompletion, self.reports,
                                   [KSNSErrorHelper errorWithDomain:[[self class] description]
                                                               code:0
                                                        description:@"Unknown MFMailComposeResult: %d", result]);
        }
    }
}

- (void)presentModalVC:(UIViewController *)vc
{
    self.dummyVC = [[UIViewController alloc] initWithNibName:nil bundle:nil];
    self.dummyVC.view = [[UIView alloc] init];

    UIWindow *window = [[[UIApplication sharedApplication] delegate] window];
    [window addSubview:self.dummyVC.view];

    if ([self.dummyVC respondsToSelector:@selector(presentViewController:animated:completion:)]) {
        [self.dummyVC presentViewController:vc animated:YES completion:nil];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [self.dummyVC presentModalViewController:vc animated:YES];
#pragma clang diagnostic pop
    }
}

- (void)dismissModalVC
{
    if ([self.dummyVC respondsToSelector:@selector(dismissViewControllerAnimated:completion:)]) {
        [self.dummyVC dismissViewControllerAnimated:YES
                                         completion:^{
                                             [self.dummyVC.view removeFromSuperview];
                                             self.dummyVC = nil;
                                         }];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [self.dummyVC dismissModalViewControllerAnimated:NO];
#pragma clang diagnostic pop
        [self.dummyVC.view removeFromSuperview];
        self.dummyVC = nil;
    }
}

@end

@interface KFCrashReportSinkEMail ()

@property(nonatomic, readwrite, copy) NSArray *recipients;
@property(nonatomic, readwrite, copy) NSString *subject;
@property(nonatomic, readwrite, copy) NSString *message;
@property(nonatomic, readwrite, copy) NSString *filenameFmt;

@end

@implementation KFCrashReportSinkEMail

- (instancetype)initWithRecipients:(NSArray<NSString *> *)recipients
                           subject:(NSString *)subject
                           message:(nullable NSString *)message
                       filenameFmt:(NSString *)filenameFmt
{
    if ((self = [super init])) {
        _recipients = [recipients copy];
        _subject = [subject copy];
        _message = [message copy];
        _filenameFmt = [filenameFmt copy];
    }
    return self;
}

- (id<KFCrashReportFilter>)defaultCrashReportFilterSet
{
    return [[KFCrashReportFilterPipeline alloc] initWithFilters:@[
        [[KFCrashReportFilterJSONEncode alloc] initWithOptions:KSJSONEncodeOptionSorted | KSJSONEncodeOptionPretty],
        [[KFCrashReportFilterGZipCompress alloc] initWithCompressionLevel:-1],
        self,
    ]];
}

- (id<KFCrashReportFilter>)defaultCrashReportFilterSetAppleFmt
{
    return [[KFCrashReportFilterPipeline alloc] initWithFilters:@[
        [[KFCrashReportFilterAppleFmt alloc] initWithReportStyle:KSAppleReportStyleSymbolicatedSideBySide],
        [KFCrashReportFilterStringToData new],
        [[KFCrashReportFilterGZipCompress alloc] initWithCompressionLevel:-1],
        self,
    ]];
}

static UIWindow *getKeyWindow(void)
{
    if (@available(iOS 15, tvOS 15, *)) {
        for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.keyWindow != nil) {
                return scene.keyWindow;
            }
        }
    } else {
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            if (window.keyWindow) {
                return window;
            }
        }
    }
    return nil;
}

- (void)filterReports:(NSArray<id<KFCrashReport>> *)reports onCompletion:(KFCrashReportFilterCompletion)onCompletion
{
    if (![MFMailComposeViewController canSendMail]) {
        UIAlertController *alertController =
            [UIAlertController alertControllerWithTitle:@"Email Error"
                                                message:@"This device is not configured to send email."
                                         preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
        [alertController addAction:okAction];
        UIWindow *keyWindow = getKeyWindow();
        [keyWindow.rootViewController presentViewController:alertController animated:YES completion:NULL];

        kfcrash_callCompletion(onCompletion, reports,
                               [KSNSErrorHelper errorWithDomain:[[self class] description]
                                                           code:0
                                                    description:@"E-Mail not enabled on device"]);
        return;
    }

    MFMailComposeViewController *mailController = [[MFMailComposeViewController alloc] init];
    [mailController setToRecipients:self.recipients];
    [mailController setSubject:self.subject];
    if (self.message != nil) {
        [mailController setMessageBody:self.message isHTML:NO];
    }
    NSString *filenameFmt = self.filenameFmt;

    dispatch_async(dispatch_get_main_queue(), ^{
        __block KSCrashMailProcess *process = [[KSCrashMailProcess alloc] init];
        [process startWithController:mailController
                             reports:reports
                         filenameFmt:filenameFmt
                        onCompletion:^(NSArray *filteredReports, NSError *error) {
                            kfcrash_callCompletion(onCompletion, filteredReports, error);
                            dispatch_async(dispatch_get_main_queue(), ^{
                                process = nil;
                            });
                        }];
    });
}

@end

#else

#import "KFCNSErrorHelper.h"

@implementation KFCrashReportSinkEMail

+ (KFCrashReportSinkEMail *)sinkWithRecipients:(NSArray *)recipients
                                       subject:(NSString *)subject
                                       message:(NSString *)message
                                   filenameFmt:(NSString *)filenameFmt
{
    return [[self alloc] initWithRecipients:recipients subject:subject message:message filenameFmt:filenameFmt];
}

- (id)initWithRecipients:(__unused NSArray *)recipients
                 subject:(__unused NSString *)subject
                 message:(__unused NSString *)message
             filenameFmt:(__unused NSString *)filenameFmt
{
    return [super init];
}

- (void)filterReports:(NSArray<id<KFCrashReport>> *)reports onCompletion:(KFCrashReportFilterCompletion)onCompletion
{
    for (id<KFCrashReport> report in reports) {
        NSLog(@"Report\n%@", report);
    }
    kfcrash_callCompletion(onCompletion, reports,
                           [KSNSErrorHelper errorWithDomain:[[self class] description]
                                                       code:0
                                                description:@"Cannot send mail on this platform"]);
}

- (id<KFCrashReportFilter>)defaultCrashReportFilterSet
{
    return [[KFCrashReportFilterPipeline alloc] initWithFilters:@[
        [[KFCrashReportFilterJSONEncode alloc] initWithOptions:KSJSONEncodeOptionSorted | KSJSONEncodeOptionPretty],
        [[KFCrashReportFilterGZipCompress alloc] initWithCompressionLevel:-1],
        self,
    ]];
}

- (id<KFCrashReportFilter>)defaultCrashReportFilterSetAppleFmt
{
    return [[KFCrashReportFilterPipeline alloc] initWithFilters:@[
        [[KFCrashReportFilterAppleFmt alloc] initWithReportStyle:KSAppleReportStyleSymbolicatedSideBySide],
        [KFCrashReportFilterStringToData new],
        [[KFCrashReportFilterGZipCompress alloc] initWithCompressionLevel:-1],
        self,
    ]];
}

@end

#endif
