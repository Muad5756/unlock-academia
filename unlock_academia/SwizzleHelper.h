#import <Foundation/Foundation.h>
#import <objc/runtime.h>

@interface SwizzleHelper : NSObject

+ (void)swizzleInstanceMethod:(Class)cls selector:(SEL)sel hookIMP:(IMP)hookIMP originalIMPPair:(IMP *)originalIMPPair;
+ (void)swizzleClassMethod:(Class)cls selector:(SEL)sel hookIMP:(IMP)hookIMP originalIMPPair:(IMP *)originalIMPPair;

// Dynamic conditional hooks
+ (void)swizzleInstanceMethod:(Class)cls selector:(SEL)sel returnValIfBypassed:(BOOL)returnVal;
+ (void)swizzleInstanceMethodVoid:(Class)cls selector:(SEL)sel;

@end
