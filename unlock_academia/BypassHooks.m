#import "BypassHooks.h"
#import "BypassSettings.h"
#import "SwizzleHelper.h"
#import <objc/message.h>
#import <UIKit/UIKit.h>

// Original IMP pointers for fallback
static IMP orig_safe_isJailbroken = NULL;
static IMP orig_safe_isJailBroken = NULL;
static IMP orig_safe_isJailBrokenCustom = NULL;
static IMP orig_safe_hasJailbreakPaths = NULL;
static IMP orig_safe_hasJailbreakProcesses = NULL;
static IMP orig_safe_canOpenJailbreakSchemes = NULL;
static IMP orig_safe_hasJailbreakEnvironmentVariables = NULL;
static IMP orig_safe_canViolateSandbox = NULL;
static IMP orig_safe_hasSuspiciousSymlinks = NULL;
static IMP orig_safe_isSimulator = NULL;
static IMP orig_safe_canAccessPath = NULL;
static IMP orig_safe_getJailbreakDetails = NULL;

static IMP orig_safePlugin_isJailBroken = NULL;
static IMP orig_safePlugin_isJailBrokenCustom = NULL;
static IMP orig_safePlugin_isRealDevice = NULL;
static IMP orig_safePlugin_hasLegitimateEnv = NULL;
static IMP orig_safePlugin_isDevEnv = NULL;
static IMP orig_safePlugin_hasObviousSigns = NULL;
static void (*orig_safePlugin_handleCall)(id, SEL, id, id) = NULL;

static IMP orig_uiscreen_isCaptured = NULL;
static IMP orig_uitextfield_isSecureTextEntry = NULL;
static void (*orig_setSecureTextEntry)(id, SEL, BOOL) = NULL;

static IMP orig_rc_entitlementInfo_isActive = NULL;
static IMP orig_rc_entitlementInfo_isActiveInCurrentEnvironment = NULL;
static id (*orig_rc_entitlementInfos_all)(id, SEL) = NULL;
static void (*orig_rc_handleCall)(id, SEL, id, id) = NULL;

static void (*orig_setCallHandler)(id, SEL, id) = NULL;

#pragma mark - Hook Implementations

// SafeDeviceJailbreakDetection Class Hook methods
static BOOL safe_isJailbroken(id self, SEL _cmd) {
    if ([BypassSettings isDRMBypassActive]) return NO;
    if (orig_safe_isJailbroken) return ((BOOL (*)(id, SEL))orig_safe_isJailbroken)(self, _cmd);
    return YES;
}
static BOOL safe_isJailBroken(id self, SEL _cmd) {
    if ([BypassSettings isDRMBypassActive]) return NO;
    if (orig_safe_isJailBroken) return ((BOOL (*)(id, SEL))orig_safe_isJailBroken)(self, _cmd);
    return YES;
}
static BOOL safe_isJailBrokenCustom(id self, SEL _cmd) {
    if ([BypassSettings isDRMBypassActive]) return NO;
    if (orig_safe_isJailBrokenCustom) return ((BOOL (*)(id, SEL))orig_safe_isJailBrokenCustom)(self, _cmd);
    return YES;
}
static BOOL safe_hasJailbreakPaths(id self, SEL _cmd) {
    if ([BypassSettings isDRMBypassActive]) return NO;
    if (orig_safe_hasJailbreakPaths) return ((BOOL (*)(id, SEL))orig_safe_hasJailbreakPaths)(self, _cmd);
    return YES;
}
static BOOL safe_hasJailbreakProcesses(id self, SEL _cmd) {
    if ([BypassSettings isDRMBypassActive]) return NO;
    if (orig_safe_hasJailbreakProcesses) return ((BOOL (*)(id, SEL))orig_safe_hasJailbreakProcesses)(self, _cmd);
    return YES;
}
static BOOL safe_canOpenJailbreakSchemes(id self, SEL _cmd) {
    if ([BypassSettings isDRMBypassActive]) return NO;
    if (orig_safe_canOpenJailbreakSchemes) return ((BOOL (*)(id, SEL))orig_safe_canOpenJailbreakSchemes)(self, _cmd);
    return YES;
}
static BOOL safe_hasJailbreakEnvironmentVariables(id self, SEL _cmd) {
    if ([BypassSettings isDRMBypassActive]) return NO;
    if (orig_safe_hasJailbreakEnvironmentVariables) return ((BOOL (*)(id, SEL))orig_safe_hasJailbreakEnvironmentVariables)(self, _cmd);
    return YES;
}
static BOOL safe_canViolateSandbox(id self, SEL _cmd) {
    if ([BypassSettings isDRMBypassActive]) return NO;
    if (orig_safe_canViolateSandbox) return ((BOOL (*)(id, SEL))orig_safe_canViolateSandbox)(self, _cmd);
    return YES;
}
static BOOL safe_hasSuspiciousSymlinks(id self, SEL _cmd) {
    if ([BypassSettings isDRMBypassActive]) return NO;
    if (orig_safe_hasSuspiciousSymlinks) return ((BOOL (*)(id, SEL))orig_safe_hasSuspiciousSymlinks)(self, _cmd);
    return YES;
}
static BOOL safe_isSimulator(id self, SEL _cmd) {
    if ([BypassSettings isDRMBypassActive]) return NO;
    if (orig_safe_isSimulator) return ((BOOL (*)(id, SEL))orig_safe_isSimulator)(self, _cmd);
    return YES;
}
static BOOL safe_canAccessPath(id self, SEL _cmd, NSString *p) {
    if ([BypassSettings isDRMBypassActive]) return NO;
    if (orig_safe_canAccessPath) return ((BOOL (*)(id, SEL, id))orig_safe_canAccessPath)(self, _cmd, p);
    return YES;
}
static id safe_getJailbreakDetails(id self, SEL _cmd) {
    if ([BypassSettings isDRMBypassActive]) return @{};
    if (orig_safe_getJailbreakDetails) return ((id (*)(id, SEL))orig_safe_getJailbreakDetails)(self, _cmd);
    return @{@"isJailbroken": @YES};
}

// SafeDevicePlugin Instance Hook methods
static id safePlugin_isJailBroken(id self, SEL _cmd) {
    if ([BypassSettings isDRMBypassActive]) return @{@"isJailBroken": @NO};
    if (orig_safePlugin_isJailBroken) return ((id (*)(id, SEL))orig_safePlugin_isJailBroken)(self, _cmd);
    return @{@"isJailBroken": @YES};
}
static id safePlugin_isJailBrokenCustom(id self, SEL _cmd) {
    if ([BypassSettings isDRMBypassActive]) return @{@"isJailBroken": @NO};
    if (orig_safePlugin_isJailBrokenCustom) return ((id (*)(id, SEL))orig_safePlugin_isJailBrokenCustom)(self, _cmd);
    return @{@"isJailBroken": @YES};
}
static id safePlugin_isRealDevice(id self, SEL _cmd) {
    if ([BypassSettings isDRMBypassActive]) return @YES;
    if (orig_safePlugin_isRealDevice) return ((id (*)(id, SEL))orig_safePlugin_isRealDevice)(self, _cmd);
    return @NO;
}
static id safePlugin_hasLegitimateEnv(id self, SEL _cmd) {
    if ([BypassSettings isDRMBypassActive]) return @YES;
    if (orig_safePlugin_hasLegitimateEnv) return ((id (*)(id, SEL))orig_safePlugin_hasLegitimateEnv)(self, _cmd);
    return @NO;
}
static id safePlugin_isDevEnv(id self, SEL _cmd) {
    if ([BypassSettings isDRMBypassActive]) return @NO;
    if (orig_safePlugin_isDevEnv) return ((id (*)(id, SEL))orig_safePlugin_isDevEnv)(self, _cmd);
    return @YES;
}
static id safePlugin_hasObviousSigns(id self, SEL _cmd) {
    if ([BypassSettings isDRMBypassActive]) return @NO;
    if (orig_safePlugin_hasObviousSigns) return ((id (*)(id, SEL))orig_safePlugin_hasObviousSigns)(self, _cmd);
    return @YES;
}

static void safePlugin_handleCall(id self, SEL _cmd, id call, id result) {
    if ([BypassSettings isDRMBypassActive]) {
        NSString *method = ((NSString *(*)(id, SEL))objc_msgSend)(call, @selector(method));
        if ([method containsString:@"Jail"] || [method containsString:@"jail"] ||
            [method containsString:@"jailbreak"] || [method containsString:@"Jailbreak"] ||
            [method containsString:@"Real"] || [method containsString:@"real"] ||
            [method containsString:@"Env"] || [method containsString:@"env"] ||
            [method containsString:@"Dev"] || [method containsString:@"dev"] ||
            [method containsString:@"Sign"] || [method containsString:@"sign"]) {
            void (^reply)(id) = result;
            if (reply) reply(@{@"isJailBroken": @NO, @"isRealDevice": @YES});
            return;
        }
    }
    if (orig_safePlugin_handleCall) orig_safePlugin_handleCall(self, _cmd, call, result);
}

// UIKit Hooks
static BOOL uiscreen_isCaptured(id self, SEL _cmd) {
    if ([BypassSettings isDRMBypassActive]) return NO;
    if (orig_uiscreen_isCaptured) return ((BOOL (*)(id, SEL))orig_uiscreen_isCaptured)(self, _cmd);
    return [UIScreen mainScreen].isCaptured;
}

static BOOL uitextfield_isSecureTextEntry(id self, SEL _cmd) {
    if ([BypassSettings isDRMBypassActive]) {
        // Protect passwords, bypass only screen protector layers
        UITextField *tf = (UITextField *)self;
        if (tf.delegate != nil || (tf.placeholder && tf.placeholder.length > 0)) {
            if (orig_uitextfield_isSecureTextEntry) {
                return ((BOOL (*)(id, SEL))orig_uitextfield_isSecureTextEntry)(self, _cmd);
            }
            return YES;
        }
        
        NSString *className = NSStringFromClass([self class]);
        if ([className containsString:@"SecureTextField"] || [className containsString:@"Screen"] || 
            [className containsString:@"Prevent"] || [className containsString:@"Protect"]) {
            return NO;
        }
        UIView *sv = [self superview];
        while (sv) {
            NSString *svClass = NSStringFromClass([sv class]);
            if ([svClass containsString:@"Screen"] || [svClass containsString:@"Prevent"] || 
                [svClass containsString:@"Protect"] || [svClass containsString:@"Secure"]) {
                return NO;
            }
            sv = [sv superview];
        }
        if (tf.window) {
            NSString *winClass = NSStringFromClass([tf.window class]);
            if ([winClass containsString:@"Prevent"] || [winClass containsString:@"Protect"] || [winClass containsString:@"Secure"]) {
                return NO;
            }
        }
        return NO;
    }
    if (orig_uitextfield_isSecureTextEntry) {
        return ((BOOL (*)(id, SEL))orig_uitextfield_isSecureTextEntry)(self, _cmd);
    }
    return NO;
}

static void uitextfield_setSecureTextEntry(id self, SEL _cmd, BOOL val) {
    if (val && [BypassSettings isDRMBypassActive]) {
        UITextField *tf = (UITextField *)self;
        if (tf.delegate != nil || (tf.placeholder && tf.placeholder.length > 0)) {
            if (orig_setSecureTextEntry) orig_setSecureTextEntry(self, _cmd, val);
            return;
        }
        NSLog(@"[unlock_academia] Blocked setSecureTextEntry:YES on non-input textfield");
        return;
    }
    if (orig_setSecureTextEntry) orig_setSecureTextEntry(self, _cmd, val);
}

// RevenueCat Helpers & Hooks
static id ensureRCBilling(id data) {
    NSMutableDictionary *mdict = nil;
    if ([data isKindOfClass:NSDictionary.class]) {
        mdict = [(NSDictionary *)data mutableCopy];
    } else {
        mdict = [NSMutableDictionary dictionary];
    }
    
    if (!mdict[@"originalAppUserId"]) mdict[@"originalAppUserId"] = @"unlock_academia_user";
    if (!mdict[@"schemaVersion"]) mdict[@"schemaVersion"] = @(4);
    if (!mdict[@"requestDate"]) mdict[@"requestDate"] = @"2026-01-01T00:00:00Z";
    if (!mdict[@"originalPurchaseDate"]) mdict[@"originalPurchaseDate"] = @"2026-01-01T00:00:00Z";
    
    id ents = mdict[@"entitlements"];
    NSMutableDictionary *ment = [ents isKindOfClass:NSDictionary.class] ? [ents mutableCopy] : [NSMutableDictionary dictionary];
    if (!ment[@"RC_BILLING"]) {
        ment[@"RC_BILLING"] = @{
            @"identifier": @"RC_BILLING",
            @"isActive": @YES,
            @"willRenew": @YES,
            @"periodType": @"NORMAL",
            @"latestPurchaseDate": @"2024-01-01T00:00:00Z",
            @"originalPurchaseDate": @"2024-01-01T00:00:00Z",
            @"expirationDate": @"2099-12-31T23:59:59Z",
            @"store": @"app_store",
            @"productIdentifier": @"com.speetar.academia.monthly",
            @"productPlanIdentifier": NSNull.null,
            @"purchaseDate": @"2024-01-01T00:00:00Z",
            @"ownershipType": @"PURCHASED",
        };
    }
    mdict[@"entitlements"] = ment;
    
    id expDates = mdict[@"allExpirationDates"];
    NSMutableDictionary *mexpDates = [expDates isKindOfClass:NSDictionary.class] ? [expDates mutableCopy] : [NSMutableDictionary dictionary];
    mexpDates[@"RC_BILLING"] = @"2099-12-31T23:59:59Z";
    mdict[@"allExpirationDates"] = mexpDates;
    
    id purDates = mdict[@"allPurchaseDates"];
    NSMutableDictionary *mpurDates = [purDates isKindOfClass:NSDictionary.class] ? [purDates mutableCopy] : [NSMutableDictionary dictionary];
    mpurDates[@"RC_BILLING"] = @"2024-01-01T00:00:00Z";
    mdict[@"allPurchaseDates"] = mpurDates;
    
    return [mdict copy];
}

static id wrapCustomerInfoResult(NSString *method, id data) {
    if ([method isEqualToString:@"login"]) {
        if ([data isKindOfClass:NSDictionary.class]) {
            NSMutableDictionary *mdict = [data mutableCopy];
            mdict[@"customerInfo"] = ensureRCBilling(mdict[@"customerInfo"]);
            return [mdict copy];
        }
        return @{
            @"customerInfo": ensureRCBilling(nil),
            @"created": @YES
        };
    }
    return ensureRCBilling(data);
}

static BOOL rc_entitlementInfo_isActive(id self, SEL _cmd) { return YES; }
static BOOL rc_entitlementInfo_isActiveInCurrentEnvironment(id self, SEL _cmd) { return YES; }

static id rc_entitlementInfos_all(id self, SEL _cmd) {
    id result = orig_rc_entitlementInfos_all ? orig_rc_entitlementInfos_all(self, _cmd) : nil;
    if (!result) result = @{};
    if (!result[@"RC_BILLING"]) {
        NSMutableDictionary *dict = [result mutableCopy];
        Class infoClass = NSClassFromString(@"RCEntitlementInfo");
        if (infoClass) {
            id info = ((id (*)(id, SEL))objc_msgSend)(infoClass, @selector(alloc));
            if (info) {
                info = ((id (*)(id, SEL))objc_msgSend)(info, @selector(init));
                if (info) dict[@"RC_BILLING"] = info;
            }
        }
        result = [dict copy];
    }
    return result;
}

static void rc_plugin_handleCall(id self, SEL _cmd, id call, id result) {
    NSString *method = ((NSString *(*)(id, SEL))objc_msgSend)(call, @selector(method));
    
    BOOL returnsCustomerInfo = [method isEqualToString:@"getCustomerInfo"] ||
                               [method isEqualToString:@"login"] ||
                               [method isEqualToString:@"identify"] ||
                               [method isEqualToString:@"restorePurchases"] ||
                               [method isEqualToString:@"purchaseProduct"] ||
                               [method isEqualToString:@"purchasePackage"] ||
                               [method isEqualToString:@"syncPurchases"];
                               
    if (returnsCustomerInfo) {
        void (^origResult)(id) = result;
        void (^wrapped)(id) = ^(id data) {
            origResult(wrapCustomerInfoResult(method, data));
        };
        if (orig_rc_handleCall) {
            orig_rc_handleCall(self, _cmd, call, (id)wrapped);
        } else {
            wrapped(nil);
        }
        return;
    }
    
    if ([BypassSettings isFreePurchasesEnabled]) {
        if ([method containsString:@"purchase"] || [method containsString:@"Purchase"] ||
            [method containsString:@"buy"] || [method containsString:@"Buy"] ||
            [method containsString:@"restore"] || [method containsString:@"Restore"]) {
            void (^reply)(id) = result;
            if (reply) reply(@{
                @"productIdentifier": @"com.speetar.academia.monthly",
                @"transactionIdentifier": @"unlock_academia_free",
                @"transactionDate": @"2024-01-01T00:00:00Z",
                @"status": @"success",
            });
            return;
        }
    }
    
    if (orig_rc_handleCall) orig_rc_handleCall(self, _cmd, call, result);
}

// Flutter method call handler wrapping
static void hooked_setMethodCallHandler(id self, SEL _cmd, id handler) {
    NSString *channelName = [self valueForKey:@"name"];

    if (handler && [channelName length] > 0) {
        void (^origHandler)(id, id) = handler;
        void (^wrappedHandler)(id, id) = ^(id call, id result) {
            NSString *method = [call valueForKey:@"method"];
            id args = [call valueForKey:@"arguments"];

            // --- Wallet methods ---
            if ([channelName containsString:@"wallet"] ||
                [channelName containsString:@"balance"] ||
                [channelName containsString:@"Wallet"] ||
                [channelName containsString:@"Balance"]) {

                if ([method containsString:@"get"] || [method containsString:@"fetch"] ||
                    [method containsString:@"Get"] || [method containsString:@"Fetch"]) {
                    ((void (^)(id))result)(@([BypassSettings getWalletBalance]));
                    return;
                }
                if ([method containsString:@"add"] || [method containsString:@"Add"]) {
                    double amount = 0;
                    if ([args isKindOfClass:NSNumber.class]) amount = [args doubleValue];
                    else if ([args isKindOfClass:NSDictionary.class]) amount = [[args valueForKey:@"amount"] doubleValue];
                    if (amount > 0) [BypassSettings addWalletBalance:amount];
                    ((void (^)(id))result)(@([BypassSettings getWalletBalance]));
                    return;
                }
                if ([method containsString:@"spend"] || [method containsString:@"deduct"] ||
                    [method containsString:@"Spend"] || [method containsString:@"Deduct"]) {
                    double amount = 0;
                    if ([args isKindOfClass:NSNumber.class]) amount = [args doubleValue];
                    else if ([args isKindOfClass:NSDictionary.class]) amount = [[args valueForKey:@"amount"] doubleValue];
                    double bal = [BypassSettings getWalletBalance];
                    if (amount > 0 && bal >= amount) {
                        [BypassSettings setWalletBalance:bal - amount];
                        ((void (^)(id))result)(@([BypassSettings getWalletBalance]));
                    } else {
                        Class fe = NSClassFromString(@"FlutterError");
                        if (fe) {
                            id (*msgSend_3id)(id, SEL, id, id, id) = (id (*)(id, SEL, id, id, id))objc_msgSend;
                            ((void (^)(id))result)(msgSend_3id(fe, @selector(errorWithCode:message:details:), @"INSUFFICIENT_FUNDS", @"رصيد غير كافٍ", nil));
                        } else {
                            ((void (^)(id))result)(@{@"error": @"INSUFFICIENT_FUNDS", @"message": @"رصيد غير كافٍ"});
                        }
                    }
                    return;
                }
            }

            // --- Free purchases ---
            if ([BypassSettings isFreePurchasesEnabled]) {
                if ([method containsString:@"purchase"] || [method containsString:@"buy"] ||
                    [method containsString:@"Purchase"] || [method containsString:@"Buy"] ||
                    [method containsString:@"checkout"] || [method containsString:@"Checkout"]) {
                    ((void (^)(id))result)(@{@"status": @"success", @"transactionId": @"unlock_academia_free"});
                    return;
                }
            }

            // --- DRM / License methods ---
            if ([BypassSettings isDRMBypassActive]) {
                if ([method containsString:@"license"] || [method containsString:@"License"] ||
                    [method containsString:@"drm"] || [method containsString:@"DRM"] ||
                    [method containsString:@"verify"] || [method containsString:@"Verify"] ||
                    [method containsString:@"authenticate"] || [method containsString:@"Authenticate"]) {
                    ((void (^)(id))result)(@{@"status": @"valid", @"licensed": @YES});
                    return;
                }
            }
            
            // --- Intercept app.security/screen_protection for Fail-Closed Gate compatibility ---
            if ([channelName isEqualToString:@"app.security/screen_protection"]) {
                if ([method isEqualToString:@"enableScreenshotBlocking"]) {
                    if ([BypassSettings isDRMBypassActive]) {
                        ((void (^)(id))result)(@{
                            @"ok": @YES,
                            @"message": @"Bypassed screen protection successfully",
                            @"logs": @[@"Dylib bypassed native protection check"]
                        });
                        return;
                    }
                }
            }

            origHandler(call, result);
        };
        orig_setCallHandler(self, _cmd, wrappedHandler);
    } else {
        orig_setCallHandler(self, _cmd, handler);
    }
}

@implementation BypassHooks

+ (void)applyUIKitHooks {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [SwizzleHelper swizzleInstanceMethod:[UIScreen class] selector:@selector(isCaptured) hookIMP:(IMP)uiscreen_isCaptured originalIMPPair:&orig_uiscreen_isCaptured];
        [SwizzleHelper swizzleInstanceMethod:[UITextField class] selector:@selector(isSecureTextEntry) hookIMP:(IMP)uitextfield_isSecureTextEntry originalIMPPair:&orig_uitextfield_isSecureTextEntry];

        Method setterM = class_getInstanceMethod([UITextField class], @selector(setSecureTextEntry:));
        if (setterM) {
            orig_setSecureTextEntry = (void (*)(id, SEL, BOOL))method_getImplementation(setterM);
            method_setImplementation(setterM, (IMP)uitextfield_setSecureTextEntry);
        }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
        [NSNotificationCenter.defaultCenter removeObserver:nil
            name:UIApplicationUserDidTakeScreenshotNotification object:nil];
        [NSNotificationCenter.defaultCenter removeObserver:nil
            name:UIScreenCapturedDidChangeNotification object:nil];
#pragma clang diagnostic pop

        NSLog(@"[unlock_academia] UIKit hooks applied");
    });
}

+ (void)applySafeDeviceHooks {
    Class sdClass = NSClassFromString(@"SafeDeviceJailbreakDetection");
    if (sdClass) {
        Class meta = object_getClass(sdClass);
        [SwizzleHelper swizzleInstanceMethod:meta selector:@selector(isJailbroken) hookIMP:(IMP)safe_isJailbroken originalIMPPair:&orig_safe_isJailbroken];
        [SwizzleHelper swizzleInstanceMethod:meta selector:@selector(isJailBroken) hookIMP:(IMP)safe_isJailBroken originalIMPPair:&orig_safe_isJailBroken];
        [SwizzleHelper swizzleInstanceMethod:meta selector:@selector(isJailBrokenCustom) hookIMP:(IMP)safe_isJailBrokenCustom originalIMPPair:&orig_safe_isJailBrokenCustom];
        [SwizzleHelper swizzleInstanceMethod:meta selector:@selector(hasJailbreakPaths) hookIMP:(IMP)safe_hasJailbreakPaths originalIMPPair:&orig_safe_hasJailbreakPaths];
        [SwizzleHelper swizzleInstanceMethod:meta selector:@selector(hasJailbreakProcesses) hookIMP:(IMP)safe_hasJailbreakProcesses originalIMPPair:&orig_safe_hasJailbreakProcesses];
        [SwizzleHelper swizzleInstanceMethod:meta selector:@selector(canOpenJailbreakSchemes) hookIMP:(IMP)safe_canOpenJailbreakSchemes originalIMPPair:&orig_safe_canOpenJailbreakSchemes];
        [SwizzleHelper swizzleInstanceMethod:meta selector:@selector(hasJailbreakEnvironmentVariables) hookIMP:(IMP)safe_hasJailbreakEnvironmentVariables originalIMPPair:&orig_safe_hasJailbreakEnvironmentVariables];
        [SwizzleHelper swizzleInstanceMethod:meta selector:@selector(canViolateSandbox) hookIMP:(IMP)safe_canViolateSandbox originalIMPPair:&orig_safe_canViolateSandbox];
        [SwizzleHelper swizzleInstanceMethod:meta selector:@selector(hasSuspiciousSymlinks) hookIMP:(IMP)safe_hasSuspiciousSymlinks originalIMPPair:&orig_safe_hasSuspiciousSymlinks];
        [SwizzleHelper swizzleInstanceMethod:meta selector:@selector(isSimulator) hookIMP:(IMP)safe_isSimulator originalIMPPair:&orig_safe_isSimulator];
        [SwizzleHelper swizzleInstanceMethod:meta selector:@selector(getJailbreakDetails) hookIMP:(IMP)safe_getJailbreakDetails originalIMPPair:&orig_safe_getJailbreakDetails];
        [SwizzleHelper swizzleInstanceMethod:meta selector:@selector(canAccessPath:) hookIMP:(IMP)safe_canAccessPath originalIMPPair:&orig_safe_canAccessPath];
        NSLog(@"[unlock_academia] SafeDeviceJailbreakDetection class methods hooked");
    }

    Class sdPlugin = NSClassFromString(@"SafeDevicePlugin");
    if (sdPlugin) {
        [SwizzleHelper swizzleInstanceMethod:sdPlugin selector:@selector(isJailBroken) hookIMP:(IMP)safePlugin_isJailBroken originalIMPPair:&orig_safePlugin_isJailBroken];
        [SwizzleHelper swizzleInstanceMethod:sdPlugin selector:@selector(isJailBrokenCustom) hookIMP:(IMP)safePlugin_isJailBrokenCustom originalIMPPair:&orig_safePlugin_isJailBrokenCustom];
        [SwizzleHelper swizzleInstanceMethod:sdPlugin selector:@selector(isRealDevice) hookIMP:(IMP)safePlugin_isRealDevice originalIMPPair:&orig_safePlugin_isRealDevice];
        [SwizzleHelper swizzleInstanceMethod:sdPlugin selector:@selector(hasLegitimateEnvironmentVariables) hookIMP:(IMP)safePlugin_hasLegitimateEnv originalIMPPair:&orig_safePlugin_hasLegitimateEnv];
        [SwizzleHelper swizzleInstanceMethod:sdPlugin selector:@selector(isDevelopmentEnvironment) hookIMP:(IMP)safePlugin_isDevEnv originalIMPPair:&orig_safePlugin_isDevEnv];
        [SwizzleHelper swizzleInstanceMethod:sdPlugin selector:@selector(hasObviousJailbreakSigns) hookIMP:(IMP)safePlugin_hasObviousSigns originalIMPPair:&orig_safePlugin_hasObviousSigns];
        
        if (!orig_safePlugin_handleCall) {
            Method hm = class_getInstanceMethod(sdPlugin, @selector(handleMethodCall:result:));
            if (hm) {
                orig_safePlugin_handleCall = (void (*)(id, SEL, id, id))method_getImplementation(hm);
                method_setImplementation(hm, (IMP)safePlugin_handleCall);
            }
        }
        NSLog(@"[unlock_academia] SafeDevicePlugin instance methods hooked");
    }

    Class dttClass = NSClassFromString(@"DTTJailbreakDetection");
    if (dttClass) {
        Class meta = object_getClass(dttClass);
        [SwizzleHelper swizzleInstanceMethod:meta selector:@selector(isJailbroken) hookIMP:(IMP)safe_isJailbroken originalIMPPair:&orig_safe_isJailbroken];
        [SwizzleHelper swizzleInstanceMethod:meta selector:@selector(isPirated) hookIMP:(IMP)safe_isJailbroken originalIMPPair:&orig_safe_isJailbroken];
        NSLog(@"[unlock_academia] DTTJailbreakDetection hooked");
    }
}

+ (void)applyScreenPreventerHooks {
    NSArray *names = @[
        @"ScreenPreventer", @"ScreenshotPreventer", @"ScreenPreventerStore",
        @"ScreenshotProtectionOverlay",
        @"_TtC18ScreenPreventerKit15ScreenPreventer",
        @"_TtC18ScreenPreventerKit19ScreenshotPreventer",
        @"_TtC18ScreenPreventerKit20ScreenPreventerStore",
        @"_TtC18ScreenPreventerKit27ScreenshotProtectionOverlay",
    ];
    for (NSString *name in names) {
        Class c = NSClassFromString(name);
        if (!c) continue;
        
        SEL candidates[] = {
            @selector(enabledPreventScreenshot),
            @selector(enabled),
            @selector(enabledPreventScreenRecording),
            @selector(isEnabled),
            @selector(enabledPreventScreenshotCapture),
        };
        for (int i = 0; i < 5; i++) {
            [SwizzleHelper swizzleInstanceMethod:c selector:candidates[i] returnValIfBypassed:NO];
        }
        
        SEL enableSel = NSSelectorFromString(@"enablePreventScreenshot");
        [SwizzleHelper swizzleInstanceMethodVoid:c selector:enableSel];
        
        NSLog(@"[unlock_academia] ScreenPreventerKit class dynamically hooked: %@", name);
    }
}

+ (void)applyRevenueCatHooks {
    Class infoClass = NSClassFromString(@"RCEntitlementInfo");
    if (infoClass) {
        [SwizzleHelper swizzleInstanceMethod:infoClass selector:@selector(isActive) hookIMP:(IMP)rc_entitlementInfo_isActive originalIMPPair:&orig_rc_entitlementInfo_isActive];
        [SwizzleHelper swizzleInstanceMethod:infoClass selector:@selector(isActiveInCurrentEnvironment) hookIMP:(IMP)rc_entitlementInfo_isActiveInCurrentEnvironment originalIMPPair:&orig_rc_entitlementInfo_isActiveInCurrentEnvironment];
        NSLog(@"[unlock_academia] RCEntitlementInfo hooked");
    }

    Class infosClass = NSClassFromString(@"RCEntitlementInfos");
    if (infosClass) {
        Method allM = class_getInstanceMethod(infosClass, @selector(all));
        if (allM && !orig_rc_entitlementInfos_all) {
            orig_rc_entitlementInfos_all = (id (*)(id, SEL))method_getImplementation(allM);
            method_setImplementation(allM, (IMP)rc_entitlementInfos_all);
        }
        NSLog(@"[unlock_academia] RCEntitlementInfos hooked");
    }

    Class pluginClass = NSClassFromString(@"PurchasesFlutterPlugin");
    if (pluginClass && !orig_rc_handleCall) {
        Method hm = class_getInstanceMethod(pluginClass, @selector(handleMethodCall:result:));
        if (hm) {
            orig_rc_handleCall = (void (*)(id, SEL, id, id))method_getImplementation(hm);
            method_setImplementation(hm, (IMP)rc_plugin_handleCall);
        }
        NSLog(@"[unlock_academia] PurchasesFlutterPlugin hooked");
    }

    Class pluginRegistrar = NSClassFromString(@"PurchasesPlugin");
    if (!pluginRegistrar) pluginRegistrar = NSClassFromString(@"RCPurchasesPlugin");
    if (pluginRegistrar && !orig_rc_handleCall) {
        Method hm2 = class_getInstanceMethod(pluginRegistrar, @selector(handleMethodCall:result:));
        if (!hm2) hm2 = class_getInstanceMethod(pluginRegistrar, @selector(handle:result:));
        if (hm2) {
            orig_rc_handleCall = (void (*)(id, SEL, id, id))method_getImplementation(hm2);
            method_setImplementation(hm2, (IMP)rc_plugin_handleCall);
            NSLog(@"[unlock_academia] %@ handle hooked", pluginRegistrar);
        }
    }
}

+ (void)applyFlutterChannelHooks {
    Class channelClass = NSClassFromString(@"FlutterMethodChannel");
    if (channelClass) {
        Method m = class_getInstanceMethod(channelClass, @selector(setMethodCallHandler:));
        if (m && !orig_setCallHandler) {
            orig_setCallHandler = (void (*)(id, SEL, id))method_getImplementation(m);
            method_setImplementation(m, (IMP)hooked_setMethodCallHandler);
            NSLog(@"[unlock_academia] FlutterMethodChannel hooked");
        }
    }
}

+ (void)recursiveDisableSecure:(UIView *)view {
    if ([view isKindOfClass:UITextField.class]) {
        UITextField *tf = (UITextField *)view;
        // Protect passwords, bypass only screen protector layers
        if (tf.delegate == nil && (!tf.placeholder || tf.placeholder.length == 0)) {
            [tf setSecureTextEntry:NO];
        }
    }
    for (UIView *sub in view.subviews) {
        [self recursiveDisableSecure:sub];
    }
}

+ (void)scanAndDisableSecureTextFields {
    if (![BypassSettings isDRMBypassActive]) return;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *win in ((UIWindowScene *)scene).windows) {
            [self recursiveDisableSecure:win];
        }
    }
}

@end
