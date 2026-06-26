#import <Foundation/Foundation.h>
#import "BypassHooks.h"
#import "UnlockAcademiaMenuView.h"

#pragma mark - Deferred Hooking

static void runDeferredHooks(void) {
    NSLog(@"[unlock_academia] Running deferred hooks in background...");

    // Apply native frameworks and flutter channel hooks
    [BypassHooks applySafeDeviceHooks];
    [BypassHooks applyScreenPreventerHooks];
    [BypassHooks applyRevenueCatHooks];
    [BypassHooks applyFlutterChannelHooks];

    // Scan the window hierarchy to disable secure text field blocking selectively
    [BypassHooks scanAndDisableSecureTextFields];
    
    // Add the floating menu trigger button
    [UnlockAcademiaMenuView addFloatingButton];

    // Late retry hook after 2 seconds to capture elements instantiated later
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [BypassHooks applySafeDeviceHooks];
        [BypassHooks applyScreenPreventerHooks];
        [BypassHooks applyRevenueCatHooks];
        [BypassHooks applyFlutterChannelHooks];
        [BypassHooks scanAndDisableSecureTextFields];
        [UnlockAcademiaMenuView addFloatingButton];
        NSLog(@"[unlock_academia] Late retry hooking sequence complete");
    });
}

#pragma mark - Constructor

__attribute__((constructor)) static void init_dylib(void) {
    @autoreleasepool {
        NSLog(@"[unlock_academia] dylib loaded. Initializing separate modules...");
        
        // Immediately hook UIKit elements (UIScreen, UITextField) on load
        [BypassHooks applyUIKitHooks];

        // Defer application of dynamic class hooks and UI injection to the main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            runDeferredHooks();
        });
    }
}
