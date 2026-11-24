# -*- coding: utf-8 -*-
"""通知渠道专用 HTTP 代理。

``USE_PROXY`` 通过进程级 ``http_proxy`` / ``https_proxy`` 让**所有**出站请求走代理，
行情数据源会被一并代理掉。部分部署只想让推送走代理（例如只为了访问 Telegram
而挂本地代理）、行情保持直连，因此单独的 ``NOTIFICATION_PROXY_URL`` 只作用在
通知渠道的 ``requests`` 调用上，不修改环境变量，也不影响数据源。

取值优先级：``Config.notification_proxy_url`` → 环境变量 ``NOTIFICATION_PROXY_URL``。
留空表示不覆盖，通知请求保持 ``requests`` 默认行为。
"""

import logging
import os
from typing import Any, Dict, Optional
from urllib.parse import urlparse

logger = logging.getLogger(__name__)

NOTIFICATION_PROXY_ENV = "NOTIFICATION_PROXY_URL"

# requests 的 HTTP(S) 代理；SOCKS 需要额外安装 PySocks，不在支持范围内。
_SUPPORTED_PROXY_SCHEMES = ("http", "https")


def _normalize_proxy_url(raw: Optional[str]) -> Optional[str]:
    value = (raw or "").strip()
    if not value:
        return None
    parsed = urlparse(value)
    if parsed.scheme.lower() not in _SUPPORTED_PROXY_SCHEMES or not parsed.netloc:
        logger.warning(
            "%s 只支持 http/https 代理地址，已忽略: %s",
            NOTIFICATION_PROXY_ENV,
            value,
        )
        return None
    return value


def notification_proxies(config: Any = None) -> Optional[Dict[str, str]]:
    """返回可直接传给 ``requests`` 的 ``proxies`` 参数；未配置时返回 ``None``。

    Args:
        config: 全局配置对象；为 ``None`` 或未配置该字段时回退到环境变量。
    """
    raw = getattr(config, "notification_proxy_url", None) if config is not None else None
    if not (raw or "").strip():
        raw = os.getenv(NOTIFICATION_PROXY_ENV, "")

    proxy_url = _normalize_proxy_url(raw)
    if proxy_url is None:
        return None
    return {"http": proxy_url, "https": proxy_url}
