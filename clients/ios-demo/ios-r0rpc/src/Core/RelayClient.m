#import "RelayClient.h"

static NSString *const kRelayLogTag = @"R0RPC";

static NSTimeInterval const kBaseRetryDelay = 1.0;
static NSTimeInterval const kMaxRetryDelay = 30.0;
static NSTimeInterval const kHeartbeatInterval = 5.0;
static NSTimeInterval const kHeartbeatJitter = 1.5;

@interface RelayClient ()
@property (nonatomic, copy) NSString *baseURL;
@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy) NSString *password;
@property (nonatomic, copy) NSString *clientId;
@property (nonatomic, copy) NSString *group;
@property (nonatomic, copy) NSString *platform;
@property (nonatomic, copy) NSString *token;
@property (nonatomic, copy) NSString *wsURL;
@property (nonatomic, strong) NSMutableDictionary<NSString *, RelayJobHandler> *handlers;
@property (nonatomic, strong) dispatch_queue_t workerQueue;
@property (nonatomic, strong) dispatch_queue_t jobQueue;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionWebSocketTask *webSocketTask;
@property (nonatomic, strong) dispatch_source_t heartbeatTimer;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) BOOL started;
@property (nonatomic, assign) NSInteger maxInFlight;
@end

@implementation RelayClient

- (instancetype)initWithBaseURL:(NSString *)baseURL
                       username:(NSString *)username
                       password:(NSString *)password
                       clientId:(NSString *)clientId
                          group:(NSString *)group
                       platform:(NSString *)platform {
    self = [super init];
    if (self) {
        _baseURL = [self normalizedBaseURL:baseURL];
        _username = [username copy];
        _password = [password copy];
        _clientId = [clientId copy];
        _group = [group copy];
        _platform = platform.length > 0 ? [platform copy] : @"ios";
        _handlers = [NSMutableDictionary dictionary];
        _workerQueue = dispatch_queue_create("com.r0rpc.relay.worker", DISPATCH_QUEUE_SERIAL);
        _jobQueue = dispatch_queue_create("com.r0rpc.relay.jobs", DISPATCH_QUEUE_CONCURRENT);
        _session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration];
        _maxInFlight = 64;
    }
    return self;
}

- (void)registerHandler:(NSString *)action handler:(RelayJobHandler)handler {
    if (action.length == 0 || handler == nil) {
        return;
    }
    self.handlers[action] = [handler copy];
}

- (void)start {
    if (self.started) {
        return;
    }
    self.started = YES;
    self.running = YES;
    dispatch_async(self.workerQueue, ^{
        [self loopForever];
    });
}

- (void)stop {
    self.running = NO;
    [self stopHeartbeat];
    [self.webSocketTask cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:nil];
    self.webSocketTask = nil;
}

#pragma mark - Connection loop

- (void)loopForever {
    NSInteger retryAttempt = 0;
    while (self.running) {
        @autoreleasepool {
            NSDate *connectedAt = nil;
            @try {
                [self ensureLoggedIn];
                connectedAt = [NSDate date];
                [self connectAndRun];
                if (!self.running) {
                    return;
                }
                if (connectedAt && [[NSDate date] timeIntervalSinceDate:connectedAt] >= 60.0) {
                    retryAttempt = 0;
                }
            } @catch (NSException *exception) {
                if (!self.running) {
                    return;
                }
                NSString *message = exception.reason ?: exception.name;
                if ([message containsString:@"401"] || [message localizedCaseInsensitiveContainsString:@"unauthorized"]) {
                    self.token = nil;
                    self.wsURL = nil;
                }
                if (connectedAt && [[NSDate date] timeIntervalSinceDate:connectedAt] >= 60.0) {
                    retryAttempt = 0;
                }
                NSLog(@"[%@] reconnect scheduled, attempt=%ld, reason=%@", kRelayLogTag, (long)retryAttempt + 1, message);
            }
            NSTimeInterval delay = [self retryDelayForAttempt:retryAttempt];
            retryAttempt += 1;
            [NSThread sleepForTimeInterval:delay];
        }
    }
}

- (void)connectAndRun {
    NSString *wsURLString = self.wsURL.length > 0 ? self.wsURL : [self buildWSURL];
    NSURL *url = [NSURL URLWithString:wsURLString];
    if (url == nil) {
        @throw [NSException exceptionWithName:@"RelayClientError" reason:@"invalid ws url" userInfo:nil];
    }

    self.webSocketTask = [self.session webSocketTaskWithURL:url];
    [self.webSocketTask resume];
    [self startHeartbeat];

    while (self.running) {
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        __block NSString *text = nil;
        __block NSError *readError = nil;

        [self.webSocketTask receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message, NSError *error) {
            readError = error;
            if (message.type == NSURLSessionWebSocketMessageTypeString) {
                text = message.string;
            } else if (message.type == NSURLSessionWebSocketMessageTypeData && message.data != nil) {
                text = [[NSString alloc] initWithData:message.data encoding:NSUTF8StringEncoding];
            }
            dispatch_semaphore_signal(sem);
        }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

        if (readError != nil || text.length == 0) {
            [self stopHeartbeat];
            [self.webSocketTask cancelWithCloseCode:NSURLSessionWebSocketCloseCodeGoingAway reason:nil];
            self.webSocketTask = nil;
            if (readError != nil) {
                @throw [NSException exceptionWithName:@"RelayClientError" reason:readError.localizedDescription userInfo:nil];
            }
            return;
        }

        [self handleIncomingText:text];
    }
}

#pragma mark - Message handling

- (void)handleIncomingText:(NSString *)text {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![parsed isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSDictionary *message = (NSDictionary *)parsed;
    if (![message[@"type"] isEqualToString:@"job"]) {
        return;
    }
    id jobObject = message[@"job"];
    if (![jobObject isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSDictionary *job = [(NSDictionary *)jobObject copy];
    dispatch_async(self.jobQueue, ^{
        [self dispatchJob:job];
    });
}

- (void)dispatchJob:(NSDictionary *)job {
    NSString *action = [self stringValue:job[@"action"]];
    RelayJobHandler handler = self.handlers[action];
    NSDate *startedAt = [NSDate date];
    NSString *requestId = [self stringValue:job[@"requestId"]];

    void (^response)(NSString *, NSInteger, NSDictionary *, NSString *) = ^(NSString *status, NSInteger httpCode, NSDictionary *payload, NSString *error) {
        NSTimeInterval latencyMs = [[NSDate date] timeIntervalSinceDate:startedAt] * 1000.0;
        [self sendResultWithRequestId:requestId status:status httpCode:httpCode payload:payload ?: @{} error:error ?: @"" latencyMs:(NSInteger)latencyMs];
    };

    if (handler == nil) {
        response(@"error", 500, @{}, [NSString stringWithFormat:@"No handler registered for action: %@", action]);
        return;
    }

    @try {
        handler(job, response);
    } @catch (NSException *exception) {
        response(@"error", 500, @{}, exception.reason ?: exception.name);
    }
}

- (void)sendResultWithRequestId:(NSString *)requestId
                         status:(NSString *)status
                       httpCode:(NSInteger)httpCode
                        payload:(NSDictionary *)payload
                          error:(NSString *)error
                      latencyMs:(NSInteger)latencyMs {
    NSDictionary *resultBody = @{
        @"requestId": requestId ?: @"",
        @"status": status ?: @"error",
        @"httpCode": @(httpCode),
        @"payload": payload ?: @{},
        @"error": error ?: @"",
        @"latencyMs": @(latencyMs)
    };
    NSDictionary *envelope = @{
        @"type": @"result",
        @"result": resultBody
    };
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:envelope options:0 error:nil];
    NSString *jsonText = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    if (jsonText.length == 0) {
        return;
    }

    NSURLSessionWebSocketMessage *message = [[NSURLSessionWebSocketMessage alloc] initWithString:jsonText];
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [self.webSocketTask sendMessage:message completionHandler:^(NSError *sendError) {
        if (sendError != nil) {
            NSLog(@"[%@] send result failed: %@", kRelayLogTag, sendError.localizedDescription);
        }
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
}

#pragma mark - Heartbeat

- (void)startHeartbeat {
    [self stopHeartbeat];
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    self.heartbeatTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    if (self.heartbeatTimer == nil) {
        return;
    }
    uint64_t intervalNs = (uint64_t)((kHeartbeatInterval + (arc4random_uniform((uint32_t)(kHeartbeatJitter * 1000)) / 1000.0)) * NSEC_PER_SEC);
    dispatch_source_set_timer(self.heartbeatTimer, dispatch_time(DISPATCH_TIME_NOW, intervalNs), intervalNs, (uint64_t)(0.2 * NSEC_PER_SEC));
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(self.heartbeatTimer, ^{
        [weakSelf sendHeartbeat];
    });
    dispatch_resume(self.heartbeatTimer);
}

- (void)stopHeartbeat {
    if (self.heartbeatTimer != nil) {
        dispatch_source_cancel(self.heartbeatTimer);
        self.heartbeatTimer = nil;
    }
}

- (void)sendHeartbeat {
    if (self.webSocketTask == nil) {
        return;
    }
    NSURLSessionWebSocketMessage *message = [[NSURLSessionWebSocketMessage alloc] initWithString:@"{\"type\":\"heartbeat\"}"];
    [self.webSocketTask sendMessage:message completionHandler:^(NSError *error) {
        if (error != nil) {
            NSLog(@"[%@] heartbeat failed: %@", kRelayLogTag, error.localizedDescription);
        }
    }];
}

#pragma mark - Login

- (void)ensureLoggedIn {
    if (self.token.length > 0) {
        return;
    }
    [self login];
}

- (void)login {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/client/login", self.baseURL]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json; charset=UTF-8" forHTTPHeaderField:@"Content-Type"];
    NSDictionary *body = @{
        @"username": self.username ?: @"",
        @"password": self.password ?: @"",
        @"clientId": self.clientId ?: @"",
        @"group": self.group ?: @"",
        @"platform": self.platform ?: @"ios",
        @"maxInFlight": @(self.maxInFlight)
    };
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSData *responseData = nil;
    __block NSHTTPURLResponse *httpResponse = nil;
    __block NSError *requestError = nil;

    [[self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        responseData = data;
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            httpResponse = (NSHTTPURLResponse *)response;
        }
        requestError = error;
        dispatch_semaphore_signal(sem);
    }] resume];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

    if (requestError != nil) {
        @throw [NSException exceptionWithName:@"RelayClientError" reason:requestError.localizedDescription userInfo:nil];
    }
    if (httpResponse.statusCode >= 400) {
        @throw [NSException exceptionWithName:@"RelayClientError" reason:[NSString stringWithFormat:@"HTTP %ld", (long)httpResponse.statusCode] userInfo:nil];
    }

    id parsed = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:nil];
    if (![parsed isKindOfClass:[NSDictionary class]]) {
        @throw [NSException exceptionWithName:@"RelayClientError" reason:@"invalid login response" userInfo:nil];
    }
    NSDictionary *responseBody = (NSDictionary *)parsed;
    NSString *token = [self stringValue:responseBody[@"token"]];
    if (token.length == 0) {
        @throw [NSException exceptionWithName:@"RelayClientError" reason:@"login succeeded but token is missing" userInfo:nil];
    }
    self.token = token;
    NSString *wsURL = [self stringValue:responseBody[@"wsUrl"]];
    self.wsURL = wsURL.length > 0 ? wsURL : [self buildWSURL];

    NSNumber *maxInFlight = responseBody[@"maxInFlight"];
    if ([maxInFlight isKindOfClass:[NSNumber class]] && maxInFlight.integerValue > 0) {
        self.maxInFlight = maxInFlight.integerValue;
    }
}

#pragma mark - Helpers

- (NSString *)normalizedBaseURL:(NSString *)value {
    NSString *normalized = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (normalized.length == 0) {
        @throw [NSException exceptionWithName:@"RelayClientError" reason:@"baseURL can not be empty" userInfo:nil];
    }
    if (![normalized hasPrefix:@"http://"] && ![normalized hasPrefix:@"https://"]) {
        normalized = [@"http://" stringByAppendingString:normalized];
    }
    while ([normalized hasSuffix:@"/"]) {
        normalized = [normalized substringToIndex:normalized.length - 1];
    }
    return normalized;
}

- (NSString *)buildWSURL {
    NSString *wsBase = self.baseURL;
    if ([wsBase hasPrefix:@"https://"]) {
        wsBase = [@"wss://" stringByAppendingString:[wsBase substringFromIndex:8]];
    } else if ([wsBase hasPrefix:@"http://"]) {
        wsBase = [@"ws://" stringByAppendingString:[wsBase substringFromIndex:7]];
    }
    NSString *encodedToken = [self urlEncode:self.token ?: @""];
    return [NSString stringWithFormat:@"%@/api/client/ws?token=%@", wsBase, encodedToken];
}

- (NSString *)urlEncode:(NSString *)value {
    NSMutableString *result = [NSMutableString string];
    const char *bytes = value.UTF8String;
    for (const char *cursor = bytes; cursor != NULL && *cursor != '\0'; cursor++) {
        unsigned char c = (unsigned char)*cursor;
        BOOL safe = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' || c == '~';
        if (safe) {
            [result appendFormat:@"%c", c];
        } else {
            [result appendFormat:@"%%%02X", c];
        }
    }
    return result;
}

- (NSTimeInterval)retryDelayForAttempt:(NSInteger)attempt {
    NSInteger safeAttempt = MAX(0, MIN(attempt, 6));
    NSTimeInterval capped = kBaseRetryDelay * pow(2.0, safeAttempt);
    capped = MIN(capped, kMaxRetryDelay);
    if (capped <= kBaseRetryDelay) {
        return kBaseRetryDelay;
    }
    return kBaseRetryDelay + ((double)arc4random_uniform((uint32_t)((capped - kBaseRetryDelay) * 1000.0)) / 1000.0);
}

- (NSString *)stringValue:(id)value {
    if (value == nil || value == [NSNull null]) {
        return @"";
    }
    if ([value isKindOfClass:[NSString class]]) {
        return (NSString *)value;
    }
    return [NSString stringWithFormat:@"%@", value];
}

@end
