# config/__init__.py
import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent


def load_env():
    """加载 .env 文件到环境变量"""
    env_file = BASE_DIR / ".env"
    if not env_file.exists():
        return
    with open(env_file, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip().strip("'\"")
            if key and key not in os.environ:
                os.environ[key] = value


def env(key, default=""):
    return os.environ.get(key, default)


def env_int(key, default=0):
    try:
        return int(os.environ.get(key, str(default)))
    except (ValueError, TypeError):
        return default


def env_bool(key, default=False):
    val = os.environ.get(key, "")
    return val.lower() in ("1", "true", "yes", "on")


# 加载环境变量
load_env()
