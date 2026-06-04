#ifndef ObjCRuntimeUtils_h
#define ObjCRuntimeUtils_h

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

Class R0RequiredClass(NSString *className, NSString *logTag);
SEL R0RequiredSelector(NSString *selectorName);
BOOL R0ClassRespondsToSelectorName(Class cls, NSString *selectorName);
BOOL R0InstanceRespondsToSelectorName(id target, NSString *selectorName);

#endif
