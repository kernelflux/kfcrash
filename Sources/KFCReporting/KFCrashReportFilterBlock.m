//
//  KFCrashReportFilterBlock.m
//

#import "KFCrashReportFilterBlock.h"

@implementation KFCrashReportFilterBlock {
    NSArray<id<KFCrashReport>> *_Nonnull (^_block)(NSArray<id<KFCrashReport>> *_Nonnull);
}

- (instancetype)initWithBlock:(NSArray<id<KFCrashReport>> *_Nonnull (^)(NSArray<id<KFCrashReport>> *_Nonnull))block
{
    if ((self = [super init])) {
        _block = [block copy];
    }
    return self;
}

- (void)filterReports:(NSArray<id<KFCrashReport>> *)reports
         onCompletion:(KFCrashReportFilterCompletion)onCompletion
{
    NSArray<id<KFCrashReport>> *filtered = _block(reports);
    kfcrash_callCompletion(onCompletion, filtered, nil);
}

@end
