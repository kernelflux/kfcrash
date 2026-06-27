#import "KFCrashAppMemory.h"

#import "KFCrashAppMemory+Private.h"

NS_ASSUME_NONNULL_BEGIN

@implementation KFCrashAppMemory

- (instancetype)initWithFootprint:(uint64_t)footprint
                        remaining:(uint64_t)remaining
                         pressure:(KFCrashAppMemoryState)pressure
{
    if ((self = [super init])) {
        _footprint = footprint;
        _remaining = remaining;
        _pressure = pressure;
    }
    return self;
}

- (BOOL)isEqual:(id)object
{
    if (![object isKindOfClass:self.class]) {
        return NO;
    }
    KFCrashAppMemory *comp = (KFCrashAppMemory *)object;
    return comp.footprint == self.footprint && comp.remaining == self.remaining && comp.pressure == self.pressure;
}

- (uint64_t)limit
{
    return _footprint + _remaining;
}

- (KFCrashAppMemoryState)level
{
    double usedRatio = (double)self.footprint / (double)self.limit;

    return usedRatio < 0.25   ? KSCrashAppMemoryStateNormal
           : usedRatio < 0.50 ? KSCrashAppMemoryStateWarn
           : usedRatio < 0.75 ? KSCrashAppMemoryStateUrgent
           : usedRatio < 0.95 ? KSCrashAppMemoryStateCritical
                              : KSCrashAppMemoryStateTerminal;
}

- (BOOL)isOutOfMemory
{
    return self.level >= KSCrashAppMemoryStateCritical || self.pressure >= KSCrashAppMemoryStateCritical;
}

@end

const char *KSCrashAppMemoryStateToString(KFCrashAppMemoryState state)
{
    switch (state) {
        case KSCrashAppMemoryStateNormal:
            return "normal";
        case KSCrashAppMemoryStateWarn:
            return "warn";
        case KSCrashAppMemoryStateUrgent:
            return "urgent";
        case KSCrashAppMemoryStateCritical:
            return "critical";
        case KSCrashAppMemoryStateTerminal:
            return "terminal";
        default:
            assert(state <= KSCrashAppMemoryStateTerminal);
    }
}

KFCrashAppMemoryState KSCrashAppMemoryStateFromString(NSString *const string)
{
    if ([string isEqualToString:@"normal"]) {
        return KSCrashAppMemoryStateNormal;
    }

    if ([string isEqualToString:@"warn"]) {
        return KSCrashAppMemoryStateWarn;
    }

    if ([string isEqualToString:@"urgent"]) {
        return KSCrashAppMemoryStateUrgent;
    }

    if ([string isEqualToString:@"critical"]) {
        return KSCrashAppMemoryStateCritical;
    }

    if ([string isEqualToString:@"terminal"]) {
        return KSCrashAppMemoryStateTerminal;
    }

    return KSCrashAppMemoryStateNormal;
}

NSNotificationName const KSCrashAppMemoryLevelChangedNotification = @"KSCrashAppMemoryLevelChangedNotification";
NSNotificationName const KSCrashAppMemoryPressureChangedNotification = @"KSCrashAppMemoryPressureChangedNotification";
NSString *const KSCrashAppMemoryNewValueKey = @"KSCrashAppMemoryNewValueKey";
NSString *const KSCrashAppMemoryOldValueKey = @"KSCrashAppMemoryOldValueKey";

NS_ASSUME_NONNULL_END
