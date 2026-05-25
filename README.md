# R0RPC 项目总览

R0RPC 是一个面向设备侧的 RPC 中继平台，整体思路类似 Sekiro RPC，但更偏向“可部署、可管理、可观测”的后台化方案。

它适合把 Android、Xposed、Java 或 Python 侧设备接入到服务端，然后由业务后端按 `group` 或指定 `clientId` 发起调用。设备收到任务后执行动作，并把结果实时回传给调用方。

## 快速导航

- 部署入口：`deploy/linux/quickstart.sh`
- 管理后台：`http://YOUR_SERVER_IP:9876/`
- 健康检查：`http://YOUR_SERVER_IP:9876/healthz`
- 配置模板：`deploy/linux/.env.example`
- 运行配置：`deploy/linux/.env.docker`
- Java SDK：`clients/java/`
- Xposed 示例：`clients/xposed-demo/`
- Python 示例：`examples/python/`

## 1. 项目是什么

R0RPC 的核心目标是：

1. 让后端服务可以按 `group` 或指定 `clientId` 把请求发到在线设备
2. 让设备执行动作后，把结果实时回传给后端
3. 提供管理后台，用来查看账号、分组、设备、调用记录、统计指标和在线状态
4. 支持 Linux 一键部署，默认可连本机 Docker MySQL/Redis，也支持接入外部 MySQL/Redis

当前版本以 Linux 部署为主，不再围绕 Windows 本地启动维护。

## 2. 核心特性

- WebSocket 长连接：设备在线后通过 WebSocket 收任务、回结果
- 分组治理：`group` 必须先在后台创建，才能被设备登录和 RPC 调用使用
- 在线设备队列：按 `group` 查看在线设备，支持轮询分发
- 指定设备调用：传入 `clientId` 后只发给指定设备
- 管理后台：查看账号、分组、设备、调用记录、趋势指标
- Linux 一键部署：自动安装 Docker、启动依赖、初始化数据库、拉起服务
- 配置集中化：运行参数集中放在 `deploy/linux/.env.docker`
- Java/Xposed/Python 示例：方便设备侧和脚本侧快速联调

## 3. 项目结构

```text
cmd/                  Go 程序入口
cmd/server            主服务入口
cmd/dbinit            数据库初始化入口

internal/             Go 服务核心代码
internal/config       配置读取
internal/store        MySQL/Redis 存储逻辑
internal/rpc          RPC 调度逻辑
internal/web          Web API、WebSocket、内置前端

deploy/linux/         Linux 一键部署入口
clients/java/         Java Relay Client SDK
clients/xposed-demo/  Android/Xposed 示例项目
examples/python/      Python 调用和设备端示例
```

## 4. 系统工作流程

系统可以理解成三层：

1. 调用方  
   一般是业务后端、Python 脚本，或者其他服务。它通过 HTTP 调用 R0RPC。

2. R0RPC 服务端  
   负责认证、校验分组、查找在线设备、路由请求、等待结果、记录日志和指标。

3. 设备客户端  
   设备端先登录，再通过 WebSocket 长连接保持在线。收到任务后执行动作，并把结果回传给服务端。

一次完整调用大致是：

```text
设备登录 -> 建立 WebSocket -> 调用方发起 RPC -> 服务端选择在线设备
       -> WebSocket 下发任务 -> 设备执行 action -> 服务端同步返回结果
```

调用接口形式：

```text
POST /rpc/invoke/{group}/{action}
```

如果没有指定 `clientId`，服务端会在同组在线设备里轮询分发。如果指定了 `clientId`，就只发给指定设备。

## 5. Group 使用规则

现在 `group` 不是随便填的字符串，必须先创建后使用。

推荐流程：

1. 先在管理后台创建 `group`
2. 设备登录时使用这个 `group`
3. 调用方通过 `/rpc/invoke/{group}/{action}` 发起请求
4. 需要查看在线设备时，通过 `/rpc/clientQueue?group=...` 查询

异常行为：

- `group` 不存在：返回 `group_not_found`，HTTP 状态码 `404`
- `group` 被禁用：返回 `group_disabled`，HTTP 状态码 `403`
- `group` 不存在的调用不会计入 RPC 调用统计，也不会写入正常调用记录
- `clientQueue` 查询同样要求 `group` 已存在且启用

这样可以避免任意人随便构造一个 `group` 就能发起请求，也让后台里的分组更可控。

## 6. 传输方式

当前主通道是 WebSocket。

设备侧流程：

1. `POST /api/client/login`
2. 读取返回里的 `token` 和 `wsUrl`
3. 连接 `GET /api/client/ws?token=...`
4. 周期性发送 heartbeat
5. 接收任务并回传结果

这种方式的好处是：

- 设备在线时延更低
- 空闲时 HTTP 开销更小
- 更适合大量设备常驻连接

## 7. 管理后台

默认访问：

```text
http://YOUR_SERVER_IP:9876/
```

后台可以查看和管理：

- 管理员账号
- 分组列表
- 设备列表
- 调用记录
- 统计指标
- 在线状态
- 手动 RPC 调试

默认管理账号：

```text
用户名：admin
密码：123456
```

注意：默认密码来自 `deploy/linux/.env.docker` 里的 `BOOTSTRAP_ADMIN_PASSWORD`。这个配置只在管理员账号不存在时用于初始化账号；如果账号已经存在，改配置不会覆盖已有密码。

## 8. 常用接口

### 8.1 管理员登录

接口：

```text
POST /api/auth/login
```

请求：

```json
{
  "username": "admin",
  "password": "123456"
}
```

返回里重点看：

- `token`
- `user`

### 8.2 查询 group 下的设备

接口：

```text
GET /rpc/clientQueue?group={groupName}
```

可选参数：

- `group`：必填，分组名
- `status`：可选，设备状态过滤
- `limit`：可选，返回数量上限

示例：

```bash
curl "http://127.0.0.1:9876/rpc/clientQueue?group=idlefish"
```

返回示意：

```json
{
  "group": "idlefish",
  "count": 2,
  "clientIds": ["device-a", "device-b"],
  "items": [
    {
      "clientId": "device-a",
      "group": "idlefish",
      "platform": "android",
      "status": "online",
      "lastSeenAt": "2026-04-01T16:00:00+08:00",
      "lastIp": "10.0.0.12"
    }
  ]
}
```

如果只想看在线设备，不传 `status` 即可。这个接口默认优先返回在线设备队列。

### 8.3 发起 RPC 调用

接口：

```text
POST /rpc/invoke/{group}/{action}
```

当前支持两种认证方式：

1. Header 里带 Bearer Token
2. 请求体里直接带 `username` 和 `password`
3. token会缓存，只有第一次会查询数据库，后面会缓存12小时，无论是请求体带账号信息或者先登录带token都会缓存

推荐的简单调用体：

```json
{
  "username": "admin",
  "password": "123456",
  "timeoutSeconds": 20,
  "payload": {
    "encode_str": "xxx"
  }
}
```

如果要指定设备，多传一个 `clientId`：

```json
{
  "username": "admin",
  "password": "123456",
  "clientId": "device-001",
  "timeoutSeconds": 20,
  "payload": {
    "encode_str": "xxx"
  }
}
```

字段说明：

- `username`：管理员账号
- `password`：管理员密码
- `clientId`：可选，指定某一台设备；不传就按 group 轮询在线设备
- `timeoutSeconds`：可选，请求超时时间，单位是秒；不传时走服务端默认值，当前默认是 `25` 秒
- `payload`：真正发给设备 action 的参数对象，建议直接写扁平结构，不要再多套一层 `payload`

调用示例：

```bash
curl -X POST "http://127.0.0.1:9876/rpc/invoke/idlefish/decrypt" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "admin",
    "password": "123456",
    "timeoutSeconds": 20,
    "payload": {
      "encode_str": "v7eNwdELBmc1hOkagpP6NQ=="
    }
  }'
```

### 8.4 调用返回结构

服务端返回统一结构，重点看这些字段：

- `is_ok`
- `status`
- `httpCode`
- `requestId`
- `clientId`
- `data`
- `error`

判断成功失败时，建议直接看 `is_ok`：

- `true`：本次调用成功
- `false`：本次调用失败

成功示例：

```json
{
  "is_ok": true,
  "requestId": "xxx",
  "group": "idlefish",
  "action": "decrypt",
  "clientId": "a9178e59d1d77782",
  "requestPayload": {
    "encode_str": "v7eNwdELBmc1hOkagpP6NQ=="
  },
  "status": "success",
  "httpCode": 200,
  "data": {
    "data": "解密结果"
  },
  "latencyMs": 132,
  "error": ""
}
```

超时示例：

```json
{
  "is_ok": false,
  "status": "timeout",
  "httpCode": 504,
  "requestId": "xxx",
  "group": "idlefish",
  "action": "decrypt",
  "clientId": "a9178e59d1d77782",
  "requestPayload": {
    "encode_str": "v7eNwdELBmc1hOkagpP6NQ=="
  },
  "error": "context deadline exceeded"
}
```

## 9. 设备端接入

### 9.1 Java / Xposed

相关目录：

- `clients/java/`
- `clients/xposed-demo/`

当前 Java/Xposed 的 handler 写法：

1. 用 `registerHandler("action", handler)` 注册动作
2. handler 内实现 `handleRequest(...)`
3. 请求参数推荐走扁平 `payload`
4. 需要时可用 `@AutoBind` 直接把 payload 字段绑定到成员变量

示意：

```java
relayClient.registerHandler("decrypt", new DecryptHandler());
```

```java
public class DecryptHandler implements RelayHandler {
    @AutoBind
    private String encode_str;

    @Override
    public void handleRequest(RelayRequest request, RelayResponse response) throws Exception {
        response.success(encode_str);
    }
}
```

如果 Java SDK 还是本地 jar，可以先用：

```gradle
implementation files('libs/r0rpc-relay-client.jar')
```

如果后面发布到 Maven 仓库，就可以改成类似 Sekiro 这种形式：

```gradle
implementation 'com.yourgroup:r0rpc-relay-client:版本号'
```

坐标需要以实际发布到 Maven 的 groupId、artifactId、version 为准。

### 9.2 Python

相关目录：

- `examples/python/`
- `examples/python/invoke_demo.py`
- `examples/python/test_decrypt_demo.py`

Python 侧可以作为调用方，也可以模拟设备端通过 WebSocket 接入。

## 10. Linux 部署

### 10.1 支持系统

自动安装脚本目前支持：

- Ubuntu
- Debian
- CentOS
- RHEL
- Rocky Linux
- AlmaLinux
- Oracle Linux

### 10.2 一键部署

默认最快方式：

```bash
cd deploy/linux
chmod +x quickstart.sh
./quickstart.sh
```

如果脚本是从 Windows 复制到 Linux 的，先处理换行：

```bash
cd deploy/linux/
for f in *.sh; do sed -i 's/\r$//' "$f"; done
chmod +x *.sh
bash -x ./quickstart.sh
```

这个流程会做：

1. 检查 `docker` 和 `docker compose`
2. 如果缺失则自动安装
3. 如果没有 `.env.docker`，就从 `.env.example` 自动生成
4. 按当前模式启动 MySQL、Redis、R0RPC
5. 等待依赖服务就绪
6. 自动初始化数据库
7. 启动服务端

### 10.3 默认部署模式

默认配置：

```text
MYSQL_MODE=builtin
REDIS_MODE=builtin
```

含义：

- MySQL 用本机 Docker 启动
- Redis 用本机 Docker 启动
- R0RPC 也在 Docker 中启动

也就是默认整套服务都在 Linux 机器本地拉起，最省事。

### 10.4 使用外部 MySQL / Redis

如果你已经有自己的 MySQL / Redis，只需要改 `deploy/linux/.env.docker`：

```text
MYSQL_MODE=external
REDIS_MODE=external
MYSQL_HOST=10.0.0.12
MYSQL_PORT=3306
MYSQL_USER=root
MYSQL_PASSWORD=your-password
MYSQL_DB=r0rpc
REDIS_ADDR=10.0.0.13:6379
REDIS_PASSWORD=your-password
REDIS_DB=0
```

然后执行：

```bash
cd deploy/linux
./deploy.sh
```

### 10.5 混合模式

也可以一部分内置，一部分外部。例如 MySQL 用内置，Redis 用外部：

```text
MYSQL_MODE=builtin
REDIS_MODE=external
REDIS_ADDR=10.0.0.13:6379
REDIS_PASSWORD=your-password
REDIS_DB=0
```

### 10.6 数据库初始化

不需要手工建库、建表、导入 SQL。

当前 Linux 启动链路已经自动处理：

1. 检查 MySQL 是否可连
2. 检查 Redis 是否可连
3. 自动执行 `/app/r0rpc-dbinit`
4. 自动创建数据库和表
5. 自动确保管理员账号存在
6. 然后再启动 `/app/r0rpc-server`

### 10.7 常用命令

安装 Docker 和 Compose：

```bash
cd deploy/linux
./install-docker.sh
```

部署：

```bash
cd deploy/linux
./deploy.sh
```

停止：

```bash
cd deploy/linux
./stop.sh
```

## 11. 配置文件说明

### 11.1 `.env.example` 和 `.env.docker`

`deploy/linux/.env.example` 是部署配置模板。

第一次部署时，脚本会复制一份生成：

```text
deploy/linux/.env.docker
```

真正运行时读的是 `.env.docker`。Docker 内部会把它挂载成：

```text
/app/r0rpc.conf
```

建议：

- `.env.example` 保持完整参考
- `.env.docker` 放你机器上的真实运行配置
- MySQL、Redis、心跳、掉线判断、数据保留、队列、管理员初始化都集中在 `.env.docker` 里改

### 11.2 基础信息

- `APP_NAME`：应用名称，健康检查和后台展示用
- `SERVER_ID`：服务节点 ID，多节点时方便区分是哪台服务
- `TZ`：Docker 容器时区
- `TIME_ZONE`：服务内部时间解析和展示时区
- `HTTP_ADDR`：容器内监听地址，默认 `:8080`
- `HTTP_EXPOSE_PORT`：宿主机暴露端口，默认 `9876`
- `JWT_SECRET`：JWT 签名密钥；留空时部署脚本会生成并写回 `.env.docker`

### 11.3 RPC、心跳和在线状态

- `REQUEST_TIMEOUT_SECONDS`：RPC 默认超时时间，单位秒，当前默认 `25`
- `DEVICE_OFFLINE_SECONDS`：设备多久没有心跳或消息就判定离线，单位秒，当前默认 `20`
- `DEVICE_OFFLINE_MINUTES`：旧版兼容配置，正常保持 `0`
- `HEARTBEAT_INTERVAL_SECONDS`：设备心跳间隔，当前默认 `5`
- `PRESENCE_FLUSH_SECONDS`：在线状态刷新间隔，当前默认 `5`

当前默认含义是：设备大约 `5` 秒发一次心跳，服务端超过 `20` 秒没有收到心跳或消息，就认为设备离线。

### 11.4 数据保留

- `RAW_RETENTION_DAYS`：原始 RPC 请求和响应明细保留天数，当前默认 `3`
- `AGGREGATE_RETENTION_DAYS`：日统计聚合数据保留天数，当前默认 `30`
- `RAW_REQUEST_KEEP_LATEST_PER_SCOPE`：group + action + clientId 保留条数，默认1000
也就是说，详细调用记录默认保留 3 天，日统计指标默认保留 30 天。

### 11.5 队列和并发

- `PERSIST_QUEUE_SIZE`：异步持久化队列大小
- `PERSIST_WORKERS`：持久化 worker 数量
- `CLIENT_QUEUE_SIZE`：单客户端任务队列大小
- `CLIENT_MAX_IN_FLIGHT`：单客户端最大并发处理中任务数

服务端会强制这些最小值，避免误配得太小：

```text
PERSIST_QUEUE_SIZE >= 131072
PERSIST_WORKERS >= 32
CLIENT_QUEUE_SIZE >= 2048
CLIENT_MAX_IN_FLIGHT >= 256
```

### 11.6 服务模式

- `MYSQL_MODE=builtin`：启动 Docker 内置 MySQL
- `MYSQL_MODE=external`：使用你已有的外部 MySQL
- `REDIS_MODE=builtin`：启动 Docker 内置 Redis
- `REDIS_MODE=external`：使用你已有的外部 Redis

默认是：

```text
MYSQL_MODE=builtin
REDIS_MODE=builtin
```

### 11.7 MySQL

- `MYSQL_ROOT_PASSWORD`：内置 MySQL 的 root 密码
- `MYSQL_HOST`：MySQL 地址；内置模式保持 `mysql`
- `MYSQL_PORT`：MySQL 端口，默认 `3306`
- `MYSQL_USER`：连接 MySQL 的用户名
- `MYSQL_PASSWORD`：连接 MySQL 的密码
- `MYSQL_DB`：数据库名，默认 `r0rpc`
- `MYSQL_EXPOSE_PORT`：内置 MySQL 暴露到宿主机的端口
- `MYSQL_PARAMS`：MySQL DSN 参数，包含字符集、时区和超时
- `MYSQL_MAX_OPEN_CONNS`：最大打开连接数
- `MYSQL_MAX_IDLE_CONNS`：最大空闲连接数
- `MYSQL_CONN_MAX_LIFETIME_MINUTES`：连接最大生命周期，单位分钟

当前模板里的测试密码是：

```text
MYSQL_ROOT_PASSWORD=QiLongZhuDamo!@
MYSQL_PASSWORD=QiLongZhuDamo!@
```

### 11.8 Redis

- `REDIS_ADDR`：Redis 地址；内置模式保持 `redis:6379`；留空则关闭 Redis presence key
- `REDIS_PASSWORD`：Redis 密码
- `REDIS_DB`：Redis DB 编号
- `REDIS_EXPOSE_PORT`：内置 Redis 暴露到宿主机的端口

当前模板里的测试密码是：

```text
REDIS_PASSWORD=QiLongZhuDamo!@
```

### 11.9 初始化管理员

- `BOOTSTRAP_ADMIN_USERNAME`：初始化管理员用户名，默认 `admin`
- `BOOTSTRAP_ADMIN_PASSWORD`：初始化管理员密码，默认 `123456`

这两个配置只在管理员账号不存在时生效。账号已经存在时，不会自动覆盖已有密码。

## 12. 掉线感知和数据缓存

当前默认配置下：

- 设备心跳间隔：`5` 秒
- 掉线感知：超过 `20` 秒没有心跳或消息，服务端判定离线
- 在线状态刷新：每 `5` 秒刷新一次
- RPC 明细数据：默认保留 `3` 天
- 日统计聚合数据：默认保留 `30` 天

相关配置都在 `deploy/linux/.env.docker`：

```text
HEARTBEAT_INTERVAL_SECONDS=5
DEVICE_OFFLINE_SECONDS=20
PRESENCE_FLUSH_SECONDS=5
RAW_RETENTION_DAYS=3
RAW_REQUEST_KEEP_LATEST_PER_SCOPE=100
AGGREGATE_RETENTION_DAYS=30
```

## 13. PC 端转发

Python 示例里有几个脚本可以用于 PC 端转发调试：

```text
client_websocket.py
```

理解方式：

- `client_websocket.py`：模拟设备侧，通过 WebSocket 连接 R0RPC 服务端 可以@client.register('xxx')新的方法 然后方法体里调用类似127.0.0.1:xxx的本地端口 然后返回数据 达成类似内网穿透功能



## 14. 额外说明

查看某个 group 下的设备：

```text
http://YOUR_SERVER_IP:9876/rpc/clientQueue?group=idlefish
```

如果你的测试服务器就是 `159.75.100.225`，示例就是：

```text
http://159.75.100.225:9876/rpc/clientQueue?group=idlefish
```

Python 解密测试 demo：

```text
examples/python/test_decrypt_demo.py
```

`latencyMs` 表示手机端从接收任务到返回数据的耗时，并不是完整链路耗时。

如果遇到网络问题导致 Docker 镜像拉不下来，可以参考：

```text
https://github.com/DaoCloud/public-image-mirror
```

示例 Docker 镜像加速配置：

```bash
sudo mkdir -p /etc/docker/
```

添加到 `/etc/docker/daemon.json`：

```json
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io"
  ]
}
```

重启 Docker：

```bash
sudo systemctl daemon-reload
sudo systemctl restart docker
```

## 15. 适合什么场景

R0RPC 比较适合：

- 设备在线执行远程动作
- 按 `group` 管理设备池
- 后端需要把任务实时推送到设备
- 需要后台查看在线情况、调用记录和趋势指标
- Android / Xposed / Java 设备接入
- Python 脚本快速联调调用
- 用 PC 端脚本做简化版远程转发

## 16. 建议使用顺序

第一次接触项目时，建议这样用：

1. 先看 `deploy/linux/README.md`
2. 在 Linux 上跑 `deploy/linux/quickstart.sh`
3. 打开后台确认服务正常
4. 在后台创建一个 `group`
5. 让设备使用这个 `group` 登录
6. 用 `GET /rpc/clientQueue?group=...` 看在线设备
7. 用 `POST /rpc/invoke/{group}/{action}` 发一次测试请求
8. 再根据接入方式选择 Java/Xposed 或 Python 示例

## 17. 相关文档

- Linux 部署： [deploy/linux/README.md](deploy/linux/README.md)
- Java SDK： [clients/java/README.md](clients/java/README.md)
- Xposed Demo： [clients/xposed-demo/README.md](clients/xposed-demo/README.md)
- Python 示例： [examples/python/README.md](examples/python/README.md)
