# -*- coding: utf-8 -*-
"""通知渠道专用代理 ``NOTIFICATION_PROXY_URL`` 的单元测试。

覆盖：代理值解析（配置项 / 环境变量 / 非法值）、配置项解析链路，
以及各 sender 是否真的把 ``proxies`` 传给了 ``requests.post``。
"""

import os
import unittest
from typing import Optional
from unittest import mock

from src.config import Config
from src.notification_sender.proxy_config import notification_proxies
from src.notification_sender.telegram_sender import TelegramSender
from src.notification_sender.wechat_sender import WechatSender


def _config(**overrides) -> Config:
    overrides.setdefault("stock_list", [])
    return Config(**overrides)


def _response(status_code: int, json_body: Optional[dict] = None):
    resp = mock.MagicMock()
    resp.status_code = status_code
    resp.text = "ok" if status_code == 200 else "error"
    if json_body is not None:
        resp.json.return_value = json_body
    return resp


def _clear_proxy_env():
    return mock.patch.dict(os.environ, {}, clear=False)


class TestNotificationProxies(unittest.TestCase):
    """``notification_proxies`` 的解析语义。"""

    def test_returns_none_when_unconfigured(self):
        with _clear_proxy_env():
            os.environ.pop("NOTIFICATION_PROXY_URL", None)
            self.assertIsNone(notification_proxies(_config()))

    def test_config_value_maps_to_http_and_https(self):
        with _clear_proxy_env():
            os.environ.pop("NOTIFICATION_PROXY_URL", None)
            proxies = notification_proxies(_config(notification_proxy_url="http://127.0.0.1:7897"))
        self.assertEqual(
            proxies,
            {"http": "http://127.0.0.1:7897", "https": "http://127.0.0.1:7897"},
        )

    def test_config_value_wins_over_env(self):
        cfg = _config(notification_proxy_url="http://127.0.0.1:7897")
        with mock.patch.dict(os.environ, {"NOTIFICATION_PROXY_URL": "http://127.0.0.1:1"}):
            self.assertEqual(
                notification_proxies(cfg),
                {"http": "http://127.0.0.1:7897", "https": "http://127.0.0.1:7897"},
            )

    def test_env_fallback_when_config_has_no_value(self):
        with mock.patch.dict(os.environ, {"NOTIFICATION_PROXY_URL": "http://127.0.0.1:7890"}):
            self.assertEqual(
                notification_proxies(_config()),
                {"http": "http://127.0.0.1:7890", "https": "http://127.0.0.1:7890"},
            )

    def test_blank_value_is_treated_as_unset(self):
        with _clear_proxy_env():
            os.environ.pop("NOTIFICATION_PROXY_URL", None)
            self.assertIsNone(notification_proxies(_config(notification_proxy_url="   ")))

    def test_unsupported_scheme_is_ignored(self):
        with _clear_proxy_env():
            os.environ.pop("NOTIFICATION_PROXY_URL", None)
            with self.assertLogs("src.notification_sender.proxy_config", level="WARNING"):
                proxies = notification_proxies(_config(notification_proxy_url="socks5://127.0.0.1:1080"))
        self.assertIsNone(proxies)

    def test_env_is_read_by_config_loader(self):
        with mock.patch.dict(os.environ, {"NOTIFICATION_PROXY_URL": "http://127.0.0.1:7897"}):
            self.assertEqual(
                Config._load_from_env().notification_proxy_url,
                "http://127.0.0.1:7897",
            )


class TestSenderUsesNotificationProxy(unittest.TestCase):
    """sender 必须把代理交给 ``requests.post``，未配置时保持 None。"""

    @mock.patch("src.notification_sender.telegram_sender.requests.post")
    def test_telegram_passes_proxies(self, mock_post):
        mock_post.return_value = _response(200, {"ok": True})
        cfg = _config(
            telegram_bot_token="BOT",
            telegram_chat_id="CHAT",
            notification_proxy_url="http://127.0.0.1:7897",
        )
        self.assertTrue(TelegramSender(cfg).send_to_telegram("hello"))
        self.assertEqual(
            mock_post.call_args.kwargs["proxies"],
            {"http": "http://127.0.0.1:7897", "https": "http://127.0.0.1:7897"},
        )

    @mock.patch("src.notification_sender.telegram_sender.requests.post")
    def test_telegram_without_proxy_passes_none(self, mock_post):
        mock_post.return_value = _response(200, {"ok": True})
        cfg = _config(telegram_bot_token="BOT", telegram_chat_id="CHAT")
        with _clear_proxy_env():
            os.environ.pop("NOTIFICATION_PROXY_URL", None)
            self.assertTrue(TelegramSender(cfg).send_to_telegram("hello"))
        self.assertIsNone(mock_post.call_args.kwargs["proxies"])

    @mock.patch("src.notification_sender.wechat_sender.requests.post")
    def test_wechat_passes_proxies(self, mock_post):
        mock_post.return_value = _response(200, {"errcode": 0})
        cfg = _config(
            wechat_webhook_url="https://wechat.example/hook",
            notification_proxy_url="http://127.0.0.1:7897",
        )
        self.assertTrue(WechatSender(cfg).send_to_wechat("hello"))
        self.assertEqual(
            mock_post.call_args.kwargs["proxies"],
            {"http": "http://127.0.0.1:7897", "https": "http://127.0.0.1:7897"},
        )


if __name__ == "__main__":
    unittest.main()
