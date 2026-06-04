# Android Frida Demo

Frida version of the Android RPC demo, aligned with `clients/xposed-demo`.

It injects into a target app at runtime, loads the existing Java relay client jar, and registers the same actions:

- `ping`
- `decrypt`

## Prerequisites

- Frida on host machine
- `frida-server` running on Android device/emulator
- Bundled relay jar: `lib/r0rpc-relay-client.jar`

Refresh the bundled jar from Java SDK if needed:

```powershell
cd clients/android-frida-demo
powershell -ExecutionPolicy Bypass -File .\sync-jar.ps1
```

Push the jar to device:

```bash
adb push lib/r0rpc-relay-client.jar /data/local/tmp/r0rpc-relay-client.jar
```

## Configure

Edit `frida/config.js`:

- `RPC_HOST` / `RPC_PORT`
- `RPC_USERNAME` / `RPC_PASSWORD`
- `RPC_GROUP`
- `TARGET_PACKAGE`
- `RELAY_JAR_PATH` if you use a different device path

Default target package is `com.taobao.idlefish`.

## Run

Spawn target app:

```bash
cd clients/android-frida-demo
frida -U -f com.taobao.idlefish -l frida/main.js --no-pause
```

Attach to a running process:

```bash
frida -U com.taobao.idlefish -l frida/main.js
```

## Files

- `lib/r0rpc-relay-client.jar` — bundled relay client jar
- `sync-jar.ps1` — rebuild and copy jar from `clients/java`
- `frida/main.js` — hooks app startup and starts relay once
- `frida/relay_client.js` — loads relay jar and creates `RelayClient`
- `frida/handlers.js` — registers `ping` / `decrypt`
- `frida/config.js` — server and target config

## Test

```bash
curl -X POST "http://159.75.100.225:9876/rpc/invoke/idlefish/ping" \
  -H "Content-Type: application/json" \
  -d '{"timeoutSeconds":20,"payload":{}}'
```

Decrypt example:

```bash
curl -X POST "http://159.75.100.225:9876/rpc/invoke/idlefish/decrypt" \
  -H "Content-Type: application/json" \
  -d '{"timeoutSeconds":20,"payload":{"encode_str":"your-encoded-string"}}'
```

## Notes

- This demo reuses `r0rpc-relay-client.jar`, same as the Xposed project
- `decrypt` calls `com.taobao.android.remoteobject.easy.network.interceptor.DecryptUtils.doDecode`
- Hook points match the Xposed demo: `ActivityThread.performLaunchActivity` with `Application.onCreate` fallback
- For quick iteration, Frida is usually easier than rebuilding the Xposed module
