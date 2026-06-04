'use strict';

function stringValue(value) {
  if (value === null || value === undefined) {
    return '';
  }
  return String(value);
}

function registerHandlers(client) {
  const RelayHandler = Java.use('com.r0rpc.relay.api.RelayHandler');
  const LinkedHashMap = Java.use('java.util.LinkedHashMap');

  const PingHandler = Java.registerClass({
    name: 'com.r0rpc.frida.PingHandler',
    implements: [RelayHandler],
    methods: {
      handleRequest: [{
        returnType: 'void',
        argumentTypes: ['com.r0rpc.relay.api.RelayRequest', 'com.r0rpc.relay.api.RelayResponse'],
        implementation(_request, response) {
          response.success(LinkedHashMap.$new());
        }
      }]
    }
  });

  const DecryptHandler = Java.registerClass({
    name: 'com.r0rpc.frida.DecryptHandler',
    implements: [RelayHandler],
    methods: {
      handleRequest: [{
        returnType: 'void',
        argumentTypes: ['com.r0rpc.relay.api.RelayRequest', 'com.r0rpc.relay.api.RelayResponse'],
        implementation(request, response) {
          const store = globalThis.__r0rpcStore;
          if (!store || !store.classLoader) {
            response.failed('app classloader is not ready');
            return;
          }

          const payload = request.getPayload();
          const encodeStr = stringValue(payload.get('encode_str'));
          if (!encodeStr) {
            response.failed(400, 'encode_str is required');
            return;
          }

          const factory = Java.classFactory;
          const previousLoader = factory.loader;
          try {
            factory.loader = store.classLoader;
            const DecryptUtils = Java.use('com.taobao.android.remoteobject.easy.network.interceptor.DecryptUtils');
            const ret = DecryptUtils.doDecode(encodeStr);
            response.success(ret);
          } catch (err) {
            response.failed(String(err));
          } finally {
            factory.loader = previousLoader;
          }
        }
      }]
    }
  });

  client.registerHandler('ping', PingHandler.$new());
  client.registerHandler('decrypt', DecryptHandler.$new());
}

module.exports = {
  registerHandlers
};
