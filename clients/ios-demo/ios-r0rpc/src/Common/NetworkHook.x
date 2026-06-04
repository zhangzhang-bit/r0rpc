#import <Foundation/Foundation.h>
#import "Groups.h"
#import "HookUtils.h"

%group NetworkGroup

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    R0PrintRequestInfo(request);
    return %orig;
}

%end

%hook NSMutableURLRequest

- (void)setHTTPBody:(NSData *)data {
    %orig;
    if (data.length > 0) {
        NSLog(@"[R0RPC][Network] setHTTPBody length=%lu text=%@",
              (unsigned long)data.length,
              R0ShortString(R0DataToUTF8OrNil(data) ?: R0DataToHex(data, 128), 800));
    }
    R0PrintRequestInfo(self);
}

%end

%end

void initNetworkGroup(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(NetworkGroup);
    });
}
