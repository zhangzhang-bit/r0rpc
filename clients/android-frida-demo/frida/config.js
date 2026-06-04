'use strict';

module.exports = {
  RPC_HOST: '159.75.100.225',
  RPC_PORT: 9876,
  RPC_USERNAME: 'admin',
  RPC_PASSWORD: '123456',
  RPC_GROUP: 'idlefish',
  RPC_PLATFORM: 'android',
  TARGET_PACKAGE: 'com.taobao.idlefish',
  // Push jar to device first:
  // adb push lib/r0rpc-relay-client.jar /data/local/tmp/r0rpc-relay-client.jar
  RELAY_JAR_PATH: '/data/local/tmp/r0rpc-relay-client.jar',
  get baseUrl() {
    return `http://${this.RPC_HOST}:${this.RPC_PORT}`;
  }
};
