#ifndef FRAMEJOB_OBJC_CATCH_H
#define FRAMEJOB_OBJC_CATCH_H

// The one Objective-C catch Swift cannot write (spec §11 #525): `@try` around a
// block, for `ObjCException.swift`. An exception a tool's handler raises would
// otherwise cross Rust's `catch_unwind` in `agent::serve`, or AppKit's
// uncaught-exception handler inside a `DispatchQueue.main.sync`, and end the
// app; `AgentLane` runs each call inside this instead and answers it `isError`.

#import <Foundation/Foundation.h>

/// Runs `body` inside `@try`. Answers the `NSException` it raised (any other
/// object wrapped as an `NSException` named "FrameJobNonNSException", its
/// reason the object's description), or nil when `body` returned normally.
static inline NSException *_Nullable framejob_catch_objc(NS_NOESCAPE void (^_Nonnull body)(void)) {
    @try {
        body();
    } @catch (NSException *exception) {
        return exception;
    } @catch (id other) {
        return [NSException exceptionWithName:@"FrameJobNonNSException"
                                       reason:[other description]
                                     userInfo:nil];
    }
    return nil;
}

#endif
