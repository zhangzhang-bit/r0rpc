# config/database.py - MySQL 数据库配置
# 所有配置项均可通过 .env 覆盖，支持 Docker 内置或外部 MySQL

from . import env, env_int

DATABASES = {
    "default": {
        "ENGINE": "dj_db_conn_pool.backends.mysql",  # 连接池
        "NAME": env("MYSQL_DB", "r0rpc"),
        "USER": env("MYSQL_USER", "root"),
        "PASSWORD": env("MYSQL_PASSWORD", ""),
        "HOST": env("MYSQL_HOST", "mysql"),
        "PORT": env("MYSQL_PORT", "3306"),
        "OPTIONS": {
            "charset": "utf8mb4",
            "connect_timeout": 5,
            "read_timeout": 30,
            "write_timeout": 30,
        },
        # 连接池配置
        "POOL_OPTIONS": {
            "POOL_SIZE": env_int("MYSQL_POOL_SIZE", 256),
            "MAX_OVERFLOW": env_int("MYSQL_MAX_OVERFLOW", 64),
            "RECYCLE": env_int("MYSQL_CONN_MAX_LIFETIME_SECONDS", 600),
        },
    }
}
