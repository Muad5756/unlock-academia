#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#ifndef BypassDefs_h
#define BypassDefs_h

// NSUserDefaults Keys
static NSString *const kUDWalletBalance = @"com.unlock.wallet.balance";
static NSString *const kUDDRMBypassActive = @"com.unlock.drm.bypass.active";
static NSString *const kUDFreePurchasesEnabled = @"com.unlock.freepurchases.enabled";

// Default Values
static const double kDefaultWalletBalance = 10000.0;

#endif /* BypassDefs_h */
