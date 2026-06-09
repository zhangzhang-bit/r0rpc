'use strict';

// ─── config ───────────────────────────────────────────────────────────────────
const config = {
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

// ─── relay_client ─────────────────────────────────────────────────────────────
const libdispatch = Process.getModuleByName('libdispatch.dylib');
const dispatchSemaphoreCreate = new NativeFunction(
  libdispatch.getExportByName('dispatch_semaphore_create'),
  'pointer',
  ['long']
);
const dispatchSemaphoreSignal = new NativeFunction(
  libdispatch.getExportByName('dispatch_semaphore_signal'),
  'long',
  ['pointer']
);
const dispatchSemaphoreWait = new NativeFunction(
  libdispatch.getExportByName('dispatch_semaphore_wait'),
  'long',
  ['pointer', 'uint64']
);

const DISPATCH_TIME_FOREVER = uint64('0xffffffffffffffff');

function waitSemaphore(sem) {
  dispatchSemaphoreWait(sem, DISPATCH_TIME_FOREVER);
}

function withSemaphore(block) {
  const sem = dispatchSemaphoreCreate(0);
  block(sem);
  waitSemaphore(sem);
}

function nsString(value) {
  return ObjC.classes.NSString.stringWithString_(value);
}

function jsonStringify(value) {
  const NSJSONSerialization = ObjC.classes.NSJSONSerialization;
  const NSString = ObjC.classes.NSString;
  const nsValue = plainToNSDictionary(value);
  const errPtr = Memory.alloc(Process.pointerSize);
  const data = NSJSONSerialization.dataWithJSONObject_options_error_(nsValue, 0, errPtr);
  if (data.isNull()) {
    return '{}';
  }
  return NSString.alloc().initWithData_encoding_(data, 4).toString();
}

function jsonParse(text) {
  const NSJSONSerialization = ObjC.classes.NSJSONSerialization;
  const NSString = ObjC.classes.NSString;
  const data = NSString.stringWithString_(text).dataUsingEncoding_(4);
  const errPtr = Memory.alloc(Process.pointerSize);
  const obj = NSJSONSerialization.JSONObjectWithData_options_error_(data, 0, errPtr);
  if (obj.isNull()) {
    return null;
  }
  return nsDictionaryToPlain(obj);
}

function nsDictionaryToPlain(obj) {
  if (obj.isKindOfClass_(ObjC.classes.NSString)) {
    return obj.toString();
  }
  if (obj.isKindOfClass_(ObjC.classes.NSNumber)) {
    return obj.doubleValue();
  }
  if (obj.isKindOfClass_(ObjC.classes.NSDictionary)) {
    const keys = obj.allKeys();
    const count = keys.count().valueOf();
    const out = {};
    for (let i = 0; i < count; i++) {
      const key = keys.objectAtIndex_(i).toString();
      out[key] = nsDictionaryToPlain(obj.objectForKey_(keys.objectAtIndex_(i)));
    }
    return out;
  }
  if (obj.isKindOfClass_(ObjC.classes.NSArray)) {
    const count = obj.count().valueOf();
    const out = [];
    for (let i = 0; i < count; i++) {
      out.push(nsDictionaryToPlain(obj.objectAtIndex_(i)));
    }
    return out;
  }
  return obj.toString();
}

function jsArrayToNSArray(arr) {
  const NSArray = ObjC.classes.NSArray;
  const NSMutableArray = ObjC.classes.NSMutableArray;
  const result = NSMutableArray.array();
  for (let i = 0; i < arr.length; i++) {
    result.addObject_(arr[i]);
  }
  return result;
}

function plainToNSDictionary(value) {
  const NSDictionary = ObjC.classes.NSDictionary;
  const NSNumber = ObjC.classes.NSNumber;
  if (value === null || value === undefined) {
    return NSDictionary.dictionary();
  }
  if (typeof value === 'string') {
    return nsString(value);
  }
  if (typeof value === 'number') {
    return NSNumber.numberWithDouble_(value);
  }
  if (typeof value === 'boolean') {
    return NSNumber.numberWithBool_(value ? 1 : 0);
  }
  if (Array.isArray(value)) {
    const items = value.map(plainToNSDictionary);
    return jsArrayToNSArray(items);
  }
  if (typeof value === 'object') {
    const ks = Object.keys(value).map(k => nsString(k));
    const vs = Object.keys(value).map(k => plainToNSDictionary(value[k]));
    return NSDictionary.dictionaryWithObjects_forKeys_(jsArrayToNSArray(vs), jsArrayToNSArray(ks));
  }
  return nsString(String(value));
}

function urlEncode(value) {
  let out = '';
  const bytes = Memory.allocUtf8String(value);
  let cursor = bytes;
  while (true) {
    const c = cursor.readU8();
    if (c === 0) {
      break;
    }
    const safe = (c >= 0x61 && c <= 0x7a) || (c >= 0x41 && c <= 0x5a) || (c >= 0x30 && c <= 0x39)
      || c === 0x2d || c === 0x5f || c === 0x2e || c === 0x7e;
    if (safe) {
      out += String.fromCharCode(c);
    } else {
      out += '%' + c.toString(16).toUpperCase().padStart(2, '0');
    }
    cursor = cursor.add(1);
  }
  return out;
}

class RelayClient {
  constructor(baseUrl, username, password, clientId, group, platform) {
    this.baseUrl = normalizeBaseUrl(baseUrl);
    this.username = username;
    this.password = password;
    this.clientId = clientId;
    this.group = group;
    this.platform = platform || 'ios';
    this.token = '';
    this.wsUrl = '';
    this.handlers = {};
    this.running = false;
    this.session = ObjC.classes.NSURLSession.sharedSession();
    this.webSocketTask = null;
    this.heartbeatTimer = null;
  }

  registerHandler(action, handler) {
    this.handlers[action] = handler;
  }

  start() {
    if (this.running) {
      return;
    }
    this.running = true;
    setImmediate(() => this.loopForever());
  }

  stop() {
    this.running = false;
    this.stopHeartbeat();
    if (this.webSocketTask) {
      this.webSocketTask.cancelWithCloseCode_reason_(1000, nsString(''));
      this.webSocketTask = null;
    }
  }

  loopForever() {
    let retryAttempt = 0;
    const tick = () => {
      if (!this.running) {
        return;
      }
      let connectedAt = 0;
      Promise.resolve()
        .then(() => {
          this.ensureLoggedIn();
          connectedAt = Date.now();
          return this.connectAndRun();
        })
        .then(() => {
          if (!this.running) {
            return;
          }
          if (Date.now() - connectedAt >= 60000) {
            retryAttempt = 0;
          }
        })
        .catch((err) => {
          if (!this.running) {
            return;
          }
          const message = String(err);
          if (message.includes('401') || message.toLowerCase().includes('unauthorized')) {
            this.token = '';
            this.wsUrl = '';
          }
          if (connectedAt > 0 && Date.now() - connectedAt >= 60000) {
            retryAttempt = 0;
          }
          console.log(`[R0RPC] reconnect scheduled, attempt=${retryAttempt + 1}, reason=${message}`);
        })
        .finally(() => {
          if (!this.running) {
            return;
          }
          const delayMs = retryDelayForAttempt(retryAttempt);
          retryAttempt += 1;
          setTimeout(tick, delayMs);
        });
    };
    tick();
  }

  ensureLoggedIn() {
    if (this.token) {
      return;
    }
    this.login();
  }

  login() {
    const url = ObjC.classes.NSURL.URLWithString_(nsString(`${this.baseUrl}/api/client/login`));
    const request = ObjC.classes.NSMutableURLRequest.requestWithURL_(url);
    request.setHTTPMethod_(nsString('POST'));
    request.setValue_forHTTPHeaderField_(nsString('application/json; charset=UTF-8'), nsString('Content-Type'));

    const body = plainToNSDictionary({
      username: this.username,
      password: this.password,
      clientId: this.clientId,
      group: this.group,
      platform: this.platform,
      maxInFlight: 64
    });
    const bodyErrPtr = Memory.alloc(Process.pointerSize);
    const bodyData = ObjC.classes.NSJSONSerialization.dataWithJSONObject_options_error_(body, 0, bodyErrPtr);
    request.setHTTPBody_(bodyData);

    let responseData = null;
    let statusCode = 0;
    let requestError = null;

    withSemaphore((sem) => {
      const completion = new ObjC.Block({
        retType: 'void',
        argTypes: ['object', 'object', 'object'],
        implementation(data, response, error) {
          responseData = data;
          if (response && response.isKindOfClass_(ObjC.classes.NSHTTPURLResponse)) {
            statusCode = response.statusCode();
          }
          requestError = error;
          dispatchSemaphoreSignal(sem);
        }
      });
      this.session.dataTaskWithRequest_completionHandler_(request, completion).resume();
    });

    if (requestError && !requestError.isNull()) {
      throw new Error(requestError.localizedDescription().toString());
    }
    if (statusCode >= 400) {
      throw new Error(`HTTP ${statusCode}`);
    }

    const text = ObjC.classes.NSString.alloc().initWithData_encoding_(responseData, 4).toString();
    const parsed = jsonParse(text);
    if (!parsed || !parsed.token) {
      throw new Error('login succeeded but token is missing');
    }
    this.token = parsed.token;
    this.wsUrl = parsed.wsUrl || this.buildWsUrl();
  }

  buildWsUrl() {
    let wsBase = this.baseUrl;
    if (wsBase.startsWith('https://')) {
      wsBase = `wss://${wsBase.substring(8)}`;
    } else if (wsBase.startsWith('http://')) {
      wsBase = `ws://${wsBase.substring(7)}`;
    }
    return `${wsBase}/api/client/ws?token=${urlEncode(this.token)}`;
  }

  connectAndRun() {
    const wsUrl = this.wsUrl || this.buildWsUrl();
    console.log(`[R0RPC] connecting wsUrl=${wsUrl}`);
    const url = ObjC.classes.NSURL.URLWithString_(nsString(wsUrl));
    this.webSocketTask = this.session.webSocketTaskWithURL_(url);
    this.webSocketTask.resume();
    this.startHeartbeat();
    console.log('[R0RPC] websocket resumed, starting readLoop');

    return new Promise((resolve, reject) => {
      const self = this;
      const readLoop = () => {
        if (!self.running || !self.webSocketTask) {
          resolve();
          return;
        }

        const completion = new ObjC.Block({
          retType: 'void',
          argTypes: ['object', 'object'],
          implementation: (message, error) => {
            console.log('[R0RPC] ws received callback');
            if (!self.running) {
              resolve();
              return;
            }
            if (error && !error.isNull()) {
              self.stopHeartbeat();
              self.webSocketTask = null;
              reject(new Error(error.localizedDescription().toString()));
              return;
            }
            let text = '';
            try {
              const msgType = message.type();
              console.log(`[R0RPC] ws message type=${msgType}`);
              // Try string() first regardless of type, since server sends text JSON
              try {
                const str = message.string();
                if (str) {
                  text = str.toString();
                }
              } catch (_e) {}
              // Fallback: if string() didn't work, try data() for binary
              if (!text) {
                try {
                  const data = message.data();
                  if (data && !data.isNull()) {
                    text = ObjC.classes.NSString.alloc().initWithData_encoding_(data, 4).toString();
                  }
                } catch (_e) {}
              }
              console.log(`[R0RPC] ws text length=${text.length}`);
            } catch (err) {
              console.log(`[R0RPC] read message type/data failed: ${err}`);
            }
            if (text) {
              try {
                self.handleIncomingText(text);
              } catch (err) {
                console.log(`[R0RPC] handle message failed: ${err}`);
              }
            }
            readLoop();
          }
        });

        // Keep strong reference to prevent GC
        self._lastCompletion = completion;
        self.webSocketTask.receiveMessageWithCompletionHandler_(completion);
      };

      readLoop();
    });
  }

  handleIncomingText(text) {
    let message;
    try {
      message = jsonParse(text);
    } catch (err) {
      console.log(`[R0RPC] jsonParse incoming failed: ${err}`);
      return;
    }
    if (!message || message.type !== 'job' || !message.job) {
      return;
    }
    const job = message.job;
    const action = String(job.action || '');
    const handler = this.handlers[action];
    const startedAt = Date.now();
    const requestId = String(job.requestId || '');

    console.log(`[R0RPC] dispatch action=${action}, requestId=${requestId}`);

    const respond = (status, httpCode, payload, error) => {
      const latencyMs = Date.now() - startedAt;
      console.log(`[R0RPC] respond action=${action}, status=${status}, latency=${latencyMs}ms`);
      this.sendResult(requestId, status, httpCode, payload || {}, error || '', latencyMs);
    };

    if (!handler) {
      respond('error', 500, {}, `No handler registered for action: ${action}`);
      return;
    }

    try {
      handler(job, respond);
    } catch (err) {
      console.log(`[R0RPC] handler threw: ${err}`);
      respond('error', 500, {}, String(err));
    }
  }

  sendResult(requestId, status, httpCode, payload, error, latencyMs) {
    if (!this.webSocketTask) {
      console.log(`[R0RPC] sendResult skipped, no webSocketTask`);
      return;
    }
    const envelope = {
      type: 'result',
      result: {
        requestId,
        status,
        httpCode,
        payload,
        error,
        latencyMs
      }
    };
    const jsonText = jsonStringify(envelope);
    console.log(`[R0RPC] sendResult jsonText length=${jsonText.length}`);
    const message = ObjC.classes.NSURLSessionWebSocketMessage.alloc().initWithString_(nsString(jsonText));
    this.webSocketTask.sendMessage_completionHandler_(message, new ObjC.Block({
      retType: 'void',
      argTypes: ['object'],
      implementation(sendError) {
        if (sendError && !sendError.isNull()) {
          console.log(`[R0RPC] send result failed: ${sendError.localizedDescription()}`);
        }
      }
    }));
  }

  startHeartbeat() {
    this.stopHeartbeat();
    this.heartbeatTimer = setInterval(() => {
      if (!this.webSocketTask) {
        return;
      }
      const message = ObjC.classes.NSURLSessionWebSocketMessage.alloc().initWithString_(nsString('{"type":"heartbeat"}'));
      this.webSocketTask.sendMessage_completionHandler_(message, new ObjC.Block({
        retType: 'void',
        argTypes: ['object'],
        implementation() {}
      }));
    }, 5000 + Math.floor(Math.random() * 1500));
  }

  stopHeartbeat() {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
  }
}

function normalizeBaseUrl(value) {
  let normalized = String(value || '').trim();
  if (!normalized) {
    throw new Error('baseUrl can not be empty');
  }
  if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
    normalized = `http://${normalized}`;
  }
  while (normalized.endsWith('/')) {
    normalized = normalized.slice(0, -1);
  }
  return normalized;
}

function retryDelayForAttempt(attempt) {
  const safeAttempt = Math.max(0, Math.min(attempt, 6));
  const capped = Math.min(1000 * (2 ** safeAttempt), 30000);
  if (capped <= 1000) {
    return 1000;
  }
  return 1000 + Math.floor(Math.random() * (capped - 1000 + 1));
}

// ─── handlers ─────────────────────────────────────────────────────────────────
function parseJsonDictionary(text) {
  if (!text || text === 'null') {
    return null;
  }
  try {
    const parsed = JSON.parse(text);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : null;
  } catch (_err) {
    return null;
  }
}

function parametersFromPayload(payload) {
  if (!payload || typeof payload !== 'object') {
    return null;
  }

  const param = payload.param;
  if (typeof param === 'string') {
    return parseJsonDictionary(param);
  }
  if (param && typeof param === 'object' && !Array.isArray(param)) {
    return param;
  }
  if (Object.keys(payload).length > 0) {
    return payload;
  }
  return null;
}

function buildSignWithParameters(parameters) {
  if (!ObjC.available) {
    throw new Error('ObjC runtime not available');
  }

  const serializerClass = ObjC.classes.YeemiaoJsonSerializer;
  if (!serializerClass) {
    throw new Error('YeemiaoJsonSerializer not found');
  }
  if (!serializerClass['buildSignJsonStringWithParameters:']) {
    throw new Error('buildSignJsonStringWithParameters: not found');
  }

  const nsParams = nsDictionaryFromPlain(parameters);
  const signResult = serializerClass['buildSignJsonStringWithParameters:'](nsParams);
  return signResult ? signResult.toString() : '';
}

function nsDictionaryFromPlain(value) {
  const NSString = ObjC.classes.NSString;
  const NSNumber = ObjC.classes.NSNumber;
  const NSDictionary = ObjC.classes.NSDictionary;

  if (value === null || value === undefined) {
    return NSDictionary.dictionary();
  }
  if (typeof value === 'string') {
    return NSString.stringWithString_(value);
  }
  if (typeof value === 'number') {
    return NSNumber.numberWithDouble_(value);
  }
  if (typeof value === 'boolean') {
    return NSNumber.numberWithBool_(value ? 1 : 0);
  }
  if (Array.isArray(value)) {
    return jsArrayToNSArray(value.map(nsDictionaryFromPlain));
  }
  if (typeof value === 'object') {
    const ks = Object.keys(value).map((key) => NSString.stringWithString_(key));
    const vs = Object.keys(value).map((key) => nsDictionaryFromPlain(value[key]));
    return NSDictionary.dictionaryWithObjects_forKeys_(jsArrayToNSArray(vs), jsArrayToNSArray(ks));
  }
  return NSString.stringWithString_(String(value));
}

function registerHandlers(client) {
  client.registerHandler('ping', (_job, respond) => {
    respond('success', 200, {}, '');
  });

  client.registerHandler('get_sign', (job, respond) => {
    console.log(`[R0RPC] get_sign handler called, job keys=${Object.keys(job).join(',')}`);
    const payload = job.payload && typeof job.payload === 'object' ? job.payload : {};
    const parameters = parametersFromPayload(payload);
    console.log(`[R0RPC] get_sign parameters=${JSON.stringify(parameters)}`);
    if (!parameters) {
      respond('error', 400, {}, 'param is required and must be valid json');
      return;
    }

    try {
      const sign = buildSignWithParameters(parameters);
      console.log(`[R0RPC] get_sign result=${sign}`);
      respond('success', 200, { sign }, '');
    } catch (err) {
      console.log(`[R0RPC] get_sign error: ${err}`);
      respond('error', 500, {}, String(err));
    }
  });
}

// ─── main ─────────────────────────────────────────────────────────────────────
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
