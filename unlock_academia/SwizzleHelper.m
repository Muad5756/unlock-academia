#import "SwizzleHelper.h"
#import "BypassSettings.h"

static NSMutableDictionary *gOriginalIMPs = nil;

@implementation SwizzleHelper

+ (void)initialize {
    if (self == [SwizzleHelper class]) {
        gOriginalIMPs = [[NSMutableDictionary alloc] init];
    }
}

+ (void)swizzleInstanceMethod:(Class)cls selector:(SEL)sel hookIMP:(IMP)hookIMP originalIMPPair:(IMP *)originalIMPPair {
    if (!cls || !sel || !hookIMP) return;
    
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    
    IMP origImp = method_getImplementation(m);
    if (origImp == hookIMP) return; // Already swizzled
    
    const char *types = method_getTypeEncoding(m);
    if (class_addMethod(cls, sel, hookIMP, types)) {
        if (originalIMPPair) *originalIMPPair = origImp;
    } else {
        IMP old = method_setImplementation(m, hookIMP);
        if (originalIMPPair) *originalIMPPair = old;
    }
}

+ (void)swizzleClassMethod:(Class)cls selector:(SEL)sel hookIMP:(IMP)hookIMP originalIMPPair:(IMP *)originalIMPPair {
    if (!cls || !sel || !hookIMP) return;
    [self swizzleInstanceMethod:object_getClass(cls) selector:sel hookIMP:hookIMP originalIMPPair:originalIMPPair];
}

+ (void)swizzleInstanceMethod:(Class)cls selector:(SEL)sel returnValIfBypassed:(BOOL)returnVal {
    if (!cls || !sel) return;
    
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    
    NSString *key = [NSString stringWithFormat:@"%@_%@", NSStringFromClass(cls), NSStringFromSelector(sel)];
    IMP origImp = method_getImplementation(m);
    
    @synchronized (gOriginalIMPs) {
        gOriginalIMPs[key] = [NSValue valueWithPointer:origImp];
    }
    
    BOOL (^hookBlock)(id) = ^BOOL(id selfObj) {
        if ([BypassSettings isDRMBypassActive]) {
            return returnVal;
        }
        NSValue *val = nil;
        @synchronized (gOriginalIMPs) {
            val = gOriginalIMPs[key];
        }
        if (val) {
            BOOL (*origFunc)(id, SEL) = (BOOL (*)(id, SEL))[val pointerValue];
            return origFunc(selfObj, sel);
        }
        return returnVal;
    };
    
    IMP newImp = imp_implementationWithBlock(hookBlock);
    method_setImplementation(m, newImp);
}

+ (void)swizzleInstanceMethodVoid:(Class)cls selector:(SEL)sel {
    if (!cls || !sel) return;
    
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    
    NSString *key = [NSString stringWithFormat:@"%@_%@", NSStringFromClass(cls), NSStringFromSelector(sel)];
    IMP origImp = method_getImplementation(m);
    
    @synchronized (gOriginalIMPs) {
        gOriginalIMPs[key] = [NSValue valueWithPointer:origImp];
    }
    
    void (^hookBlock)(id) = ^(id selfObj) {
        if ([BypassSettings isDRMBypassActive]) {
            return; // No-op when bypass is active
        }
        NSValue *val = nil;
        @synchronized (gOriginalIMPs) {
            val = gOriginalIMPs[key];
        }
        if (val) {
            void (*origFunc)(id, SEL) = (void (*)(id, SEL))[val pointerValue];
            origFunc(selfObj, sel);
        }
    };
    
    IMP newImp = imp_implementationWithBlock(hookBlock);
    method_setImplementation(m, newImp);
}

@end
