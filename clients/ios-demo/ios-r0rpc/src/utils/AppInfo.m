#import "AppInfo.h"

NSString *R0GetBundleId(void) {
    return NSBundle.mainBundle.bundleIdentifier ?: @"unknown";
}
