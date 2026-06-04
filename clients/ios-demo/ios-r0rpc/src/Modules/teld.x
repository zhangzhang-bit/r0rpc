#import <Foundation/Foundation.h>
#import "Groups.h"

%group TeldGroup

%hook TLDLoginManager

- (id)AESForBaseSGEncrypt:(id)input {
    NSLog(@"[R0RPC][Teld][AES] in=%@", input);
    id result = %orig(input);
    NSLog(@"[R0RPC][Teld][AES] out=%@", result);
    return result;
}

+ (id)DESEncrypUserApiSGPlainText:(id)input {
    NSLog(@"[R0RPC][Teld][DES] in=%@", input);
    id result = %orig(input);
    NSLog(@"[R0RPC][Teld][DES] out=%@", result);
    return result;
}

%end

%end

void initTeldGroup(void) {
    static BOOL installed = NO;
    if (installed) {
        return;
    }

    Class cls = NSClassFromString(@"TLDLoginManager");
    if (cls != nil) {
        installed = YES;
        %init(TeldGroup);
        NSLog(@"[R0RPC][Teld] hooks installed");
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        initTeldGroup();
    });
}
