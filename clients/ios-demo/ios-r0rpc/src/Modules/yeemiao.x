#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "Groups.h"
#import "RelayBootstrap.h"
#import "RPCResponse.h"
#import "PayloadUtils.h"
#import "ObjCRuntimeUtils.h"

static NSString *const kRPCGroup = @"yeemiao";

static RelayClient *gRelayClient = nil;

static NSString *YeeMiaoBuildSign(NSDictionary *parameters, NSString **error) {
    Class serializerClass = R0RequiredClass(@"YeemiaoJsonSerializer", @"YeeMiao");
    if (!serializerClass) {
        if (error) {
            *error = @"YeemiaoJsonSerializer not found";
        }
        return nil;
    }

    SEL selector = R0RequiredSelector(@"buildSignJsonStringWithParameters:");
    if (![serializerClass respondsToSelector:selector]) {
        if (error) {
            *error = @"buildSignJsonStringWithParameters: not found";
        }
        return nil;
    }

    return ((NSString *(*)(id, SEL, id))objc_msgSend)(serializerClass, selector, parameters);
}

static void RegisterYeeMiaoHandlers(RelayClient *client) {
    [client registerHandler:@"ping" handler:^(__unused NSDictionary *job, R0RPCResponseBlock response) {
        R0ResponseOK(response, @{});
    }];

    [client registerHandler:@"get_sign" handler:^(NSDictionary *job, R0RPCResponseBlock response) {
        NSDictionary *parameters = R0DictionaryFromParamPayload(R0JobPayload(job));
        if (!parameters) {
            R0ResponseError(response, 400, @"param is required and must be valid json");
            return;
        }

        @try {
            NSString *signError = nil;
            NSString *signResult = YeeMiaoBuildSign(parameters, &signError);
            if (signError.length > 0) {
                R0ResponseError(response, 500, signError);
                return;
            }
            R0ResponseOK(response, @{@"sign": signResult ?: @""});
        } @catch (NSException *exception) {
            R0ResponseError(response, 500, exception.reason ?: exception.name);
        }
    }];
}

static void StartRelayOnce(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gRelayClient = R0StartRelayClient(kRPCGroup, @"yeemiao", ^(RelayClient *client) {
            RegisterYeeMiaoHandlers(client);
        });
    });
}

static void StartRelaySoon(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        StartRelayOnce();
    });
}

%group YeeMiaoGroup

%hook AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL result = %orig;
    StartRelayOnce();
    return result;
}

%end

%end

void initYeeMiaoGroup(void) {
    %init(YeeMiaoGroup);
    StartRelaySoon();
}
