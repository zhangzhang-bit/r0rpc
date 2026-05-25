# Linux One-Click Deploy

This directory supports one-click deployment for these modes:

- default: local Docker MySQL + local Docker Redis + R0RPC
- mixed: local Docker MySQL/Redis plus external service on either side
- external: your existing MySQL + your existing Redis + R0RPC

## Supported Systems

Automatic Docker installation script currently supports:

- Ubuntu
- Debian
- CentOS
- RHEL
- Rocky Linux
- AlmaLinux
- Oracle Linux
- OpenCloudOS

For RPM-based systems, the installer tries the official Docker repository first and automatically falls back to an Aliyun mirror when the official source is unreachable.

## Fastest Start

Default behavior is local MySQL and local Redis inside Docker on the same machine.

```bash
cd deploy/linux
chmod +x quickstart.sh
./quickstart.sh
```

What it does:

1. installs Docker and Docker Compose if missing
2. creates `.env.docker` from template if missing
3. starts MySQL, Redis, and R0RPC by Docker Compose
4. waits for dependencies
5. automatically runs database initialization
6. starts the server

## Config Switches

All deployment config is centralized in:

- template: `.env.example`
- active config: `.env.docker`

`quickstart.sh` and `deploy.sh` create `.env.docker` from `.env.example` when it does not exist.
Edit `.env.docker` before starting if you want to change passwords, retention, heartbeat, queues, or external MySQL/Redis.

The most commonly tuned values are:

```text
DEVICE_OFFLINE_SECONDS=20
HEARTBEAT_INTERVAL_SECONDS=5
PRESENCE_FLUSH_SECONDS=5
RAW_RETENTION_DAYS=3
RAW_REQUEST_KEEP_LATEST_PER_SCOPE=100
AGGREGATE_RETENTION_DAYS=30
REQUEST_TIMEOUT_SECONDS=25
```

Edit these switches if you want to use your own database or Redis.

```text
MYSQL_MODE=builtin
REDIS_MODE=builtin
```

Allowed values:

- `builtin`: start service in local Docker
- `external`: use your existing service

## External Service Example

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

Then run:

```bash
./deploy.sh
```

## Database Initialization

You do not need to create the database or tables manually.

Container startup automatically:

1. checks MySQL connectivity
2. checks Redis connectivity when configured
3. runs `/app/r0rpc-dbinit`
4. starts `/app/r0rpc-server`

## Manual Commands

Install Docker and Docker Compose only:

```bash
./install-docker.sh
```

Deploy with current config:

```bash
./deploy.sh
```

Stop services:

```bash
./stop.sh
```

## After Startup

- management UI: `http://YOUR_SERVER_IP:9876/`
- health check: `http://YOUR_SERVER_IP:9876/healthz`
- bootstrap admin: `BOOTSTRAP_ADMIN_USERNAME / BOOTSTRAP_ADMIN_PASSWORD` from `.env.docker`
