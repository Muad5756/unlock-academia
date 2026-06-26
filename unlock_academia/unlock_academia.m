#import <objc/runtime.h>
#import <objc/message.h>
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#pragma mark - NSUserDefaults Keys

static NSString *const kUDWalletBalance = @"com.unlock.wallet.balance";
static NSString *const kUDDRMEnabled = @"com.unlock.drm.enabled";
static NSString *const kUDFreePurchases = @"com.unlock.freepurchases.enabled";

#pragma mark - Constants

static const double kDefaultWalletBalance = 10000.0;

#pragma mark - Toggle State Helpers

static BOOL isDRMEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kUDDRMEnabled];
}

static BOOL isFreePurchasesEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kUDFreePurchases];
}

static void setDRMEnabled(BOOL val) {
    [[NSUserDefaults standardUserDefaults] setBool:val forKey:kUDDRMEnabled];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static void setFreePurchasesEnabled(BOOL val) {
    [[NSUserDefaults standardUserDefaults] setBool:val forKey:kUDFreePurchases];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - Wallet Helpers

static double getWalletBalance(void) {
    double bal = [[NSUserDefaults standardUserDefaults] doubleForKey:kUDWalletBalance];
    if (bal < 0.01) bal = kDefaultWalletBalance;
    return bal;
}

static void setWalletBalance(double val) {
    [[NSUserDefaults standardUserDefaults] setDouble:val forKey:kUDWalletBalance];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static void addWalletBalance(double amount) {
    setWalletBalance(getWalletBalance() + amount);
}

static NSString *formatBalance(double bal) {
    NSNumberFormatter *fmt = [[NSNumberFormatter alloc] init];
    fmt.numberStyle = NSNumberFormatterDecimalStyle;
    fmt.minimumFractionDigits = 2;
    fmt.maximumFractionDigits = 2;
    return [NSString stringWithFormat:@"%@ ر.س", [fmt stringFromNumber:@(bal)]];
}

#pragma mark - Swizzle Helpers

static void swz(Class cls, SEL sel, IMP newImp, IMP *oldOut) {
    Method m = class_getInstanceMethod(cls, sel);
    if (m) { *oldOut = method_setImplementation(m, newImp); }
}

static void swzIfSafe(Class cls, SEL sel, IMP newImp) {
    IMP dummy;
    swz(cls, sel, newImp, &dummy);
}

static void swzClassIfSafe(Class cls, SEL sel, IMP newImp) {
    swz(object_getClass(cls), sel, newImp, &(IMP){0});
}

#pragma mark - Flutter Method Channel Hook

static void (*orig_setCallHandler)(id, SEL, id);

static void hooked_setMethodCallHandler(id self, SEL _cmd, id handler) {
    NSString *channelName = [self valueForKey:@"name"];

    if (handler && [channelName length] > 0) {
        void (^origHandler)(id, id) = handler;
        void (^wrappedHandler)(id, id) = ^(id call, id result) {
            NSString *method = [call valueForKey:@"method"];
            id args = [call valueForKey:@"arguments"];

            // --- Wallet methods (always intercepted) ---
            if ([channelName containsString:@"wallet"] ||
                [channelName containsString:@"balance"] ||
                [channelName containsString:@"Wallet"] ||
                [channelName containsString:@"Balance"]) {

                if ([method containsString:@"get"] || [method containsString:@"fetch"] ||
                    [method containsString:@"Get"] || [method containsString:@"Fetch"]) {
                    ((void (^)(id))result)(@(getWalletBalance()));
                    return;
                }
                if ([method containsString:@"add"] || [method containsString:@"Add"]) {
                    double amount = 0;
                    if ([args isKindOfClass:NSNumber.class]) amount = [args doubleValue];
                    else if ([args isKindOfClass:NSDictionary.class]) amount = [[args valueForKey:@"amount"] doubleValue];
                    if (amount > 0) addWalletBalance(amount);
                    ((void (^)(id))result)(@(getWalletBalance()));
                    return;
                }
                if ([method containsString:@"spend"] || [method containsString:@"deduct"] ||
                    [method containsString:@"Spend"] || [method containsString:@"Deduct"]) {
                    double amount = 0;
                    if ([args isKindOfClass:NSNumber.class]) amount = [args doubleValue];
                    else if ([args isKindOfClass:NSDictionary.class]) amount = [[args valueForKey:@"amount"] doubleValue];
                    double bal = getWalletBalance();
                    if (amount > 0 && bal >= amount) {
                        setWalletBalance(bal - amount);
                        ((void (^)(id))result)(@(getWalletBalance()));
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

            // --- Free purchases (intercepted based on toggle) ---
            if (isFreePurchasesEnabled()) {
                if ([method containsString:@"purchase"] || [method containsString:@"buy"] ||
                    [method containsString:@"Purchase"] || [method containsString:@"Buy"] ||
                    [method containsString:@"checkout"] || [method containsString:@"Checkout"]) {
                    ((void (^)(id))result)(@{@"status": @"success", @"transactionId": @"unlock_academia_free"});
                    return;
                }
            }

            // --- DRM / License methods (intercepted based on toggle) ---
            if (isDRMEnabled()) {
                if ([method containsString:@"license"] || [method containsString:@"License"] ||
                    [method containsString:@"drm"] || [method containsString:@"DRM"] ||
                    [method containsString:@"verify"] || [method containsString:@"Verify"] ||
                    [method containsString:@"authenticate"] || [method containsString:@"Authenticate"]) {
                    ((void (^)(id))result)(@{@"status": @"valid", @"licensed": @YES});
                    return;
                }
            }

            origHandler(call, result);
        };
        orig_setCallHandler(self, _cmd, wrappedHandler);
    } else {
        orig_setCallHandler(self, _cmd, handler);
    }
}

static void applyFlutterChannelHook(void) {
    Class channelClass = NSClassFromString(@"FlutterMethodChannel");
    if (channelClass) {
        Method m = class_getInstanceMethod(channelClass, @selector(setMethodCallHandler:));
        if (m) {
            orig_setCallHandler = (void (*)(id, SEL, id))method_getImplementation(m);
            method_setImplementation(m, (IMP)hooked_setMethodCallHandler);
            NSLog(@"[unlock_academia] FlutterMethodChannel hooked");
        }
    }
}

#pragma mark - UI / Menu System

static UIButton *menuBtn = nil;

static UIViewController *topVC(void) {
    UIViewController *vc = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

static void showWalletMenu(void) {
    UIViewController *vc = topVC();
    if (!vc) return;

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"المحفظة"
        message:[NSString stringWithFormat:@"الرصيد الحالي: %@", formatBalance(getWalletBalance())]
        preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"➕ إضافة ١٠٠٠ ر.س"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        addWalletBalance(1000.0);
        showWalletMenu();
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"➕➕ إضافة ٥٠٠٠ ر.س"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        addWalletBalance(5000.0);
        showWalletMenu();
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"➕➕➕ إضافة ١٠٠٠٠ ر.س"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        addWalletBalance(10000.0);
        showWalletMenu();
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"🔄 تعيين الرصيد إلى ١٠٠٠٠٠ ر.س"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        setWalletBalance(100000.0);
        showWalletMenu();
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"🔙 رجوع"
        style:UIAlertActionStyleCancel handler:nil]];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = menuBtn;
        sheet.popoverPresentationController.sourceRect = menuBtn.bounds;
    }
    [vc presentViewController:sheet animated:YES completion:nil];
}

static void showMainMenu(void) {
    UIViewController *vc = topVC();
    if (!vc) return;

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"قائمة التحكم"
        message:@"unlock_academia" preferredStyle:UIAlertControllerStyleActionSheet];

    // Wallet
    [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"💰 المحفظة — %@", formatBalance(getWalletBalance())]
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        showWalletMenu();
    }]];

    // DRM Toggle
    if (isDRMEnabled()) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"🔓 تعطيل حماية DRM ✅"
            style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            setDRMEnabled(NO);
            showMainMenu();
        }]];
    } else {
        [sheet addAction:[UIAlertAction actionWithTitle:@"🔒 تفعيل حماية DRM ❌"
            style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            setDRMEnabled(YES);
            showMainMenu();
        }]];
    }

    // Free Purchases Toggle
    if (isFreePurchasesEnabled()) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"🛒 شراء الكورسات مجانا ✅"
            style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            setFreePurchasesEnabled(NO);
            showMainMenu();
        }]];
    } else {
        [sheet addAction:[UIAlertAction actionWithTitle:@"🛒 شراء الكورسات مجانا ❌"
            style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            setFreePurchasesEnabled(YES);
            showMainMenu();
        }]];
    }

    // Status
    [sheet addAction:[UIAlertAction actionWithTitle:@"ℹ️ حالة النظام"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *status = [NSString stringWithFormat:
            @"المحفظة: %@\n\n"
            @"حماية DRM: %@\n"
            @"شراء مجاني: %@\n\n"
            @"✅ منع التصوير: مفعل\n"
            @"✅ كشف الجيلبريك: معطل\n"
            @"✅ RevenueCat: RC_BILLING نشط",
            formatBalance(getWalletBalance()),
            isDRMEnabled() ? @"✅ مفعل" : @"❌ معطل",
            isFreePurchasesEnabled() ? @"✅ مفعل" : @"❌ معطل"];
        UIAlertController *sub = [UIAlertController alertControllerWithTitle:@"حالة النظام"
            message:status preferredStyle:UIAlertControllerStyleAlert];
        [sub addAction:[UIAlertAction actionWithTitle:@"حسنا" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            showMainMenu();
        }]];
        [vc presentViewController:sub animated:YES completion:nil];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"❌ إغلاق"
        style:UIAlertActionStyleCancel handler:nil]];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = menuBtn;
        sheet.popoverPresentationController.sourceRect = menuBtn.bounds;
    }
    [vc presentViewController:sheet animated:YES completion:nil];
}

static void addFloatingMenuButton(void) {
    if (menuBtn) return;
    UIWindow *win = UIApplication.sharedApplication.keyWindow;
    if (!win) return;

    CGFloat sz = 52;
    CGFloat pad = 16;
    menuBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    menuBtn.frame = CGRectMake(pad, 100 + pad, sz, sz);
    menuBtn.backgroundColor = [UIColor colorWithRed:0.85 green:0.12 blue:0.12 alpha:0.90];
    menuBtn.layer.cornerRadius = sz / 2;
    menuBtn.clipsToBounds = YES;
    menuBtn.tintColor = UIColor.whiteColor;
    [menuBtn setPreferredSymbolConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:24]
        forImageInState:UIControlStateNormal];
    [menuBtn setImage:[UIImage systemImageNamed:@"bolt.fill"] forState:UIControlStateNormal];
    menuBtn.layer.borderWidth = 1.5;
    menuBtn.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.3].CGColor;
    menuBtn.accessibilityLabel = @"unlock_academia menu";

    if (@available(iOS 14, *)) {
        [menuBtn addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
            showMainMenu();
        }] forControlEvents:UIControlEventTouchUpInside];
    }

    UIPanGestureRecognizer *drag = [[UIPanGestureRecognizer alloc] initWithTarget:nil action:nil];
    [drag addTarget:[NSObject new] action:@selector(__unlock_dragButton:)];
    objc_setAssociatedObject(drag, @selector(__unlock_dragButton:), menuBtn, OBJC_ASSOCIATION_RETAIN);
    [menuBtn addGestureRecognizer:drag];

    [win addSubview:menuBtn];
    [win bringSubviewToFront:menuBtn];
    NSLog(@"[unlock_academia] Floating menu button added");
}

// Drag support via method swizzling on NSObject
static void unlock_dragButton(id self, SEL _cmd, UIPanGestureRecognizer *gesture) {
    UIButton *btn = objc_getAssociatedObject(gesture, @selector(__unlock_dragButton:));
    if (!btn) return;
    UIView *parent = btn.superview;
    if (!parent) return;
    CGPoint pt = [gesture translationInView:parent];
    btn.transform = CGAffineTransformTranslate(btn.transform, pt.x, pt.y);
    [gesture setTranslation:CGPointZero inView:parent];
}

#pragma mark - Jailbreak Detection Bypasses (respect DRM toggle)

static BOOL safe_isJailbroken(id self, SEL _cmd) {
    return isDRMEnabled() ? NO : YES;
}
static BOOL safe_isJailBroken(id self, SEL _cmd) {
    return isDRMEnabled() ? NO : YES;
}
static BOOL safe_isJailBrokenCustom(id self, SEL _cmd) {
    return isDRMEnabled() ? NO : YES;
}
static BOOL safe_hasJailbreakPaths(id self, SEL _cmd) {
    return isDRMEnabled() ? NO : YES;
}
static BOOL safe_hasJailbreakProcesses(id self, SEL _cmd) {
    return isDRMEnabled() ? NO : YES;
}
static BOOL safe_canOpenJailbreakSchemes(id self, SEL _cmd) {
    return isDRMEnabled() ? NO : YES;
}
static BOOL safe_hasJailbreakEnvironmentVariables(id self, SEL _cmd) {
    return isDRMEnabled() ? NO : YES;
}
static BOOL safe_canViolateSandbox(id self, SEL _cmd) {
    return isDRMEnabled() ? NO : YES;
}
static BOOL safe_hasSuspiciousSymlinks(id self, SEL _cmd) {
    return isDRMEnabled() ? NO : YES;
}
static BOOL safe_isSimulator(id self, SEL _cmd) {
    return isDRMEnabled() ? NO : YES;
}
static BOOL safe_canAccessPath(id self, SEL _cmd, NSString *p) {
    return isDRMEnabled() ? NO : YES;
}
static id safe_getJailbreakDetails(id self, SEL _cmd) {
    if (isDRMEnabled()) return @{};
    return @{@"isJailbroken": @YES};
}

static id safePlugin_isJailBroken(id self, SEL _cmd) {
    return @{@"isJailBroken": @(isDRMEnabled() ? NO : YES)};
}
static id safePlugin_isJailBrokenCustom(id self, SEL _cmd) {
    return @{@"isJailBroken": @(isDRMEnabled() ? NO : YES)};
}
static id safePlugin_isRealDevice(id self, SEL _cmd) { return @(isDRMEnabled() ? YES : NO); }
static id safePlugin_hasLegitimateEnv(id self, SEL _cmd) { return @(isDRMEnabled() ? YES : NO); }
static id safePlugin_isDevEnv(id self, SEL _cmd) { return @(isDRMEnabled() ? NO : YES); }
static id safePlugin_hasObviousSigns(id self, SEL _cmd) { return @(isDRMEnabled() ? NO : YES); }

static void (*orig_handleCall)(id, SEL, id, id);

static void safePlugin_handleCall(id self, SEL _cmd, id call, id result) {
    NSString *method = ((NSString *(*)(id, SEL))objc_msgSend)(call, @selector(method));
    if ([method containsString:@"Jail"] || [method containsString:@"jail"] ||
        [method containsString:@"jailbreak"] || [method containsString:@"Jailbreak"] ||
        [method containsString:@"Real"] || [method containsString:@"real"] ||
        [method containsString:@"Env"] || [method containsString:@"env"] ||
        [method containsString:@"Dev"] || [method containsString:@"dev"] ||
        [method containsString:@"Sign"] || [method containsString:@"sign"]) {
        void (^reply)(id) = result;
        if (reply) reply(@{@"isJailBroken": @(isDRMEnabled() ? NO : YES),
                           @"isRealDevice": @(isDRMEnabled() ? YES : NO)});
        return;
    }
    if (orig_handleCall) orig_handleCall(self, _cmd, call, result);
}

#pragma mark - UIKit Bypasses (respect DRM toggle)

static BOOL uiscreen_isCaptured(id self, SEL _cmd) {
    return isDRMEnabled() ? NO : [UIScreen mainScreen].isCaptured;
}
static BOOL uitextfield_isSecureTextEntry(id self, SEL _cmd) { return NO; }

static void (*orig_setSecureTextEntry)(id, SEL, BOOL);
static void uitextfield_setSecureTextEntry(id self, SEL _cmd, BOOL val) {
    if (val && isDRMEnabled()) {
        NSLog(@"[unlock_academia] Blocked setSecureTextEntry:YES");
        return;
    }
    if (orig_setSecureTextEntry) orig_setSecureTextEntry(self, _cmd, val);
}

static void preventer_enablePreventScreenshot(id self, SEL _cmd) {}

#pragma mark - RevenueCat Bypass (modified for free purchases toggle)

static BOOL rc_entitlementInfo_isActive(id self, SEL _cmd) { return YES; }
static BOOL rc_entitlementInfo_isActiveInCurrentEnvironment(id self, SEL _cmd) { return YES; }

static id (*orig_rc_entitlementInfos_all)(id, SEL);
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

static void (*orig_rc_handleCall)(id, SEL, id, id);

static id ensureRCBilling(id data) {
    if (![data isKindOfClass:NSDictionary.class]) return data;
    NSMutableDictionary *mdict = [(NSDictionary *)data mutableCopy];
    id ents = mdict[@"entitlements"];
    NSMutableDictionary *ment = [ents mutableCopy] ?: [NSMutableDictionary dictionary];
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
    mdict[@"allExpirationDates"] = @{@"RC_BILLING": @"2099-12-31T23:59:59Z"};
    mdict[@"allPurchaseDates"] = @{@"RC_BILLING": @"2024-01-01T00:00:00Z"};
    return [mdict copy];
}

static void rc_plugin_handleCall(id self, SEL _cmd, id call, id result) {
    NSString *method = ((NSString *(*)(id, SEL))objc_msgSend)(call, @selector(method));

    if ([method isEqualToString:@"getCustomerInfo"] || [method isEqualToString:@"getOfferings"]) {
        void (^origResult)(id) = result;
        void (^wrapped)(id) = ^(id data) {
            origResult(ensureRCBilling(data));
        };
        if (orig_rc_handleCall) {
            orig_rc_handleCall(self, _cmd, call, (id)wrapped);
        } else {
            wrapped(nil);
        }
        return;
    }

    // Intercept purchase methods when free purchases is enabled
    if (isFreePurchasesEnabled()) {
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

static void applyRevenueCatHooks(void) {
    Class infoClass = NSClassFromString(@"RCEntitlementInfo");
    if (infoClass) {
        swzIfSafe(infoClass, @selector(isActive), (IMP)rc_entitlementInfo_isActive);
        swzIfSafe(infoClass, @selector(isActiveInCurrentEnvironment), (IMP)rc_entitlementInfo_isActiveInCurrentEnvironment);
        NSLog(@"[unlock_academia] RCEntitlementInfo.isActive hooked");
    }

    Class infosClass = NSClassFromString(@"RCEntitlementInfos");
    if (infosClass) {
        Method allM = class_getInstanceMethod(infosClass, @selector(all));
        if (allM) {
            orig_rc_entitlementInfos_all = (id (*)(id, SEL))method_getImplementation(allM);
            method_setImplementation(allM, (IMP)rc_entitlementInfos_all);
        }
        NSLog(@"[unlock_academia] RCEntitlementInfos.all hooked");
    }

    Class pluginClass = NSClassFromString(@"PurchasesFlutterPlugin");
    if (pluginClass) {
        Method hm = class_getInstanceMethod(pluginClass, @selector(handleMethodCall:result:));
        if (hm) {
            orig_rc_handleCall = (void (*)(id, SEL, id, id))method_getImplementation(hm);
            method_setImplementation(hm, (IMP)rc_plugin_handleCall);
        }
        NSLog(@"[unlock_academia] PurchasesFlutterPlugin.handleMethodCall:result: hooked");
    }

    Class pluginRegistrar = NSClassFromString(@"PurchasesPlugin");
    if (!pluginRegistrar) pluginRegistrar = NSClassFromString(@"RCPurchasesPlugin");
    if (pluginRegistrar) {
        Method hm2 = class_getInstanceMethod(pluginRegistrar, @selector(handleMethodCall:result:));
        if (!hm2) hm2 = class_getInstanceMethod(pluginRegistrar, @selector(handle:result:));
        if (hm2 && !orig_rc_handleCall) {
            orig_rc_handleCall = (void (*)(id, SEL, id, id))method_getImplementation(hm2);
            method_setImplementation(hm2, (IMP)rc_plugin_handleCall);
            NSLog(@"[unlock_academia] %@ handle hooked", pluginRegistrar);
        }
    }
}

#pragma mark - UIKit Hooks

static void applyUIKitHooks(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        swzIfSafe([UIScreen class], @selector(isCaptured), (IMP)uiscreen_isCaptured);
        swzIfSafe([UITextField class], @selector(isSecureTextEntry), (IMP)uitextfield_isSecureTextEntry);

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

#pragma mark - SafeDevice / Jailbreak Hook Application

static void applySafeDeviceHooks(void) {
    Class sdClass = NSClassFromString(@"SafeDeviceJailbreakDetection");
    if (sdClass) {
        swzClassIfSafe(sdClass, @selector(isJailbroken), (IMP)safe_isJailbroken);
        swzClassIfSafe(sdClass, @selector(isJailBroken), (IMP)safe_isJailBroken);
        swzClassIfSafe(sdClass, @selector(isJailBrokenCustom), (IMP)safe_isJailBrokenCustom);
        swzClassIfSafe(sdClass, @selector(hasJailbreakPaths), (IMP)safe_hasJailbreakPaths);
        swzClassIfSafe(sdClass, @selector(hasJailbreakProcesses), (IMP)safe_hasJailbreakProcesses);
        swzClassIfSafe(sdClass, @selector(canOpenJailbreakSchemes), (IMP)safe_canOpenJailbreakSchemes);
        swzClassIfSafe(sdClass, @selector(hasJailbreakEnvironmentVariables), (IMP)safe_hasJailbreakEnvironmentVariables);
        swzClassIfSafe(sdClass, @selector(canViolateSandbox), (IMP)safe_canViolateSandbox);
        swzClassIfSafe(sdClass, @selector(hasSuspiciousSymlinks), (IMP)safe_hasSuspiciousSymlinks);
        swzClassIfSafe(sdClass, @selector(isSimulator), (IMP)safe_isSimulator);
        swzClassIfSafe(sdClass, @selector(getJailbreakDetails), (IMP)safe_getJailbreakDetails);
        swzClassIfSafe(sdClass, @selector(canAccessPath:), (IMP)safe_canAccessPath);
        NSLog(@"[unlock_academia] SafeDeviceJailbreakDetection hooked");
    }

    Class sdPlugin = NSClassFromString(@"SafeDevicePlugin");
    if (sdPlugin) {
        swzIfSafe(sdPlugin, @selector(isJailBroken), (IMP)safePlugin_isJailBroken);
        swzIfSafe(sdPlugin, @selector(isJailBrokenCustom), (IMP)safePlugin_isJailBrokenCustom);
        swzIfSafe(sdPlugin, @selector(isRealDevice), (IMP)safePlugin_isRealDevice);
        swzIfSafe(sdPlugin, @selector(hasLegitimateEnvironmentVariables), (IMP)safePlugin_hasLegitimateEnv);
        swzIfSafe(sdPlugin, @selector(isDevelopmentEnvironment), (IMP)safePlugin_isDevEnv);
        swzIfSafe(sdPlugin, @selector(hasObviousJailbreakSigns), (IMP)safePlugin_hasObviousSigns);
        Method hm = class_getInstanceMethod(sdPlugin, @selector(handleMethodCall:result:));
        if (hm) {
            orig_handleCall = (void (*)(id, SEL, id, id))method_getImplementation(hm);
            method_setImplementation(hm, (IMP)safePlugin_handleCall);
        }
        NSLog(@"[unlock_academia] SafeDevicePlugin hooked");
    }

    Class dttClass = NSClassFromString(@"DTTJailbreakDetection");
    if (dttClass) {
        swzClassIfSafe(dttClass, @selector(isJailbroken), (IMP)safe_isJailbroken);
        swzClassIfSafe(dttClass, @selector(isPirated), (IMP)safe_isJailbroken);
        NSLog(@"[unlock_academia] DTTJailbreakDetection hooked");
    }
}

#pragma mark - ScreenPreventerKit Hooks

static void applyScreenPreventerHooks(void) {
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
            Method m = class_getInstanceMethod(c, candidates[i]);
            if (m) method_setImplementation(m, (IMP)uitextfield_isSecureTextEntry);
        }
        SEL enableSel = NSSelectorFromString(@"enablePreventScreenshot");
        Method em = class_getInstanceMethod(c, enableSel);
        if (em) method_setImplementation(em, (IMP)preventer_enablePreventScreenshot);

        SEL disableSel = NSSelectorFromString(@"disableScreenshotBlocking");
        Method dm = class_getInstanceMethod(c, disableSel);
        if (dm) {
            IMP orig = method_getImplementation(dm);
            ((void (*)(id, SEL))orig)(c, disableSel);
        }

        NSLog(@"[unlock_academia] ScreenPreventerKit class hooked: %@", name);
    }
}

#pragma mark - Secure Text Field Scanner

static void recursiveDisableSecure(UIView *view) {
    if ([view isKindOfClass:UITextField.class]) {
        [(UITextField *)view setSecureTextEntry:NO];
    }
    for (UIView *sub in view.subviews) {
        recursiveDisableSecure(sub);
    }
}

static void scanAndDisableSecureTextFields(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *win in ((UIWindowScene *)scene).windows) {
            recursiveDisableSecure(win);
        }
    }
}

#pragma mark - Drag Gesture Support

__attribute__((constructor)) static void initDragSupport(void) {
    Method nopM = class_getInstanceMethod([NSObject class], @selector(__unlock_dragButton:));
    if (!nopM) {
        BOOL added = class_addMethod([NSObject class], @selector(__unlock_dragButton:),
                                     (IMP)unlock_dragButton, "v@:@");
        if (added) {
            NSLog(@"[unlock_academia] Drag support initialized");
        }
    }
}

#pragma mark - Deferred Hooking

static void runDeferredHooks(void) {
    NSLog(@"[unlock_academia] Running deferred hooks...");

    applySafeDeviceHooks();
    applyScreenPreventerHooks();
    applyRevenueCatHooks();
    applyFlutterChannelHook();

    scanAndDisableSecureTextFields();
    addFloatingMenuButton();

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        applySafeDeviceHooks();
        applyScreenPreventerHooks();
        applyRevenueCatHooks();
        applyFlutterChannelHook();
        scanAndDisableSecureTextFields();
        if (!menuBtn) addFloatingMenuButton();
        NSLog(@"[unlock_academia] Late retry complete");
    });
}

#pragma mark - Constructor

__attribute__((constructor)) static void init_dylib(void) {
    @autoreleasepool {
        NSLog(@"[unlock_academia] dylib loaded.");
        applyUIKitHooks();

        dispatch_async(dispatch_get_main_queue(), ^{
            runDeferredHooks();
        });
    }
}
