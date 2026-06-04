#import "ObjCRuntimeUtils.h"

Class R0RequiredClass(NSString *className, NSString *logTag) {
    Class cls = NSClassFromString(className);
    if (!cls) {
        NSLog(@"[R0RPC][%@] class not found: %@", logTag ?: @"Runtime", className);
    }
    return cls;
}

SEL R0RequiredSelector(NSString *selectorName) {
    return NSSelectorFromString(selectorName);
}

BOOL R0ClassRespondsToSelectorName(Class cls, NSString *selectorName) {
    SEL selector = R0RequiredSelector(selectorName);
    return cls != nil && selector != NULL && [cls respondsToSelector:selector];
}

BOOL R0InstanceRespondsToSelectorName(id target, NSString *selectorName) {
    SEL selector = R0RequiredSelector(selectorName);
    return target != nil && selector != NULL && [target respondsToSelector:selector];
}
