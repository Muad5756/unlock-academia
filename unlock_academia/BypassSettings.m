#import "BypassSettings.h"
#import "BypassDefs.h"

@implementation BypassSettings

+ (BOOL)isDRMBypassActive {
    id val = [[NSUserDefaults standardUserDefaults] objectForKey:kUDDRMBypassActive];
    if (val == nil) {
        return YES; // Default to active bypass on startup
    }
    return [val boolValue];
}

+ (void)setDRMBypassActive:(BOOL)active {
    [[NSUserDefaults standardUserDefaults] setBool:active forKey:kUDDRMBypassActive];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (BOOL)isFreePurchasesEnabled {
    id val = [[NSUserDefaults standardUserDefaults] objectForKey:kUDFreePurchasesEnabled];
    if (val == nil) {
        return YES; // Default to active purchases bypass on startup
    }
    return [val boolValue];
}

+ (void)setFreePurchasesEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kUDFreePurchasesEnabled];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (double)getWalletBalance {
    id val = [[NSUserDefaults standardUserDefaults] objectForKey:kUDWalletBalance];
    if (val == nil) {
        return kDefaultWalletBalance; // Starts at 10000.0
    }
    double bal = [val doubleValue];
    if (bal < 0.01) {
        bal = kDefaultWalletBalance;
    }
    return bal;
}

+ (void)setWalletBalance:(double)balance {
    [[NSUserDefaults standardUserDefaults] setDouble:balance forKey:kUDWalletBalance];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (void)addWalletBalance:(double)amount {
    [self setWalletBalance:[self getWalletBalance] + amount];
}

+ (NSString *)formatBalance:(double)balance {
    NSNumberFormatter *fmt = [[NSNumberFormatter alloc] init];
    fmt.numberStyle = NSNumberFormatterDecimalStyle;
    fmt.minimumFractionDigits = 2;
    fmt.maximumFractionDigits = 2;
    return [NSString stringWithFormat:@"%@ ر.س", [fmt stringFromNumber:@(balance)]];
}

@end
