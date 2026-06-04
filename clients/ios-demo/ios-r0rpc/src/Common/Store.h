#ifndef Store_h
#define Store_h

#import <Foundation/Foundation.h>

@interface Store : NSObject

+ (instancetype)shared;
- (void)put:(id)object forKey:(NSString *)key;
- (id)get:(NSString *)key;
- (void)remove:(NSString *)key;
- (BOOL)contains:(NSString *)key;
- (void)clear;

@end

#endif
