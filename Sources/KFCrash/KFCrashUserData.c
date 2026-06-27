//
//  KFCrashUserData.c
//
//  Pre-allocated thread-safe storage for breadcrumbs and custom key-value pairs.
//  Uses pre-allocated memory to be async-safe at crash time — no malloc, no locks
//  needed during serialization since threads are already suspended.
//

#include "KFCrashUserData.h"

#include <pthread.h>
#include <string.h>
#include <time.h>

#include "KFCLogger.h"

// ============================================================================
#pragma mark - Breadcrumbs -
// ============================================================================

typedef struct {
    int64_t timestamp;  // microseconds since epoch
    char message[KFCRASH_BREADCRUMB_MAX_MESSAGE_LENGTH];
} KFCBreadcrumbEntry;

typedef struct {
    KFCBreadcrumbEntry entries[KFCRASH_MAX_BREADCRUMBS];
    int writeIndex;  // Next write position (oldest entry is at writeIndex when full)
    int count;       // Number of valid entries (0..KFCRASH_MAX_BREADCRUMBS)
} KFCBreadcrumbStore;

static KFCBreadcrumbStore g_breadcrumbStore;
static pthread_mutex_t g_breadcrumbMutex = PTHREAD_MUTEX_INITIALIZER;

void kfcrash_addBreadcrumb(const char *message)
{
    if (message == NULL) {
        return;
    }

    // Get timestamp before acquiring lock to minimize lock hold time.
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    int64_t timestamp = (int64_t)ts.tv_sec * 1000000 + (int64_t)ts.tv_nsec / 1000;

    pthread_mutex_lock(&g_breadcrumbMutex);

    KFCBreadcrumbEntry *entry = &g_breadcrumbStore.entries[g_breadcrumbStore.writeIndex];
    entry->timestamp = timestamp;
    strncpy(entry->message, message, KFCRASH_BREADCRUMB_MAX_MESSAGE_LENGTH - 1);
    entry->message[KFCRASH_BREADCRUMB_MAX_MESSAGE_LENGTH - 1] = '\0';

    g_breadcrumbStore.writeIndex = (g_breadcrumbStore.writeIndex + 1) % KFCRASH_MAX_BREADCRUMBS;
    if (g_breadcrumbStore.count < KFCRASH_MAX_BREADCRUMBS) {
        g_breadcrumbStore.count++;
    }

    pthread_mutex_unlock(&g_breadcrumbMutex);
}

void kfcrash_clearBreadcrumbs(void)
{
    pthread_mutex_lock(&g_breadcrumbMutex);
    memset(&g_breadcrumbStore, 0, sizeof(g_breadcrumbStore));
    pthread_mutex_unlock(&g_breadcrumbMutex);
}

// ============================================================================
#pragma mark - Custom Keys -
// ============================================================================

typedef struct {
    char key[KFCRASH_CUSTOM_KEY_MAX_LENGTH];
    char value[KFCRASH_CUSTOM_VALUE_MAX_LENGTH];
} KFCCustomKeyEntry;

typedef struct {
    KFCCustomKeyEntry entries[KFCRASH_MAX_CUSTOM_KEYS];
    int count;
} KFCCustomKeyStore;

static KFCCustomKeyStore g_customKeyStore;
static pthread_mutex_t g_customKeyMutex = PTHREAD_MUTEX_INITIALIZER;

void kfcrash_setCustomKey(const char *key, const char *value)
{
    if (key == NULL || value == NULL) {
        return;
    }

    pthread_mutex_lock(&g_customKeyMutex);

    // Check if key already exists — update in place.
    for (int i = 0; i < g_customKeyStore.count; i++) {
        if (strncmp(g_customKeyStore.entries[i].key, key, KFCRASH_CUSTOM_KEY_MAX_LENGTH) == 0) {
            strncpy(g_customKeyStore.entries[i].value, value, KFCRASH_CUSTOM_VALUE_MAX_LENGTH - 1);
            g_customKeyStore.entries[i].value[KFCRASH_CUSTOM_VALUE_MAX_LENGTH - 1] = '\0';
            pthread_mutex_unlock(&g_customKeyMutex);
            return;
        }
    }

    // Key doesn't exist — add new entry.
    if (g_customKeyStore.count < KFCRASH_MAX_CUSTOM_KEYS) {
        KFCCustomKeyEntry *entry = &g_customKeyStore.entries[g_customKeyStore.count];
        strncpy(entry->key, key, KFCRASH_CUSTOM_KEY_MAX_LENGTH - 1);
        entry->key[KFCRASH_CUSTOM_KEY_MAX_LENGTH - 1] = '\0';
        strncpy(entry->value, value, KFCRASH_CUSTOM_VALUE_MAX_LENGTH - 1);
        entry->value[KFCRASH_CUSTOM_VALUE_MAX_LENGTH - 1] = '\0';
        g_customKeyStore.count++;
    } else {
        KFCLOG_WARN("Custom key store is full (%d entries). Ignoring key: %s",
                    KFCRASH_MAX_CUSTOM_KEYS, key);
    }

    pthread_mutex_unlock(&g_customKeyMutex);
}

void kfcrash_removeCustomKey(const char *key)
{
    if (key == NULL) {
        return;
    }

    pthread_mutex_lock(&g_customKeyMutex);

    for (int i = 0; i < g_customKeyStore.count; i++) {
        if (strncmp(g_customKeyStore.entries[i].key, key, KFCRASH_CUSTOM_KEY_MAX_LENGTH) == 0) {
            // Shift remaining entries down.
            int remaining = g_customKeyStore.count - i - 1;
            if (remaining > 0) {
                memmove(&g_customKeyStore.entries[i], &g_customKeyStore.entries[i + 1],
                        (size_t)remaining * sizeof(KFCCustomKeyEntry));
            }
            g_customKeyStore.count--;
            break;
        }
    }

    pthread_mutex_unlock(&g_customKeyMutex);
}

void kfcrash_clearCustomKeys(void)
{
    pthread_mutex_lock(&g_customKeyMutex);
    memset(&g_customKeyStore, 0, sizeof(g_customKeyStore));
    pthread_mutex_unlock(&g_customKeyMutex);
}

// ============================================================================
#pragma mark - Crash-time serialization -
// ============================================================================

// No locks needed — threads are suspended at crash time.

int kfcrash_getBreadcrumbCount(void)
{
    return g_breadcrumbStore.count;
}

bool kfcrash_getBreadcrumbAt(int index, int64_t *timestamp, const char **message)
{
    if (index < 0 || index >= g_breadcrumbStore.count) {
        return false;
    }
    int realIndex;
    if (g_breadcrumbStore.count < KFCRASH_MAX_BREADCRUMBS) {
        realIndex = index;
    } else {
        realIndex = (g_breadcrumbStore.writeIndex + index) % KFCRASH_MAX_BREADCRUMBS;
    }
    *timestamp = g_breadcrumbStore.entries[realIndex].timestamp;
    *message = g_breadcrumbStore.entries[realIndex].message;
    return true;
}

int kfcrash_getCustomKeyCount(void)
{
    return g_customKeyStore.count;
}

bool kfcrash_getCustomKeyAt(int index, const char **key, const char **value)
{
    if (index < 0 || index >= g_customKeyStore.count) {
        return false;
    }
    *key = g_customKeyStore.entries[index].key;
    *value = g_customKeyStore.entries[index].value;
    return true;
}
