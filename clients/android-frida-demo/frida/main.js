'use strict';

const config = require('./config');
const { ensureRelayJarLoaded, getAndroidId, startRelayClient } = require('./relay_client');
const { registerHandlers } = require('./handlers');

function rememberAppContext(app) {
  globalThis.__r0rpcStore = {
    context: app,
    classLoader: app.getClassLoader()
  };
}

function startRelayOnce(app) {
  if (globalThis.__r0rpcStarted) {
    return;
  }
  globalThis.__r0rpcStarted = true;

  rememberAppContext(app);
  ensureRelayJarLoaded(config.RELAY_JAR_PATH);

  const clientId = getAndroidId(app);
  console.log(`[R0RPC] starting relay client, clientId=${clientId}, package=${app.getPackageName()}`);

  const client = startRelayClient(config, clientId);
  registerHandlers(client);
  client.start();
  globalThis.__r0rpcClient = client;
  console.log('[R0RPC] relay client started');
}

function hookActivityLaunch() {
  const ActivityThread = Java.use('android.app.ActivityThread');
  ActivityThread.performLaunchActivity.overloads.forEach((overload) => {
    overload.implementation = function () {
      const result = overload.apply(this, arguments);
      try {
        const app = this.mInitialApplication.value;
        if (app !== null) {
          startRelayOnce(app);
        }
      } catch (err) {
        console.log(`[R0RPC] performLaunchActivity hook failed: ${err}`);
      }
      return result;
    };
  });
}

function hookApplicationOnCreate() {
  const Application = Java.use('android.app.Application');
  Application.onCreate.implementation = function () {
    this.onCreate();
    try {
      startRelayOnce(this);
    } catch (err) {
      console.log(`[R0RPC] Application.onCreate hook failed: ${err}`);
    }
  };
}

function bootstrap() {
  Java.perform(function () {
    console.log(`[R0RPC] android frida demo loaded, target=${config.TARGET_PACKAGE}`);
    hookActivityLaunch();
    hookApplicationOnCreate();

    try {
      const ActivityThread = Java.use('android.app.ActivityThread');
      const app = ActivityThread.currentApplication();
      if (app !== null) {
        startRelayOnce(app);
      }
    } catch (_err) {
      // App may not be ready yet; hooks above will start relay later.
    }
  });
}

setImmediate(bootstrap);
