//
//  KFCrashUserData.h
//
//  Pre-allocated thread-safe storage for breadcrumbs and custom key-value pairs
//  that get serialized into crash reports at crash time.
//

#ifndef HDR_KFCrashUserData_h
#define HDR_KFCrashUserData_h

#include <stdbool.h>
#include <stdint.h>

#include "KFCrashNamespace.h"

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
#pragma mark - Breadcrumbs -
// ============================================================================

#define KFCRASH_MAX_BREADCRUMBS 100
#define KFCRASH_BREADCRUMB_MAX_MESSAGE_LENGTH 256

/** Add a breadcrumb. Thread-safe. May be called from any thread at any time.
 *  The message is truncated to KFCRASH_BREADCRUMB_MAX_MESSAGE_LENGTH bytes.
 *
 * @param message A UTF-8 string describing the breadcrumb event.
 */
void kfcrash_addBreadcrumb(const char *message);

/** Clear all breadcrumbs. Thread-safe. */
void kfcrash_clearBreadcrumbs(void);

// ============================================================================
#pragma mark - Custom Keys -
// ============================================================================

#define KFCRASH_MAX_CUSTOM_KEYS 50
#define KFCRASH_CUSTOM_KEY_MAX_LENGTH 128
#define KFCRASH_CUSTOM_VALUE_MAX_LENGTH 128

/** Set a custom key-value pair. Thread-safe.
 *  If the key already exists, its value is updated.
 *  If the store is full, the oldest key is evicted.
 *  Keys and values are truncated to their respective max lengths.
 *
 * @param key A UTF-8 string key.
 * @param value A UTF-8 string value.
 */
void kfcrash_setCustomKey(const char *key, const char *value);

/** Remove a custom key. Thread-safe.
 *
 * @param key The key to remove.
 */
void kfcrash_removeCustomKey(const char *key);

/** Clear all custom keys. Thread-safe. */
void kfcrash_clearCustomKeys(void);

// ============================================================================
#pragma mark - Crash-time serialization -
// ============================================================================

/** Number of stored breadcrumbs. Async-safe at crash time (no lock needed). */
int kfcrash_getBreadcrumbCount(void);

/** Get a breadcrumb's timestamp and message by index (0-based).
 *  Async-safe at crash time. Returns false if index is out of range. */
bool kfcrash_getBreadcrumbAt(int index, int64_t *timestamp, const char **message);

/** Number of stored custom keys. Async-safe at crash time (no lock needed). */
int kfcrash_getCustomKeyCount(void);

/** Get a custom key-value pair by index (0-based).
 *  Async-safe at crash time. Returns false if index is out of range. */
bool kfcrash_getCustomKeyAt(int index, const char **key, const char **value);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KFCrashUserData_h
