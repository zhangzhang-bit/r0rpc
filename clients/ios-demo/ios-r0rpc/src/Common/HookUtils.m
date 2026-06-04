#import "HookUtils.h"
#import <dlfcn.h>
#import <execinfo.h>

NSString *R0ShortString(NSString *value, NSUInteger maxLength) {
    if (value.length == 0 || value.length <= maxLength) {
        return value ?: @"";
    }
    return [[value substringToIndex:maxLength] stringByAppendingString:@"..."];
}

NSString *R0DataToHex(NSData *data, NSUInteger maxLength) {
    if (data.length == 0) {
        return @"";
    }
    const unsigned char *bytes = data.bytes;
    NSUInteger limit = MIN(data.length, maxLength);
    NSMutableString *hex = [NSMutableString stringWithCapacity:limit * 2];
    for (NSUInteger i = 0; i < limit; i++) {
        [hex appendFormat:@"%02x", bytes[i]];
    }
    if (data.length > limit) {
        [hex appendString:@"..."];
    }
    return hex;
}

NSString *R0DataToUTF8OrNil(NSData *data) {
    if (data.length == 0) {
        return @"";
    }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

NSString *R0DataToBase64(NSData *data) {
    return data.length > 0 ? [data base64EncodedStringWithOptions:0] : @"";
}

NSDictionary *R0PayloadFromData(NSData *data) {
    NSString *body = R0DataToUTF8OrNil(data);
    if (body != nil) {
        return @{@"body": body, @"encoding": @"utf8", @"length": @(data.length)};
    }
    return @{@"bodyBase64": R0DataToBase64(data), @"encoding": @"base64", @"length": @(data.length)};
}

static NSString *R0CallStackString(int skipFrames) {
    void *frames[64];
    int count = backtrace(frames, 64);
    NSMutableString *stack = [NSMutableString string];
    for (int i = skipFrames; i < count && i < skipFrames + 12; i++) {
        Dl_info info;
        if (!dladdr(frames[i], &info)) {
            continue;
        }
        const char *path = info.dli_fname ?: "unknown";
        const char *name = strrchr(path, '/');
        name = name ? name + 1 : path;
        uintptr_t base = (uintptr_t)info.dli_fbase;
        uintptr_t addr = (uintptr_t)frames[i];
        [stack appendFormat:@"%s 0x%llx base+0x%llx\n",
         name,
         (unsigned long long)addr,
         (unsigned long long)(base > 0 ? addr - base : 0)];
    }
    return stack;
}

void R0PrintRequestInfo(NSURLRequest *request) {
    if (request.URL == nil) {
        NSLog(@"[R0RPC][Network] empty request or url");
        return;
    }

    NSMutableString *log = [NSMutableString string];
    [log appendFormat:@"\n[R0RPC][Network]\nURL: %@\nMethod: %@\nTimeout: %.2f\n",
     request.URL.absoluteString,
     request.HTTPMethod ?: @"GET",
     request.timeoutInterval];

    NSDictionary *headers = request.allHTTPHeaderFields;
    if (headers.count > 0) {
        [log appendString:@"Headers:\n"];
        [headers enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            [log appendFormat:@"%@: %@\n", key, obj];
        }];
    }

    NSData *body = nil;
    if ([request respondsToSelector:@selector(HTTPBody)]) {
        body = [(id)request HTTPBody];
    }
    if (body.length > 0) {
        NSString *bodyText = R0DataToUTF8OrNil(body);
        [log appendFormat:@"Body: %@\n", bodyText ?: R0DataToHex(body, 128)];
    }

    [log appendFormat:@"Stack:\n%@", R0CallStackString(3)];
    NSLog(@"%@", log);
}

void R0TrackStringSource(NSString *value, NSString *tag) {
    if (value.length == 0) {
        return;
    }
    NSLog(@"\n[R0RPC][Source] %@\nValue: %@\nStack:\n%@",
          tag ?: @"unknown",
          R0ShortString(value, 800),
          R0CallStackString(3));
}
