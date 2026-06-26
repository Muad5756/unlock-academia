#import <Foundation/Foundation.h>

@interface BypassHooks : NSObject

+ (void)applyUIKitHooks;
+ (void)applySafeDeviceHooks;
+ (void)applyScreenPreventerHooks;
+ (void)applyRevenueCatHooks;
+ (void)applyFlutterChannelHooks;

+ (void)scanAndDisableSecureTextFields;

@end
