#ifndef RelayBootstrap_h
#define RelayBootstrap_h

#import <Foundation/Foundation.h>
#import "RelayClient.h"

typedef void (^R0RelayRegisterHandlersBlock)(RelayClient *client);

RelayClient *R0StartRelayClient(NSString *group, NSString *logName, R0RelayRegisterHandlersBlock registerHandlers);

#endif
