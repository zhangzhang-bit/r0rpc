#import <Foundation/Foundation.h>
#import <substrate.h>
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonCryptor.h>
#import <CommonCrypto/CommonHMAC.h>
#import <Security/Security.h>
#import "Groups.h"

static unsigned char *(*orig_CC_MD5)(const void *, CC_LONG, unsigned char *);
static unsigned char *(*orig_CC_SHA1)(const void *, CC_LONG, unsigned char *);
static unsigned char *(*orig_CC_SHA256)(const void *, CC_LONG, unsigned char *);
static unsigned char *(*orig_CC_SHA384)(const void *, CC_LONG, unsigned char *);
static unsigned char *(*orig_CC_SHA512)(const void *, CC_LONG, unsigned char *);
static void (*orig_CCHmac)(CCHmacAlgorithm, const void *, CC_LONG, const void *, CC_LONG, void *);
static CCCryptorStatus (*orig_CCCrypt)(CCOperation, CCAlgorithm, CCOptions, const void *, size_t, const void *, const void *, size_t, void *, size_t, size_t *);
static OSStatus (*orig_SecKeyEncrypt)(SecKeyRef, SecPadding, const uint8_t *, size_t, uint8_t *, size_t *);
static OSStatus (*orig_SecKeyDecrypt)(SecKeyRef, SecPadding, const uint8_t *, size_t, uint8_t *, size_t *);

static NSString *R0Hex(NSData *data) {
    if (data.length == 0) return @"";
    const unsigned char *bytes = data.bytes;
    NSUInteger limit = MIN(data.length, 512);
    NSMutableString *hex = [NSMutableString stringWithCapacity:limit * 2];
    for (NSUInteger i = 0; i < limit; i++) {
        [hex appendFormat:@"%02x", bytes[i]];
    }
    if (data.length > limit) {
        [hex appendString:@"..."];
    }
    return hex;
}

static NSString *R0UTF8(NSData *data) {
    if (data.length == 0) return @"";
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    if (text.length > 1000) {
        return [[text substringToIndex:1000] stringByAppendingString:@"..."];
    }
    return text;
}

static void R0LogCrypto(NSString *title, NSString *detail) {
    NSLog(@"[R0RPC][Crypto] %@\n%@", title, detail);
}

unsigned char *r0_CC_MD5(const void *data, CC_LONG len, unsigned char *md) {
    unsigned char *ret = orig_CC_MD5(data, len, md);
    NSData *input = data ? [NSData dataWithBytes:data length:(NSUInteger)len] : [NSData data];
    NSData *output = md ? [NSData dataWithBytes:md length:CC_MD5_DIGEST_LENGTH] : [NSData data];
    R0LogCrypto(@"MD5", [NSString stringWithFormat:@"in.len=%d\nin.utf8=%@\nin.hex=%@\nout.hex=%@\n", len, R0UTF8(input), R0Hex(input), R0Hex(output)]);
    return ret;
}

unsigned char *r0_CC_SHA1(const void *data, CC_LONG len, unsigned char *md) {
    unsigned char *ret = orig_CC_SHA1(data, len, md);
    NSData *input = data ? [NSData dataWithBytes:data length:(NSUInteger)len] : [NSData data];
    NSData *output = md ? [NSData dataWithBytes:md length:CC_SHA1_DIGEST_LENGTH] : [NSData data];
    R0LogCrypto(@"SHA1", [NSString stringWithFormat:@"in.len=%d\nin.utf8=%@\nin.hex=%@\nout.hex=%@\n", len, R0UTF8(input), R0Hex(input), R0Hex(output)]);
    return ret;
}

unsigned char *r0_CC_SHA256(const void *data, CC_LONG len, unsigned char *md) {
    unsigned char *ret = orig_CC_SHA256(data, len, md);
    NSData *input = data ? [NSData dataWithBytes:data length:(NSUInteger)len] : [NSData data];
    NSData *output = md ? [NSData dataWithBytes:md length:CC_SHA256_DIGEST_LENGTH] : [NSData data];
    R0LogCrypto(@"SHA256", [NSString stringWithFormat:@"in.len=%d\nin.utf8=%@\nin.hex=%@\nout.hex=%@\n", len, R0UTF8(input), R0Hex(input), R0Hex(output)]);
    return ret;
}

unsigned char *r0_CC_SHA384(const void *data, CC_LONG len, unsigned char *md) {
    unsigned char *ret = orig_CC_SHA384(data, len, md);
    NSData *input = data ? [NSData dataWithBytes:data length:(NSUInteger)len] : [NSData data];
    NSData *output = md ? [NSData dataWithBytes:md length:CC_SHA384_DIGEST_LENGTH] : [NSData data];
    R0LogCrypto(@"SHA384", [NSString stringWithFormat:@"in.len=%d\nin.utf8=%@\nin.hex=%@\nout.hex=%@\n", len, R0UTF8(input), R0Hex(input), R0Hex(output)]);
    return ret;
}

unsigned char *r0_CC_SHA512(const void *data, CC_LONG len, unsigned char *md) {
    unsigned char *ret = orig_CC_SHA512(data, len, md);
    NSData *input = data ? [NSData dataWithBytes:data length:(NSUInteger)len] : [NSData data];
    NSData *output = md ? [NSData dataWithBytes:md length:CC_SHA512_DIGEST_LENGTH] : [NSData data];
    R0LogCrypto(@"SHA512", [NSString stringWithFormat:@"in.len=%d\nin.utf8=%@\nin.hex=%@\nout.hex=%@\n", len, R0UTF8(input), R0Hex(input), R0Hex(output)]);
    return ret;
}

void r0_CCHmac(CCHmacAlgorithm alg, const void *key, CC_LONG keyLen, const void *data, CC_LONG dataLen, void *out) {
    orig_CCHmac(alg, key, keyLen, data, dataLen, out);
    NSData *keyData = key ? [NSData dataWithBytes:key length:(NSUInteger)keyLen] : [NSData data];
    NSData *dataData = data ? [NSData dataWithBytes:data length:(NSUInteger)dataLen] : [NSData data];
    NSUInteger outLen = 0;
    switch (alg) {
        case kCCHmacAlgMD5: outLen = CC_MD5_DIGEST_LENGTH; break;
        case kCCHmacAlgSHA1: outLen = CC_SHA1_DIGEST_LENGTH; break;
        case kCCHmacAlgSHA224: outLen = CC_SHA224_DIGEST_LENGTH; break;
        case kCCHmacAlgSHA256: outLen = CC_SHA256_DIGEST_LENGTH; break;
        case kCCHmacAlgSHA384: outLen = CC_SHA384_DIGEST_LENGTH; break;
        case kCCHmacAlgSHA512: outLen = CC_SHA512_DIGEST_LENGTH; break;
        default: break;
    }
    NSData *outData = out && outLen > 0 ? [NSData dataWithBytes:out length:outLen] : [NSData data];
    R0LogCrypto(@"HMAC", [NSString stringWithFormat:@"key.utf8=%@\nkey.hex=%@\ndata.utf8=%@\ndata.hex=%@\nout.hex=%@\n",
                           R0UTF8(keyData), R0Hex(keyData), R0UTF8(dataData), R0Hex(dataData), R0Hex(outData)]);
}

CCCryptorStatus r0_CCCrypt(CCOperation op, CCAlgorithm alg, CCOptions options, const void *key, size_t keyLength, const void *iv, const void *dataIn, size_t dataInLength, void *dataOut, size_t dataOutAvailable, size_t *dataOutMoved) {
    CCCryptorStatus status = orig_CCCrypt(op, alg, options, key, keyLength, iv, dataIn, dataInLength, dataOut, dataOutAvailable, dataOutMoved);
    if (dataOutMoved != NULL && *dataOutMoved > 0) {
        NSData *input = dataIn ? [NSData dataWithBytes:dataIn length:dataInLength] : [NSData data];
        NSData *output = dataOut ? [NSData dataWithBytes:dataOut length:*dataOutMoved] : [NSData data];
        R0LogCrypto(@"CCCrypt", [NSString stringWithFormat:@"op=%d alg=%d options=%lu\nkey.hex=%@\niv.hex=%@\nin.hex=%@\nout.hex=%@\nstatus=%d\n",
                                  op, alg, (unsigned long)options,
                                  R0Hex(key ? [NSData dataWithBytes:key length:keyLength] : [NSData data]),
                                  R0Hex(iv ? [NSData dataWithBytes:iv length:(alg == kCCAlgorithmAES ? kCCBlockSizeAES128 : kCCBlockSizeDES)] : [NSData data]),
                                  R0Hex(input), R0Hex(output), status]);
    }
    return status;
}

OSStatus r0_SecKeyEncrypt(SecKeyRef key, SecPadding padding, const uint8_t *plain, size_t plainLen, uint8_t *cipher, size_t *cipherLen) {
    OSStatus status = orig_SecKeyEncrypt(key, padding, plain, plainLen, cipher, cipherLen);
    NSData *plainData = plain ? [NSData dataWithBytes:plain length:plainLen] : [NSData data];
    NSData *cipherData = cipher && cipherLen && *cipherLen > 0 ? [NSData dataWithBytes:cipher length:*cipherLen] : [NSData data];
    R0LogCrypto(@"SecKeyEncrypt", [NSString stringWithFormat:@"padding=%d\nplain.utf8=%@\nplain.hex=%@\ncipher.hex=%@\nstatus=%d\n",
                                    padding, R0UTF8(plainData), R0Hex(plainData), R0Hex(cipherData), (int)status]);
    return status;
}

OSStatus r0_SecKeyDecrypt(SecKeyRef key, SecPadding padding, const uint8_t *cipher, size_t cipherLen, uint8_t *plain, size_t *plainLen) {
    OSStatus status = orig_SecKeyDecrypt(key, padding, cipher, cipherLen, plain, plainLen);
    NSData *cipherData = cipher ? [NSData dataWithBytes:cipher length:cipherLen] : [NSData data];
    NSData *plainData = plain && plainLen && *plainLen > 0 ? [NSData dataWithBytes:plain length:*plainLen] : [NSData data];
    R0LogCrypto(@"SecKeyDecrypt", [NSString stringWithFormat:@"padding=%d\ncipher.hex=%@\nplain.utf8=%@\nplain.hex=%@\nstatus=%d\n",
                                    padding, R0Hex(cipherData), R0UTF8(plainData), R0Hex(plainData), (int)status]);
    return status;
}

void initCryptoGroup(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        MSHookFunction((void *)CC_MD5, (void *)r0_CC_MD5, (void **)&orig_CC_MD5);
        MSHookFunction((void *)CC_SHA1, (void *)r0_CC_SHA1, (void **)&orig_CC_SHA1);
        MSHookFunction((void *)CC_SHA256, (void *)r0_CC_SHA256, (void **)&orig_CC_SHA256);
        MSHookFunction((void *)CC_SHA384, (void *)r0_CC_SHA384, (void **)&orig_CC_SHA384);
        MSHookFunction((void *)CC_SHA512, (void *)r0_CC_SHA512, (void **)&orig_CC_SHA512);
        MSHookFunction((void *)CCHmac, (void *)r0_CCHmac, (void **)&orig_CCHmac);
        MSHookFunction((void *)CCCrypt, (void *)r0_CCCrypt, (void **)&orig_CCCrypt);
        MSHookFunction((void *)SecKeyEncrypt, (void *)r0_SecKeyEncrypt, (void **)&orig_SecKeyEncrypt);
        MSHookFunction((void *)SecKeyDecrypt, (void *)r0_SecKeyDecrypt, (void **)&orig_SecKeyDecrypt);
        NSLog(@"[R0RPC][Crypto] hooks installed");
    });
}
