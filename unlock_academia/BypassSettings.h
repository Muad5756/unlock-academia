#import <Foundation/Foundation.h>

@interface BypassSettings : NSObject

+ (BOOL)isDRMBypassActive;
+ (void)setDRMBypassActive:(BOOL)active;

+ (BOOL)isFreePurchasesEnabled;
+ (void)setFreePurchasesEnabled:(BOOL)enabled;

+ (double)getWalletBalance;
+ (void)setWalletBalance:(double)balance;
+ (void)addWalletBalance:(double)amount;
+ (NSString *)formatBalance:(double)balance;

@end
