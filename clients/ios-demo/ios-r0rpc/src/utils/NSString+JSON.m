#import "NSString+JSON.h"

@implementation NSString (R0JSON)

- (NSDictionary *)r0_jsonDictionary {
    if (self.length == 0 || [self isEqualToString:@"null"]) {
        return nil;
    }

    NSData *jsonData = [self dataUsingEncoding:NSUTF8StringEncoding];
    if (jsonData.length == 0) {
        return nil;
    }

    id jsonObject = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
    return [jsonObject isKindOfClass:[NSDictionary class]] ? (NSDictionary *)jsonObject : nil;
}

@end
