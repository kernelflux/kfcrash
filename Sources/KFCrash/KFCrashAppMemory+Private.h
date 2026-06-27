#import <Foundation/Foundation.h>
#import "KFCrashAppMemory.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Internal and for tests.
 */
@interface KFCrashAppMemory ()
- (instancetype)initWithFootprint:(uint64_t)footprint
                        remaining:(uint64_t)remaining
                         pressure:(KFCrashAppMemoryState)pressure NS_DESIGNATED_INITIALIZER;
@end

typedef KFCrashAppMemory *_Nonnull (^KFCrashAppMemoryProvider)(void);
FOUNDATION_EXPORT void testsupport_KFCrashAppMemorySetProvider(KFCrashAppMemoryProvider _Nullable provider);

NS_ASSUME_NONNULL_END
