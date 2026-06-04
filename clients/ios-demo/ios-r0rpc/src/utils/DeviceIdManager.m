#import "DeviceIdManager.h"
#import <Security/Security.h>

NSString *R0GetDeviceIdentifier(void) {
    static NSString *deviceId = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        NSString *service = @"com.r0rpc.client";
        NSString *account = @"device_uuid";

        NSMutableDictionary *query = [NSMutableDictionary dictionary];
        query[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
        query[(__bridge id)kSecAttrService] = service;
        query[(__bridge id)kSecAttrAccount] = account;
        query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
        query[(__bridge id)kSecReturnData] = (__bridge id)kCFBooleanTrue;

        CFTypeRef result = NULL;
        OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
        if (status == errSecSuccess) {
            NSData *data = (__bridge_transfer NSData *)result;
            deviceId = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            return;
        }

        deviceId = [[NSUUID UUID] UUIDString];
        NSData *data = [deviceId dataUsingEncoding:NSUTF8StringEncoding];
        NSMutableDictionary *addQuery = [NSMutableDictionary dictionary];
        addQuery[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
        addQuery[(__bridge id)kSecAttrService] = service;
        addQuery[(__bridge id)kSecAttrAccount] = account;
        addQuery[(__bridge id)kSecValueData] = data;
        addQuery[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
        SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
    });

    return deviceId ?: @"ios-unknown";
}
