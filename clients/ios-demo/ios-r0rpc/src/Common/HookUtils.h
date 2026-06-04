#ifndef HookUtils_h
#define HookUtils_h

#import <Foundation/Foundation.h>

void R0PrintRequestInfo(NSURLRequest *request);
void R0TrackStringSource(NSString *value, NSString *tag);
NSString *R0ShortString(NSString *value, NSUInteger maxLength);
NSString *R0DataToHex(NSData *data, NSUInteger maxLength);
NSString *R0DataToUTF8OrNil(NSData *data);
NSString *R0DataToBase64(NSData *data);
NSDictionary *R0PayloadFromData(NSData *data);

#endif
