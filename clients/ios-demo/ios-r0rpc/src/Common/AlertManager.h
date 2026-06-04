#ifndef AlertManager_h
#define AlertManager_h

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

void showDeviceAlert(NSString *deviceId);
void showAlertWithTitle(NSString *title, NSString *message);
void showAlertLater(NSString *deviceId, NSTimeInterval delaySeconds);

#ifdef __cplusplus
}
#endif

#endif
