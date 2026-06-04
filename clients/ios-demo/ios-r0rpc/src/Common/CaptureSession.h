#ifndef CaptureSession_h
#define CaptureSession_h

#import <Foundation/Foundation.h>
#import "RPCResponse.h"

typedef void (^R0CaptureTimeoutBlock)(NSString *key, NSDictionary *context, R0RPCResponseBlock response);

void R0StartCapture(NSString *key, R0RPCResponseBlock response, NSDictionary *context, NSTimeInterval timeoutSeconds, R0CaptureTimeoutBlock timeoutBlock);
NSDictionary *R0CaptureContext(NSString *key);
R0RPCResponseBlock R0CaptureResponse(NSString *key);
BOOL R0FinishCapture(NSString *key, NSDictionary *payload);
void R0CancelCapture(NSString *key);

#endif
