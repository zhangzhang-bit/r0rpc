#import "Store.h"

@implementation Store {
    NSMutableDictionary *_store;
}

+ (instancetype)shared {
    static Store *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[Store alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _store = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)put:(id)object forKey:(NSString *)key {
    if (object == nil || key.length == 0) {
        return;
    }
    @synchronized (_store) {
        _store[key] = object;
    }
}

- (id)get:(NSString *)key {
    if (key.length == 0) {
        return nil;
    }
    @synchronized (_store) {
        return _store[key];
    }
}

- (void)remove:(NSString *)key {
    if (key.length == 0) {
        return;
    }
    @synchronized (_store) {
        [_store removeObjectForKey:key];
    }
}

- (BOOL)contains:(NSString *)key {
    if (key.length == 0) {
        return NO;
    }
    @synchronized (_store) {
        return _store[key] != nil;
    }
}

- (void)clear {
    @synchronized (_store) {
        [_store removeAllObjects];
    }
}

@end
