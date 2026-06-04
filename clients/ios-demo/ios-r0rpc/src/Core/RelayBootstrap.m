#import "RelayBootstrap.h"
#import "RPCConfig.h"
#import "DeviceIdManager.h"

RelayClient *R0StartRelayClient(NSString *group, NSString *logName, R0RelayRegisterHandlersBlock registerHandlers) {
    NSString *clientId = R0GetDeviceIdentifier();
    RelayClient *client = [[RelayClient alloc] initWithBaseURL:R0RPCBaseURL()
                                                      username:R0RPCUsername()
                                                      password:R0RPCPassword()
                                                      clientId:clientId
                                                         group:group
                                                      platform:R0RPCPlatform()];
    if (registerHandlers) {
        registerHandlers(client);
    }
    [client start];
    NSLog(@"[R0RPC][%@] relay client started, clientId=%@", logName ?: group, clientId);
    return client;
}
