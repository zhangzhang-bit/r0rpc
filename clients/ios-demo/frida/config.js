'use strict';

module.exports = {
  RPC_HOST: '159.75.100.225',
  RPC_PORT: 9876,
  RPC_USERNAME: 'admin',
  RPC_PASSWORD: '123456',
  RPC_GROUP: 'yeemiao',
  RPC_PLATFORM: 'Apple',
  TARGET_BUNDLE_ID: 'com.threegene.yeemiao',
  get baseUrl() {
    return `http://${this.RPC_HOST}:${this.RPC_PORT}`;
  }
};
