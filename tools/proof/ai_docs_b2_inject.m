// ai-docs b2's #525 instrument (`ai_docs_b2_proof.py`): loaded into an unhardened app or the
// b2 probe with DYLD_INSERT_LIBRARIES (through lldb's target.env-vars), it raises an
// Objective-C exception inside a tool call, through the real lane, trampoline and core.
// Nothing else changes: a call without either token goes to the original method.
//
// 1. +[NSJSONSerialization JSONObjectWithData:options:error:] raises NSInvalidArgumentException on
//    data holding FRAMEJOB_RAISE_525. `AgentServer.execute` parses each call's arguments with it
//    on the thread the call runs on (the server thread for an `offMainTools` member, main for the
//    rest), and `AgentLane.answer` parses an assistant call's first.
// 2. -[NSString stringByExpandingTildeInPath] raises NSInvalidArgumentException on a receiver
//    holding FRAMEJOB_RAISE_HOP_525, ON THE MAIN THREAD ONLY. `new_project` (an `offMainTools`
//    member) parses its arguments on the server thread, so the first token never fires, and
//    reaches this on main inside its first `onMain` hop: `refuseHeldPath` →
//    `ProjectDocumentController.isOpening` → `opens(of:)` → `AgentServer.canonical`. So the raise
//    is inside `AgentLane.onMainWhenIdle`'s `DispatchQueue.main.sync`, past `route`'s catch.
//
// The JSON token is not a substring of the hop token, so the JSON wrapper ignores a hop call.
//
// Build: cc -dynamiclib -fobjc-arc -framework Foundation ai_docs_b2_inject.m -o <out>.dylib
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static IMP originalJSON;
static IMP originalTilde;

static id raisingJSON(id self, SEL _cmd, NSData *data, NSJSONReadingOptions options,
                      NSError **error) {
    static NSData *token;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        token = [@"FRAMEJOB_RAISE_525" dataUsingEncoding:NSUTF8StringEncoding];
    });
    if (data.length &&
        [data rangeOfData:token options:0 range:NSMakeRange(0, data.length)].location != NSNotFound) {
        NSLog(@"framejob-525-inject: raising on %@ (main thread: %d)", [NSThread currentThread],
              [NSThread isMainThread]);
        [NSException raise:NSInvalidArgumentException format:@"framejob-525 injected exception"];
    }
    return ((id(*)(id, SEL, NSData *, NSJSONReadingOptions, NSError **))originalJSON)(
        self, _cmd, data, options, error);
}

static NSString *raisingTilde(NSString *self, SEL _cmd) {
    if ([NSThread isMainThread] &&
        [self rangeOfString:@"FRAMEJOB_RAISE_HOP_525"].location != NSNotFound) {
        NSLog(@"framejob-525-inject: hop raising on %@ (main thread: %d)", [NSThread currentThread],
              [NSThread isMainThread]);
        [NSException raise:NSInvalidArgumentException format:@"framejob-525 injected hop exception"];
    }
    return ((NSString * (*)(id, SEL)) originalTilde)(self, _cmd);
}

__attribute__((constructor)) static void install(void) {
    Method json = class_getClassMethod([NSJSONSerialization class],
                                       @selector(JSONObjectWithData:options:error:));
    originalJSON = method_setImplementation(json, (IMP)raisingJSON);
    Method tilde = class_getInstanceMethod([NSString class], @selector(stringByExpandingTildeInPath));
    originalTilde = method_setImplementation(tilde, (IMP)raisingTilde);
    NSLog(@"framejob-525-inject: installed (%p, %p)", originalJSON, originalTilde);
}
