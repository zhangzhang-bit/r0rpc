'use strict';

const dispatchSemaphoreCreate = new NativeFunction(
  Module.getGlobalExportByName('dispatch_semaphore_create'),
  'pointer',
  ['long']
);
const dispatchSemaphoreSignal = new NativeFunction(
  Module.getGlobalExportByName('dispatch_semaphore_signal'),
  'long',
  ['pointer']
);
const dispatchSemaphoreWait = new NativeFunction(
  Module.getGlobalExportByName('dispatch_semaphore_wait'),
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
  const data = NSJSONSerialization.dataWithJSONObject_options_error_(nsValue, 0, NULL);
  if (data.isNull()) {
    return '{}';
  }
  return NSString.alloc().initWithData_encoding_(data, 4).toString();
}

function jsonParse(text) {
  const NSJSONSerialization = ObjC.classes.NSJSONSerialization;
  const NSString = ObjC.classes.NSString;
  const data = NSString.stringWithString_(text).dataUsingEncoding_(4);
  const obj = NSJSONSerialization.JSONObjectWithData_options_error_(data, 0, NULL);
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
    const NSArray = ObjC.classes.NSArray;
    const items = value.map(plainToNSDictionary);
    return NSArray.arrayWithArray_(items);
  }
  if (typeof value === 'object') {
    const keys = Object.keys(value).map(k => nsString(k));
    const vals = Object.keys(value).map(k => plainToNSDictionary(value[k]));
    return NSDictionary.dictionaryWithObjects_forKeys_(vals, keys);
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
    const bodyData = ObjC.classes.NSJSONSerialization.dataWithJSONObject_options_error_(body, 0, NULL);
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
    const url = ObjC.classes.NSURL.URLWithString_(nsString(wsUrl));
    this.webSocketTask = this.session.webSocketTaskWithURL_(url);
    this.webSocketTask.resume();
    this.startHeartbeat();

    return new Promise((resolve, reject) => {
      const readLoop = () => {
        if (!this.running || !this.webSocketTask) {
          resolve();
          return;
        }

        const completion = new ObjC.Block({
          retType: 'void',
          argTypes: ['object', 'object'],
          implementation: (message, error) => {
            if (!this.running) {
              resolve();
              return;
            }
            if (error && !error.isNull()) {
              this.stopHeartbeat();
              this.webSocketTask = null;
              reject(new Error(error.localizedDescription().toString()));
              return;
            }
            let text = '';
            if (message.type() === 0) {
              text = message.string().toString();
            } else if (message.type() === 1) {
              text = ObjC.classes.NSString.alloc().initWithData_encoding_(message.data(), 4).toString();
            }
            if (text) {
              try {
                this.handleIncomingText(text);
              } catch (err) {
                console.log(`[R0RPC] handle message failed: ${err}`);
              }
            }
            readLoop();
          }
        });

        this.webSocketTask.receiveMessageWithCompletionHandler_(completion);
      };

      readLoop();
    });
  }

  handleIncomingText(text) {
    const message = jsonParse(text);
    if (!message || message.type !== 'job' || !message.job) {
      return;
    }
    const job = message.job;
    const action = String(job.action || '');
    const handler = this.handlers[action];
    const startedAt = Date.now();
    const requestId = String(job.requestId || '');

    const respond = (status, httpCode, payload, error) => {
      const latencyMs = Date.now() - startedAt;
      this.sendResult(requestId, status, httpCode, payload || {}, error || '', latencyMs);
    };

    if (!handler) {
      respond('error', 500, {}, `No handler registered for action: ${action}`);
      return;
    }

    try {
      handler(job, respond);
    } catch (err) {
      respond('error', 500, {}, String(err));
    }
  }

  sendResult(requestId, status, httpCode, payload, error, latencyMs) {
    if (!this.webSocketTask) {
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
    const message = ObjC.classes.NSURLSessionWebSocketMessage.messageWithString_(nsString(jsonText));
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
      const message = ObjC.classes.NSURLSessionWebSocketMessage.messageWithString_(nsString('{"type":"heartbeat"}'));
      this.webSocketTask.sendMessage_completionHandler_(message, NULL);
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

module.exports = {
  RelayClient
};
