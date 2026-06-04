#ifndef RPCResponse_h
#define RPCResponse_h

#import <Foundation/Foundation.h>

typedef void (^R0RPCResponseBlock)(NSString *status, NSInteger httpCode, NSDictionary *payload, NSString *error);

void R0ResponseOK(R0RPCResponseBlock response, NSDictionary *payload);
void R0ResponseError(R0RPCResponseBlock response, NSInteger httpCode, NSString *message);

#endif
