//
//  KFCrashAppMemoryTracker.h
//
//  Created by Alexander Cohen on 2024-05-20.
//
//  Copyright (c) 2024 Alexander Cohen. All rights reserved.
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
#import <Foundation/Foundation.h>

#import "KFCrashAppMemory.h"
#include "KFCrashNamespace.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSUInteger, KFCrashAppMemoryTrackerChangeType) {
    KSCrashAppMemoryTrackerChangeTypeNone = 0,
    KSCrashAppMemoryTrackerChangeTypeLevel = 1 << 0,
    KSCrashAppMemoryTrackerChangeTypePressure = 1 << 1,
    KSCrashAppMemoryTrackerChangeTypeFootprint = 1 << 2,
} NS_SWIFT_NAME(AppMemoryTrackerChangeType);

typedef void (^KFCrashAppMemoryTrackerObserverBlock)(KFCrashAppMemory *memory,
                                                     KFCrashAppMemoryTrackerChangeType changes)
    NS_SWIFT_UNAVAILABLE("Use Swift closures instead!");

@protocol KFCrashAppMemoryTrackerDelegate;
@protocol KSCrashAppMemoryTrackerObserving;

NS_SWIFT_NAME(AppMemoryTracker)
@interface KFCrashAppMemoryTracker : NSObject

/**
 * The shared tracker. Use this unless you absolutely need your own tracker,
 * at which point you can simply allocate your own.
 */
@property(class, atomic, readonly) KFCrashAppMemoryTracker *sharedInstance NS_SWIFT_NAME(shared);

@property(atomic, readonly) KFCrashAppMemoryState pressure;
@property(atomic, readonly) KFCrashAppMemoryState level;

@property(nonatomic, readonly, nullable) KFCrashAppMemory *currentAppMemory;

/**
 * Adds a block based observer.
 *
 *@return An object that when set to nil will remove the observer.
 */
- (id)addObserverWithBlock:(KFCrashAppMemoryTrackerObserverBlock)block;

/**
 * Start the tracker.
 *
 * @warning Don't call this on the shared tracker.
 */
- (void)start;

/**
 * Stop the tracker.
 *
 * @warning Don't call this on the shared tracker.
 */
- (void)stop;

/**
 *
 * @deprecated This property is deprecated in favor of `addObserverWithBlock:`.
 */
@property(nonatomic, assign) id<KFCrashAppMemoryTrackerDelegate> delegate
    __attribute__((deprecated("Use -addObserverWithBlock: instead.")));

@end

/**
 *
 * @deprecated Use `addObserverWithBlock:` instead.
 */
NS_SWIFT_NAME(AppMemoryTrackerDelegate)
__attribute__((deprecated("Use -addObserverWithBlock: instead.")))
@protocol KFCrashAppMemoryTrackerDelegate<NSObject>

- (void)appMemoryTracker:(KFCrashAppMemoryTracker *)tracker
                  memory:(KFCrashAppMemory *)memory
                 changed:(KFCrashAppMemoryTrackerChangeType)changes;

@end

NS_ASSUME_NONNULL_END
