// Interposes the beep for `docs_bugs_c2_probe.swift`: counts, and makes no sound. Swift's
// `NSSound.beep()` binds to AppKit's own Swift symbol, not to `NSBeep`, so both are replaced.
// cc -dynamiclib -framework AppKit -o beep_count.dylib docs_bugs_c2_beep.c
#include <stdatomic.h>

extern void NSBeep(void);
extern void swift_beep(void) __asm("_$sSo7NSSoundC6AppKitE4beepyyFZ");

static atomic_int count;

static void counted_beep(void) { atomic_fetch_add(&count, 1); }

int beep_count_read(void) { return atomic_load(&count); }

__attribute__((used)) static const struct {
    const void *replacement;
    const void *replacee;
} interposers[] __attribute__((section("__DATA,__interpose"))) = {
    {(const void *)counted_beep, (const void *)NSBeep},
    {(const void *)counted_beep, (const void *)swift_beep},
};
