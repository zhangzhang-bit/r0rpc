#import <UIKit/UIKit.h>
#import "Groups.h"

static NSDictionary *R0QueryItems(NSURL *url) {
    NSMutableDictionary *items = [NSMutableDictionary dictionary];
    for (NSString *part in [url.query componentsSeparatedByString:@"&"]) {
        NSArray *kv = [part componentsSeparatedByString:@"="];
        if (kv.count >= 2) {
            NSString *key = [kv[0] stringByRemovingPercentEncoding] ?: kv[0];
            NSString *value = [kv[1] stringByRemovingPercentEncoding] ?: kv[1];
            items[key] = value;
        }
    }
    return items;
}

static void R0LogSchemeURL(NSURL *url, NSString *source) {
    if (url == nil) {
        return;
    }
    NSLog(@"[R0RPC][Scheme] %@ url=%@ scheme=%@ host=%@ path=%@ query=%@ items=%@",
          source,
          url.absoluteString,
          url.scheme ?: @"",
          url.host ?: @"",
          url.path ?: @"",
          url.query ?: @"",
          R0QueryItems(url));
}

%group SchemeGroup

%hook SceneDelegate

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts {
    %orig;
    for (UIOpenURLContext *context in URLContexts) {
        R0LogSchemeURL(context.URL, @"SceneDelegate");
    }
}

%end

%hook AppDelegate

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
    BOOL result = %orig;
    R0LogSchemeURL(url, @"AppDelegate");
    return result;
}

%end

%end

void initSchemeGroup(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SchemeGroup);
    });
}
