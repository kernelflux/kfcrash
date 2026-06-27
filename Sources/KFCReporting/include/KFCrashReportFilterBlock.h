//
//  KFCrashReportFilterBlock.h
//
//  A filter that wraps a block — used to bridge Swift closures into the
//  KFCrashReportFilter pipeline (e.g. onBeforeSend).
//

#include "KFCrashNamespace.h"
#import "KFCrashReportFilter.h"

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A filter that passes each report through a block.
/// The block receives an array of reports and must return an array of reports.
NS_SWIFT_NAME(CrashReportFilterBlock)
@interface KFCrashReportFilterBlock : NSObject <KFCrashReportFilter>

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithBlock:(NSArray<id<KFCrashReport>> *_Nonnull (^)(NSArray<id<KFCrashReport>> *_Nonnull))block;

@end

NS_ASSUME_NONNULL_END
