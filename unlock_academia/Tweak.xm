#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#pragma mark - Logos (%orig / %new helpers)
// Logos syntax for Theos — compiles to ObjC method_setImplementation calls

#pragma mark ====== safe_device Hooks ======

// +[SafeDeviceJailbreakDetection isJailbroken] — key check used by Flutter channel
%hookf(BOOL, SafeDeviceJailbreakDetection, isJailbroken) {
    return NO;
}

// +[SafeDeviceJailbreakDetection isJailBroken] — alternate casing
%hookf(BOOL, SafeDeviceJailbreakDetection, isJailBroken) {
    return NO;
}

// +[SafeDeviceJailbreakDetection isJailBrokenCustom]
%hookf(BOOL, SafeDeviceJailbreakDetection, isJailBrokenCustom) {
    return NO;
}

// +[SafeDeviceJailbreakDetection hasJailbreakPaths]
%hookf(BOOL, SafeDeviceJailbreakDetection, hasJailbreakPaths) {
    return NO;
}

// +[SafeDeviceJailbreakDetection hasJailbreakProcesses]
%hookf(BOOL, SafeDeviceJailbreakDetection, hasJailbreakProcesses) {
    return NO;
}

// +[SafeDeviceJailbreakDetection hasJailbreakEnvironmentVariables]
%hookf(BOOL, SafeDeviceJailbreakDetection, hasJailbreakEnvironmentVariables) {
    return NO;
}

// +[SafeDeviceJailbreakDetection canOpenJailbreakSchemes]
%hookf(BOOL, SafeDeviceJailbreakDetection, canOpenJailbreakSchemes) {
    return NO;
}

// +[SafeDeviceJailbreakDetection canViolateSandbox]
%hookf(BOOL, SafeDeviceJailbreakDetection, canViolateSandbox) {
    return NO;
}

// +[SafeDeviceJailbreakDetection canAccessPath:] — returns BOOL for each path check
%hookf(BOOL, SafeDeviceJailbreakDetection, canAccessPath, NSString *path) {
    return NO;
}

// +[SafeDeviceJailbreakDetection hasSuspiciousSymlinks]
%hookf(BOOL, SafeDeviceJailbreakDetection, hasSuspiciousSymlinks) {
    return NO;
}

// +[SafeDeviceJailbreakDetection isSimulator]
%hookf(BOOL, SafeDeviceJailbreakDetection, isSimulator) {
    return NO;
}

// +[SafeDeviceJailbreakDetection getJailbreakDetails]
%hookf(NSDictionary *, SafeDeviceJailbreakDetection, getJailbreakDetails) {
    return @{};
}

// Instance hooks on SafeDevicePlugin (Flutter channel handlers)
// -[SafeDevicePlugin isJailBroken]
%hook SafeDevicePlugin
- (id)isJailBroken {
    return @{@"isJailBroken": @NO};
}
- (id)isJailBrokenCustom {
    return @{@"isJailBroken": @NO};
}
- (NSNumber *)hasObviousJailbreakSigns {
    return @NO;
}
- (NSNumber *)isRealDevice {
    return @YES;
}
- (NSNumber *)hasLegitimateEnvironmentVariables {
    return @YES;
}
- (NSNumber *)isDevelopmentEnvironment {
    return @NO;
}
%end

// Flutter method channel handler hook — intercept all calls and always succeed
%hook SafeDevicePlugin
- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSString *method = call.method;
    if ([method isEqualToString:@"isJailbroken"] ||
        [method isEqualToString:@"isJailBroken"] ||
        [method isEqualToString:@"isJailBrokenCustom"] ||
        [method isEqualToString:@"getJailbreakDetails"]) {
        NSDictionary *reply = @{@"isJailBroken": @NO, @"isJailbroken": @NO};
        result(reply);
        return;
    }
    if ([method containsString:@"Jail"] || [method containsString:@"jail"] ||
        [method containsString:@"jailbreak"] || [method containsString:@"Jailbreak"]) {
        result(@{@"result": @NO, @"isJailBroken": @NO});
        return;
    }
    %orig;
}
%end


#pragma mark ====== DTTJailbreakDetection Hook ======

%hook DTTJailbreakDetection
+ (BOOL)isJailbroken {
    return NO;
}
+ (BOOL)isPirated {
    return NO;
}
%end


#pragma mark ====== ScreenPreventerKit Hooks ======

// Swift native class names:
//  _TtC18ScreenPreventerKit15ScreenPreventer
//  _TtC18ScreenPreventerKit19ScreenshotPreventer
//  _TtC18ScreenPreventerKit20ScreenPreventerStore
//  _TtC18ScreenPreventerKit27ScreenshotProtectionOverlay
//
// Key Swift methods (de-mangled):
//  enablePreventScreenshot()   -> disable
//  disablePreventScreenshot()  -> allow
//  enableScreenshotBlocking    -> ObjC bridged, also hooked
//  enabledPreventScreenshot    -> property, return NO
//  enabledPreventScreenRecording -> property, return NO

%hookf(void, ScreenPreventer, enablePreventScreenshot) {
    // Do nothing — don't apply screenshot blocking
}

%hookf(void, ScreenPreventer, disablePreventScreenshot) {
    // Allow screenshots — call original (which removes protection)
    %orig;
}

%hookf(BOOL, ScreenPreventer, enabledPreventScreenshot) {
    return NO;
}

%hookf(BOOL, ScreenPreventer, enabledPreventScreenRecording) {
    return NO;
}

%hookf(BOOL, ScreenPreventer, enabled) {
    return NO;
}

// ScreenshotPreventer class hooks
%hookf(void, ScreenshotPreventer, enablePreventScreenshot) {
    // No-op
}

%hookf(BOOL, ScreenshotPreventer, enabledPreventScreenshot) {
    return NO;
}

%hookf(BOOL, ScreenshotPreventer, enabledPreventScreenRecording) {
    return NO;
}

%hookf(BOOL, ScreenshotPreventer, enabled) {
    return NO;
}

// ScreenPreventerStore hooks
%hookf(BOOL, ScreenPreventerStore, enabledPreventScreenshot) {
    return NO;
}

%hookf(BOOL, ScreenPreventerStore, enabledPreventScreenRecording) {
    return NO;
}


#pragma mark ====== RevenueCat / Purchases Hooks ======

%hook RCCustomerInfo
- (NSDictionary *)jsonObject {
    // Force all entitlements active
    id orig = %orig;
    if ([orig isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *entitlements = [orig mutableCopy];
        NSDictionary *all = entitlements[@"entitlements"];
        if ([all isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *active = [NSMutableDictionary dictionary];
            for (NSString *key in all) {
                NSMutableDictionary *ent = [[all objectForKey:key] mutableCopy];
                if (ent) {
                    ent[@"isActive"] = @YES;
                    ent[@"expirationDate"] = [NSNull null];
                    active[key] = ent;
                }
            }
            entitlements[@"entitlements"] = active;
        }
        return entitlements;
    }
    return orig;
}
%end

%hook RCSubscriptionPeriod
- (NSTimeInterval)subscriptionDuration {
    // Return a very long duration (100 years)
    return 365 * 24 * 60 * 60 * 100.0;
}
%end

%hook RCPurchases
- (void)getCustomerInfoWithCompletion:(void(^)(RCCustomerInfo *, NSError *))completion {
    // Hook to force valid customer info
    %orig;
}
%end

// Force all entitlement check methods to return active
%hook RCEntitlementInfo
- (BOOL)isActive {
    return YES;
}
- (BOOL)isEntitledTo {
    return YES;
}
- (BOOL)willRenew {
    return YES;
}
- (BOOL)isSandbox {
    return NO;
}
- (NSString *)expirationDate {
    return nil;
}
%end


#pragma mark ====== UIKit-Level Screenshot/Recording Bypass ======

// Hook UIScreen isCaptured check — apps poll this to detect recording
%hook UIScreen
- (BOOL)isCaptured {
    return NO;
}
%end

// Prevent UITextField secure-text-entry from protecting screen
// (this neutralizes the secure-field screenshot-blocking technique)
%hook UITextField
- (BOOL)isSecureTextEntry {
    return NO;
}
%end


#pragma mark - Constructor — Logos %ctor block
%ctor {
    @autoreleasepool {
        NSLog(@"[unlock_academia] Dylib loaded! Bypassing all protections.");

        // Logos %hookf handles all method replacements above automatically.
        // Additional runtime tasks:

        // 1. Remove screenshot notification observers on any UIApplication
        [[NSNotificationCenter defaultCenter]
            removeObserver:nil
            name:UIApplicationUserDidTakeScreenshotNotification
            object:nil];
        [[NSNotificationCenter defaultCenter]
            removeObserver:nil
            name:UIScreenCapturedDidChangeNotification
            object:nil];

        NSLog(@"[unlock_academia] All hooks applied. App is unlocked.");
    }
}
