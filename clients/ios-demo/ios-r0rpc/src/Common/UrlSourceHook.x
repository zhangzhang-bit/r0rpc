#import <Foundation/Foundation.h>
#import "Groups.h"
#import "HookUtils.h"

%group UrlSourceGroup

%hook NSURL

+ (instancetype)URLWithString:(NSString *)URLString {
    NSURL *url = %orig;
    R0TrackStringSource(url.absoluteString ?: URLString, @"NSURL URLWithString:");
    return url;
}

+ (instancetype)URLWithString:(NSString *)URLString relativeToURL:(NSURL *)baseURL {
    NSURL *url = %orig;
    R0TrackStringSource(url.absoluteString ?: URLString, @"NSURL URLWithString:relativeToURL:");
    return url;
}

- (instancetype)initWithString:(NSString *)URLString {
    id result = %orig;
    NSString *value = [result isKindOfClass:[NSURL class]] ? [(NSURL *)result absoluteString] : URLString;
    R0TrackStringSource(value, @"NSURL initWithString:");
    return result;
}

- (instancetype)initWithString:(NSString *)URLString relativeToURL:(NSURL *)baseURL {
    id result = %orig;
    NSString *value = [result isKindOfClass:[NSURL class]] ? [(NSURL *)result absoluteString] : URLString;
    R0TrackStringSource(value, @"NSURL initWithString:relativeToURL:");
    return result;
}

%end

%hook NSMutableURLRequest

- (void)setURL:(NSURL *)url {
    %orig;
    R0TrackStringSource(url.absoluteString ?: @"nil", @"NSMutableURLRequest setURL:");
}

%end

%end

void initUrlSourceGroup(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(UrlSourceGroup);
    });
}
