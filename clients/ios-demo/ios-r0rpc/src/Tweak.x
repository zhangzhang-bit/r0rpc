#import <UIKit/UIKit.h>
#import "Groups.h"
#import "AppInfo.h"
#import "DeviceIdManager.h"
#import "AlertManager.h"

%ctor {
    NSLog(@"[R0RPC] tweak started");

    NSString *deviceId = R0GetDeviceIdentifier();
    NSString *bundleId = R0GetBundleId();
    NSString *appName = NSBundle.mainBundle.infoDictionary[@"CFBundleDisplayName"] ?: NSBundle.mainBundle.infoDictionary[@"CFBundleName"] ?: @"unknown";

    NSLog(@"[R0RPC] deviceId=%@", deviceId);
    NSLog(@"[R0RPC] appName=%@", appName);
    NSLog(@"[R0RPC] ios-demo loaded into %@", bundleId);

    initNetworkGroup();
    initUrlSourceGroup();
    initSchemeGroup();
    initCryptoGroup();

    showAlertLater(deviceId, 2.0);

    if ([bundleId isEqualToString:@"com.threegene.yeemiao"]) {
        NSLog(@"[R0RPC] enter yeemiao app");
        initYeeMiaoGroup();
    }
    if ([bundleId isEqualToString:@"com.tgood.gotocharge"]) {
        NSLog(@"[R0RPC] enter teld app");
        initTeldGroup();
    }
}
