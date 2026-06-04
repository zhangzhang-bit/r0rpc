#ifndef PayloadUtils_h
#define PayloadUtils_h

#import <Foundation/Foundation.h>

NSDictionary *R0JobPayload(NSDictionary *job);
NSString *R0StringValue(id value);
NSString *R0PayloadString(NSDictionary *payload, NSString *key);
NSDictionary *R0DictionaryFromParamPayload(NSDictionary *payload);

#endif
