# iOS Demo

这个目录是 R0RPC 的 iOS 示例工程，包含 Theos tweak 和 Frida 脚本。当前主要维护 Theos 版本，用来注入目标 App 后连接 R0RPC 服务端，并在 App 进程内注册 RPC action 或安装调试 hook。

## 目录结构

```text
clients/ios-demo/
  ios-r0rpc/
    src/
      Tweak.x                 # 全局入口，按 bundle id 初始化对应模块
      Groups.h                # 各 Theos group 初始化函数声明
      Core/
        RelayClient.h
        RelayClient.m         # R0RPC WebSocket 客户端
        RPCConfig.*           # 服务端地址、账号、平台配置
        RPCResponse.*         # success / error 响应封装
        RelayBootstrap.*      # RelayClient 启动封装
      Common/
        NetworkHook.x         # 通用 NSURLSession 请求日志
        UrlSourceHook.x       # NSURL 构造来源追踪
        SchemeHook.x          # URL Scheme 入口追踪
        CryptoGroup.x         # CommonCrypto / Security 常见加密 hook
        Store.*
        HookUtils.*
        PayloadUtils.*        # job payload / 参数解析工具
        CaptureSession.*      # 异步捕获响应和超时清理
        ObjCRuntimeUtils.*    # ObjC runtime 检查工具
      Modules/
        yeemiao.x             # 小豆苗 RPC action
        teld.x                # 特来电 AES/DES hook
      utils/
        DeviceIdManager.*
        AppInfo.*
        NSString+JSON.*
  frida/
```

`Modules` 下按 App 平铺，一个 App 一个 `.x` 文件。handler 直接写在对应 App 的 `.x` 里，不再拆到外层 handler 文件。

## 注入范围

`ios-r0rpc/r0rpc-ios-demo.plist` 当前使用 `com.apple.UIKit`，默认 UIKit App 都可生效。实际开启/关闭某个 App 建议用 Choicy 管理。

`Tweak.x` 里仍按 bundle id 分发模块：

```text
com.threegene.yeemiao  -> initYeeMiaoGroup()
com.tgood.gotocharge   -> initTeldGroup()
```

通用 hook 会在入口初始化：

```text
NetworkGroup
UrlSourceGroup
SchemeGroup
CryptoGroup
```

## 模块说明

### yeemiao

文件：`ios-r0rpc/src/Modules/yeemiao.x`

RPC group：`yeemiao`

已注册 action：

```text
ping
get_sign
```

`get_sign` 调用 App 原生类：

```objc
YeemiaoJsonSerializer
+ buildSignJsonStringWithParameters:
```

兼容两种 payload：

```json
{"param":"{\"appKey\":\"xxx\",\"timestamp\":\"123\"}"}
```

```json
{"appKey":"xxx","timestamp":"123"}
```

旧版 `get_sign2` 最后也是通过 `objc_msgSend` 调同一个 selector，所以当前版本只保留 `get_sign`。

### teld

文件：`ios-r0rpc/src/Modules/teld.x`

当前是观察型 hook，没有注册 RPC action。

hook 目标：

```objc
TLDLoginManager
- AESForBaseSGEncrypt:
+ DESEncrypUserApiSGPlainText:
```

类可能晚加载，所以 `initTeldGroup()` 会找不到类时延迟重试。

## 默认服务端配置

Theos 模块里默认连接：

```text
baseURL:  http://159.75.100.225:9876
username: admin
password: 123456
platform: Apple
```

每个 App 模块里各自设置 RPC group。

服务端地址和账号集中在 `ios-r0rpc/src/Core/RPCConfig.m`，一般不需要再到每个 `Modules/*.x` 里改。

## 构建

iOS Theos tweak 不建议在 Windows 原生 PowerShell 里直接编译。推荐使用 macOS 或 WSL2 Ubuntu 配 Theos、iOS SDK、ldid、dpkg。

在可用的 Theos 环境中：

```bash
cd clients/ios-demo/ios-r0rpc
make package
make install
```

当前这台 Windows 环境未检测到 `make`，所以只能做静态检查，不能本机直接 `make package`。

## RPC 示例

小豆苗 ping：

```bash
curl -X POST "http://159.75.100.225:9876/rpc/invoke/yeemiao/ping" \
  -H "Content-Type: application/json" \
  -d '{"timeoutSeconds":20,"payload":{}}'
```

小豆苗 get_sign：

```bash
curl -X POST "http://159.75.100.225:9876/rpc/invoke/yeemiao/get_sign" \
  -H "Content-Type: application/json" \
  -d '{"timeoutSeconds":20,"payload":{"param":"{\"appKey\":\"xxx\",\"timestamp\":\"1234567890\"}"}}'
```

## 迁移说明

相比旧 `first-tweak`：

```text
SekiroClient -> RelayClient
Sekiro action -> R0RPC action
handler 文件 -> 对应 App 的 Modules/*.x
```

保留 iOS 原生 hook 思路，去掉旧 Sekiro 连接层和无效重复逻辑。

## iOS 当前保留说明

当前 `ios-r0rpc` 包只保留小豆苗和通用调试 hook。安装后打开小豆苗，如果看到设备 ID 弹框，说明 tweak 已经注入到 App 进程；随后会注册 `yeemiao/get_sign` RPC action。

Python 示例文件：`examples/python/ios_yeemiao_get_sign.py`

这个脚本用于请求 iOS 小豆苗端注册的 `yeemiao/get_sign`，请求地址是：

```text
POST http://159.75.100.225:9876/rpc/invoke/yeemiao/get_sign
```

脚本里的 `payload.param` 会被序列化成 JSON 字符串后传给小豆苗原生：

```objc
YeemiaoJsonSerializer
+ buildSignJsonStringWithParameters:
```

使用前确认三件事：

```text
1. 手机已安装最新版 ios-r0rpc tweak。
2. 小豆苗 App 已重新启动，并且出现过设备 ID 弹框。
3. 服务端能看到 iOS 客户端在线，group 为 yeemiao，action 为 get_sign。
```
