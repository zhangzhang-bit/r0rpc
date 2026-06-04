#import "PayloadUtils.h"
#import "NSString+JSON.h"

NSDictionary *R0JobPayload(NSDictionary *job) {
    return [job[@"payload"] isKindOfClass:[NSDictionary class]] ? job[@"payload"] : @{};
}

NSString *R0StringValue(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    if (value != nil && value != [NSNull null]) {
        return [NSString stringWithFormat:@"%@", value];
    }
    return @"";
}

NSString *R0PayloadString(NSDictionary *payload, NSString *key) {
    return R0StringValue(payload[key]);
}

NSDictionary *R0DictionaryFromParamPayload(NSDictionary *payload) {
    id param = payload[@"param"];
    if ([param isKindOfClass:[NSString class]]) {
        return [(NSString *)param r0_jsonDictionary];
    }
    if ([param isKindOfClass:[NSDictionary class]]) {
        return param;
    }
    if (payload.count > 0) {
        return payload;
    }
    return nil;
}
