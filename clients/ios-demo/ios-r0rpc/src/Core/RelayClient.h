#import <Foundation/Foundation.h>

typedef void (^RelayJobHandler)(NSDictionary *job, void (^response)(NSString *status, NSInteger httpCode, NSDictionary *payload, NSString *error));

@interface RelayClient : NSObject

- (instancetype)initWithBaseURL:(NSString *)baseURL
                       username:(NSString *)username
                       password:(NSString *)password
                       clientId:(NSString *)clientId
                          group:(NSString *)group
                       platform:(NSString *)platform;

- (void)registerHandler:(NSString *)action handler:(RelayJobHandler)handler;
- (void)start;
- (void)stop;

@end
