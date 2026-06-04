'use strict';

const config = require('./config');
const { RelayClient } = require('./relay_client');
const { registerHandlers } = require('./handlers');

function getClientId() {
  if (!ObjC.available) {
    return 'ios-frida-unknown';
  }
  const idfv = ObjC.classes.UIDevice.currentDevice().identifierForVendor();
  return idfv ? idfv.UUIDString().toString() : 'ios-frida-unknown';
}

function startRelayOnce() {
  if (globalThis.__r0rpcStarted) {
    return;
  }
  globalThis.__r0rpcStarted = true;

  const clientId = getClientId();
  const bundleId = ObjC.classes.NSBundle.mainBundle().bundleIdentifier().toString();
  console.log(`[R0RPC] starting yeemiao relay client, clientId=${clientId}, bundle=${bundleId}`);

  const client = new RelayClient(
    config.baseUrl,
    config.RPC_USERNAME,
    config.RPC_PASSWORD,
    clientId,
    config.RPC_GROUP,
    config.RPC_PLATFORM
  );
  registerHandlers(client);
  client.start();
  globalThis.__r0rpcClient = client;
  console.log('[R0RPC] yeemiao relay client started');
}

function hookAppDelegateLaunch() {
  if (!ObjC.available) {
    console.log('[R0RPC] ObjC runtime not available');
    return;
  }

  const AppDelegate = ObjC.classes.AppDelegate;
  if (!AppDelegate) {
    console.log('[R0RPC] AppDelegate class not found, fallback to UIApplication hook');
    hookUIApplicationLaunch();
    return;
  }

  Interceptor.attach(AppDelegate['- application:didFinishLaunchingWithOptions:'].implementation, {
    onLeave() {
      startRelayOnce();
    }
  });
}

function hookUIApplicationLaunch() {
  const UIApplication = ObjC.classes.UIApplication;
  if (!UIApplication) {
    return;
  }

  Interceptor.attach(UIApplication['- application:didFinishLaunchingWithOptions:'].implementation, {
    onLeave() {
      startRelayOnce();
    }
  });
}

setImmediate(() => {
  if (!ObjC.available) {
    console.log('[R0RPC] frida ios-demo requires ObjC runtime');
    return;
  }

  const bundleId = ObjC.classes.NSBundle.mainBundle().bundleIdentifier().toString();
  console.log(`[R0RPC] frida ios-demo loaded, target=${config.TARGET_BUNDLE_ID}, current=${bundleId}`);

  if (bundleId !== config.TARGET_BUNDLE_ID) {
    console.log('[R0RPC] bundle mismatch, skip auto start');
    return;
  }

  hookAppDelegateLaunch();
  startRelayOnce();
});
