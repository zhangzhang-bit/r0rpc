'use strict';

let jarLoaded = false;

function ensureRelayJarLoaded(jarPath) {
  if (jarLoaded) {
    return;
  }
  Java.openClassFile(jarPath).load();
  jarLoaded = true;
  console.log(`[R0RPC] relay jar loaded from ${jarPath}`);
}

function getAndroidId(context) {
  const Secure = Java.use('android.provider.Settings$Secure');
  const androidId = Secure.getString(context.getContentResolver(), 'android_id');
  return androidId ? androidId.toString() : 'android-unknown';
}

function startRelayClient(config, clientId) {
  const RelayClient = Java.use('com.r0rpc.client.RelayClient');
  return RelayClient.$new(
    config.baseUrl,
    config.RPC_USERNAME,
    config.RPC_PASSWORD,
    clientId,
    config.RPC_GROUP,
    config.RPC_PLATFORM
  );
}

module.exports = {
  ensureRelayJarLoaded,
  getAndroidId,
  startRelayClient
};
