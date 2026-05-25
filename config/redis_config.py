# config/redis_config.py - Redis 配置
# 所有配置项均可通过 .env 覆盖，支持 Docker 内置或外部 Redis

from . import env, env_int

REDIS_CONF = {
    "host": env("REDIS_HOST", "myredis"),
    "port": env_int("REDIS_PORT", 6379),
    "password": env("REDIS_PASSWORD", ""),
    "db": env_int("REDIS_DB", 8),
    "retry_on_timeout": True,
    "decode_responses": True,
}

# Django Channels 使用的 Redis 地址
REDIS_URL = (
    f"redis://:{REDIS_CONF['password']}@{REDIS_CONF['host']}:{REDIS_CONF['port']}/{REDIS_CONF['db']}"
    if REDIS_CONF["password"]
    else f"redis://{REDIS_CONF['host']}:{REDIS_CONF['port']}/{REDIS_CONF['db']}"
)

# Django 缓存用的 Redis
CACHES = {
    "default": {
        "BACKEND": "django_redis.cache.RedisCache",
        "LOCATION": REDIS_URL,
        "OPTIONS": {
            "CLIENT_CLASS": "django_redis.client.DefaultClient",
            "SOCKET_CONNECT_TIMEOUT": 5,
            "SOCKET_TIMEOUT": 5,
            "RETRY_ON_TIMEOUT": True,
            "CONNECTION_POOL_KWARGS": {"max_connections": 512},
        },
    }
}
