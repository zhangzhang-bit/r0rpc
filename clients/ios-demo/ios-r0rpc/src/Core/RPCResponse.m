#import "RPCResponse.h"

void R0ResponseOK(R0RPCResponseBlock response, NSDictionary *payload) {
    if (response) {
        response(@"success", 200, payload ?: @{}, @"");
    }
}

void R0ResponseError(R0RPCResponseBlock response, NSInteger httpCode, NSString *message) {
    if (response) {
        response(@"error", httpCode, @{}, message ?: @"");
    }
}
