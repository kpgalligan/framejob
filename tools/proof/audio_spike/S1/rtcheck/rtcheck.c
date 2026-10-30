// rtcheck: counts allocations and lock acquisitions made on ONE armed thread.
//
// Loaded with DYLD_INSERT_LIBRARIES. Interposes the allocator and the usual
// blocking primitives; each replacement calls the original (dyld does not
// interpose an interposing image's own calls) and, when the calling thread is
// the armed one, counts the call and keeps the first few backtraces. The
// libmalloc `malloc_logger` hook is set as a second, independent allocation
// count that also sees allocations made INSIDE libsystem_malloc's callers in
// the same image (which interposition cannot see).
#include <dispatch/dispatch.h>
#include <execinfo.h>
#include <malloc/malloc.h>
#include <os/lock.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DYLD_INTERPOSE(_replacement, _replacee)                                            \
    __attribute__((used)) static struct {                                                  \
        const void *replacement;                                                           \
        const void *replacee;                                                              \
    } _interpose_##_replacee __attribute__((section("__DATA,__interpose"))) = {            \
        (const void *)(unsigned long)&_replacement, (const void *)(unsigned long)&_replacee};

static pthread_t volatile armed_thread = 0;
static _Atomic long n_alloc, n_free, n_lock, n_logger_alloc, n_logger_free;

#define MAX_TRACES 6
#define TRACE_DEPTH 24
static void *traces[MAX_TRACES][TRACE_DEPTH];
static int trace_len[MAX_TRACES];
static const char *trace_kind[MAX_TRACES];
static _Atomic int n_traces;
static int volatile in_trace = 0;

static inline int armed(void) {
    pthread_t t = armed_thread;
    return t != 0 && pthread_equal(t, pthread_self());
}

static void keep_trace(const char *kind) {
    if (in_trace) return;
    int slot = atomic_fetch_add(&n_traces, 1);
    if (slot >= MAX_TRACES) return;
    in_trace = 1;
    trace_len[slot] = backtrace(traces[slot], TRACE_DEPTH);
    trace_kind[slot] = kind;
    in_trace = 0;
}

#define COUNT_ALLOC(kind)                    \
    do {                                     \
        if (armed()) {                       \
            atomic_fetch_add(&n_alloc, 1);   \
            keep_trace(kind);                \
        }                                    \
    } while (0)
#define COUNT_FREE()                         \
    do {                                     \
        if (armed()) atomic_fetch_add(&n_free, 1); \
    } while (0)
#define COUNT_LOCK(kind)                     \
    do {                                     \
        if (armed()) {                       \
            atomic_fetch_add(&n_lock, 1);    \
            keep_trace(kind);                \
        }                                    \
    } while (0)

static void *my_malloc(size_t s) { COUNT_ALLOC("malloc"); return malloc(s); }
static void *my_calloc(size_t n, size_t s) { COUNT_ALLOC("calloc"); return calloc(n, s); }
static void *my_realloc(void *p, size_t s) { COUNT_ALLOC("realloc"); return realloc(p, s); }
static void *my_valloc(size_t s) { COUNT_ALLOC("valloc"); return valloc(s); }
static int my_posix_memalign(void **p, size_t a, size_t s) { COUNT_ALLOC("posix_memalign"); return posix_memalign(p, a, s); }
static void *my_aligned_alloc(size_t a, size_t s) { COUNT_ALLOC("aligned_alloc"); return aligned_alloc(a, s); }
static void my_free(void *p) { if (p) COUNT_FREE(); free(p); }
static void *my_zmalloc(malloc_zone_t *z, size_t s) { COUNT_ALLOC("malloc_zone_malloc"); return malloc_zone_malloc(z, s); }
static void *my_zcalloc(malloc_zone_t *z, size_t n, size_t s) { COUNT_ALLOC("malloc_zone_calloc"); return malloc_zone_calloc(z, n, s); }
static void *my_zrealloc(malloc_zone_t *z, void *p, size_t s) { COUNT_ALLOC("malloc_zone_realloc"); return malloc_zone_realloc(z, p, s); }
static void *my_zmemalign(malloc_zone_t *z, size_t a, size_t s) { COUNT_ALLOC("malloc_zone_memalign"); return malloc_zone_memalign(z, a, s); }
static void my_zfree(malloc_zone_t *z, void *p) { if (p) COUNT_FREE(); malloc_zone_free(z, p); }

static int my_mutex_lock(pthread_mutex_t *m) { COUNT_LOCK("pthread_mutex_lock"); return pthread_mutex_lock(m); }
static int my_mutex_trylock(pthread_mutex_t *m) { COUNT_LOCK("pthread_mutex_trylock"); return pthread_mutex_trylock(m); }
static void my_unfair_lock(os_unfair_lock_t l) { COUNT_LOCK("os_unfair_lock_lock"); os_unfair_lock_lock(l); }
static bool my_unfair_trylock(os_unfair_lock_t l) { COUNT_LOCK("os_unfair_lock_trylock"); return os_unfair_lock_trylock(l); }
static int my_rw_rd(pthread_rwlock_t *l) { COUNT_LOCK("pthread_rwlock_rdlock"); return pthread_rwlock_rdlock(l); }
static int my_rw_wr(pthread_rwlock_t *l) { COUNT_LOCK("pthread_rwlock_wrlock"); return pthread_rwlock_wrlock(l); }
static long my_sem_wait(dispatch_semaphore_t s, dispatch_time_t t) { COUNT_LOCK("dispatch_semaphore_wait"); return dispatch_semaphore_wait(s, t); }
static int my_cond_wait(pthread_cond_t *c, pthread_mutex_t *m) { COUNT_LOCK("pthread_cond_wait"); return pthread_cond_wait(c, m); }
static int my_cond_timedwait(pthread_cond_t *c, pthread_mutex_t *m, const struct timespec *t) { COUNT_LOCK("pthread_cond_timedwait"); return pthread_cond_timedwait(c, m, t); }

DYLD_INTERPOSE(my_malloc, malloc)
DYLD_INTERPOSE(my_calloc, calloc)
DYLD_INTERPOSE(my_realloc, realloc)
DYLD_INTERPOSE(my_valloc, valloc)
DYLD_INTERPOSE(my_posix_memalign, posix_memalign)
DYLD_INTERPOSE(my_aligned_alloc, aligned_alloc)
DYLD_INTERPOSE(my_free, free)
DYLD_INTERPOSE(my_zmalloc, malloc_zone_malloc)
DYLD_INTERPOSE(my_zcalloc, malloc_zone_calloc)
DYLD_INTERPOSE(my_zrealloc, malloc_zone_realloc)
DYLD_INTERPOSE(my_zmemalign, malloc_zone_memalign)
DYLD_INTERPOSE(my_zfree, malloc_zone_free)
DYLD_INTERPOSE(my_mutex_lock, pthread_mutex_lock)
DYLD_INTERPOSE(my_mutex_trylock, pthread_mutex_trylock)
DYLD_INTERPOSE(my_unfair_lock, os_unfair_lock_lock)
DYLD_INTERPOSE(my_unfair_trylock, os_unfair_lock_trylock)
DYLD_INTERPOSE(my_rw_rd, pthread_rwlock_rdlock)
DYLD_INTERPOSE(my_rw_wr, pthread_rwlock_wrlock)
DYLD_INTERPOSE(my_sem_wait, dispatch_semaphore_wait)
DYLD_INTERPOSE(my_cond_wait, pthread_cond_wait)
DYLD_INTERPOSE(my_cond_timedwait, pthread_cond_timedwait)

// libmalloc's logger hook (the one MallocStackLogging uses). Type bits:
// 2 allocate, 4 deallocate.
typedef void(malloc_logger_t)(uint32_t type, uintptr_t a1, uintptr_t a2, uintptr_t a3,
                              uintptr_t result, uint32_t skip);
extern malloc_logger_t *malloc_logger;
static void logger(uint32_t type, uintptr_t a1, uintptr_t a2, uintptr_t a3, uintptr_t result,
                   uint32_t skip) {
    if (!armed()) return;
    if (type & 2) atomic_fetch_add(&n_logger_alloc, 1);
    if (type & 4) atomic_fetch_add(&n_logger_free, 1);
}

__attribute__((constructor)) static void install(void) { malloc_logger = logger; }

// The API the Swift harness finds with dlsym.
void rtcheck_arm(void) { armed_thread = pthread_self(); }
void rtcheck_disarm(void) { armed_thread = 0; }
// out: alloc, free, lock, logger_alloc, logger_free
void rtcheck_counts(long *out) {
    out[0] = atomic_load(&n_alloc);
    out[1] = atomic_load(&n_free);
    out[2] = atomic_load(&n_lock);
    out[3] = atomic_load(&n_logger_alloc);
    out[4] = atomic_load(&n_logger_free);
}
void rtcheck_reset_traces(void) { atomic_store(&n_traces, 0); }
// Prints the kept backtraces (call only when disarmed: it allocates).
void rtcheck_dump_traces(const char *label) {
    int n = atomic_load(&n_traces);
    if (n > MAX_TRACES) n = MAX_TRACES;
    for (int i = 0; i < n; i++) {
        fprintf(stderr, "[rtcheck %s] trace %d (%s):\n", label, i, trace_kind[i]);
        char **syms = backtrace_symbols(traces[i], trace_len[i]);
        for (int j = 1; j < trace_len[i] && j < 14; j++) fprintf(stderr, "    %s\n", syms ? syms[j] : "?");
        free(syms);
    }
}
