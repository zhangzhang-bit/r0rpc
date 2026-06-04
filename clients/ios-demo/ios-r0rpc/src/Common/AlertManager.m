#import "AlertManager.h"
#import <UIKit/UIKit.h>

static UIWindow *R0AlertKeyWindow(void) {
    UIWindow *window = nil;

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class] ||
                scene.activationState != UISceneActivationStateForegroundActive) {
                continue;
            }

            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *candidate in windowScene.windows) {
                if (candidate.isKeyWindow) {
                    window = candidate;
                    break;
                }
            }
            if (window) {
                break;
            }
        }
    } else {
        window = UIApplication.sharedApplication.keyWindow;
    }

    if (!window) {
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if (![scene isKindOfClass:UIWindowScene.class]) {
                    continue;
                }
                window = ((UIWindowScene *)scene).windows.firstObject;
                if (window) {
                    break;
                }
            }
        } else {
            window = UIApplication.sharedApplication.windows.firstObject;
        }
    }

    return window;
}

static UIViewController *R0AlertTopViewController(UIViewController *rootViewController) {
    if ([rootViewController isKindOfClass:UINavigationController.class]) {
        return R0AlertTopViewController(((UINavigationController *)rootViewController).visibleViewController);
    }
    if ([rootViewController isKindOfClass:UITabBarController.class]) {
        return R0AlertTopViewController(((UITabBarController *)rootViewController).selectedViewController);
    }
    if (rootViewController.presentedViewController) {
        return R0AlertTopViewController(rootViewController.presentedViewController);
    }
    return rootViewController;
}

static void R0ShowAlertWithRetry(NSString *title, NSString *message, NSInteger retryLeft) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = R0AlertKeyWindow();
        if (!window || !window.rootViewController) {
            NSLog(@"[R0RPC][Alert] window not ready, retryLeft=%ld", (long)retryLeft);
            if (retryLeft > 0) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    R0ShowAlertWithRetry(title, message, retryLeft - 1);
                });
            }
            return;
        }

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title ?: @"R0RPC"
                                                                       message:message ?: @""
                                                                preferredStyle:UIAlertControllerStyleAlert];
        UIViewController *topViewController = R0AlertTopViewController(window.rootViewController);
        if (!topViewController || !topViewController.view.window || topViewController.presentedViewController) {
            NSLog(@"[R0RPC][Alert] view controller not ready, retryLeft=%ld", (long)retryLeft);
            if (retryLeft > 0) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    R0ShowAlertWithRetry(title, message, retryLeft - 1);
                });
            }
            return;
        }

        [topViewController presentViewController:alert animated:YES completion:^{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [alert dismissViewControllerAnimated:YES completion:nil];
            });
        }];
        NSLog(@"[R0RPC][Alert] shown: %@", title);
    });
}

void showAlertWithTitle(NSString *title, NSString *message) {
    R0ShowAlertWithRetry(title, message, 10);
}

void showDeviceAlert(NSString *deviceId) {
    showAlertWithTitle(@"设备信息", [NSString stringWithFormat:@"设备ID:\n%@", deviceId ?: @"ios-unknown"]);
}

void showAlertLater(NSString *deviceId, NSTimeInterval delaySeconds) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delaySeconds * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        showDeviceAlert(deviceId);
    });
}
