#import "CaptureSession.h"
#import "Store.h"

static NSString *R0CaptureStoreKey(NSString *key) {
    return [@"capture." stringByAppendingString:(key ?: @"")];
}

void R0StartCapture(NSString *key, R0RPCResponseBlock response, NSDictionary *context, NSTimeInterval timeoutSeconds, R0CaptureTimeoutBlock timeoutBlock) {
    if (key.length == 0 || response == nil) {
        return;
    }

    NSString *token = [[NSUUID UUID] UUIDString];
    NSDictionary *capture = @{
        @"token": token,
        @"response": [response copy],
        @"context": context ?: @{}
    };
    [[Store shared] put:capture forKey:R0CaptureStoreKey(key)];

    if (timeoutSeconds > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeoutSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSDictionary *current = [[Store shared] get:R0CaptureStoreKey(key)];
            if (![current[@"token"] isEqualToString:token]) {
                return;
            }
            [[Store shared] remove:R0CaptureStoreKey(key)];
            R0RPCResponseBlock savedResponse = current[@"response"];
            NSDictionary *savedContext = current[@"context"] ?: @{};
            if (timeoutBlock) {
                timeoutBlock(key, savedContext, savedResponse);
            } else {
                R0ResponseError(savedResponse, 504, @"capture timeout");
            }
        });
    }
}

NSDictionary *R0CaptureContext(NSString *key) {
    NSDictionary *capture = [[Store shared] get:R0CaptureStoreKey(key)];
    return [capture[@"context"] isKindOfClass:[NSDictionary class]] ? capture[@"context"] : @{};
}

R0RPCResponseBlock R0CaptureResponse(NSString *key) {
    NSDictionary *capture = [[Store shared] get:R0CaptureStoreKey(key)];
    return capture[@"response"];
}

BOOL R0FinishCapture(NSString *key, NSDictionary *payload) {
    R0RPCResponseBlock response = R0CaptureResponse(key);
    if (!response) {
        return NO;
    }
    [[Store shared] remove:R0CaptureStoreKey(key)];
    R0ResponseOK(response, payload ?: @{});
    return YES;
}

void R0CancelCapture(NSString *key) {
    if (key.length > 0) {
        [[Store shared] remove:R0CaptureStoreKey(key)];
    }
}
