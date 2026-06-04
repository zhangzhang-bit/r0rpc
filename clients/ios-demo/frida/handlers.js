'use strict';

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
  const NSArray = ObjC.classes.NSArray;

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
    return NSArray.arrayWithArray_(value.map(nsDictionaryFromPlain));
  }
  if (typeof value === 'object') {
    const keys = Object.keys(value).map((key) => NSString.stringWithString_(key));
    const vals = Object.keys(value).map((key) => nsDictionaryFromPlain(value[key]));
    return NSDictionary.dictionaryWithObjects_forKeys_(vals, keys);
  }
  return NSString.stringWithString_(String(value));
}

function registerHandlers(client) {
  client.registerHandler('ping', (_job, respond) => {
    respond('success', 200, {}, '');
  });

  client.registerHandler('get_sign', (job, respond) => {
    const payload = job.payload && typeof job.payload === 'object' ? job.payload : {};
    const parameters = parametersFromPayload(payload);
    if (!parameters) {
      respond('error', 400, {}, 'param is required and must be valid json');
      return;
    }

    try {
      const sign = buildSignWithParameters(parameters);
      respond('success', 200, { sign }, '');
    } catch (err) {
      respond('error', 500, {}, String(err));
    }
  });
}

module.exports = {
  registerHandlers
};
