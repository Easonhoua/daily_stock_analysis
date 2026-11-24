# 服务器生产部署包

把项目部署到一台公网云服务器，带 HTTPS 和登录密码保护。整套流程只需要在服务器上跑一条命令。

| 文件 | 用途 |
|---|---|
| `setup-server.sh` | 一键部署脚本：装 Docker → 配防火墙 → 准备目录和 `.env` → 装 Caddy 配 HTTPS → 启动容器 → 健康检查 |
| `docker-compose.yml` | 生产 Compose：用官方镜像、默认只绑 `127.0.0.1`、内存/日志限额 |
| `.env.prod.example` | 生产 `.env` 模板（脚本会自动复制成 `/opt/dsa/.env`） |
| `Caddyfile` | Caddy 反代模板（自动 HTTPS，已配好 SSE 不缓冲） |
| `nginx.conf` | 想用 Nginx 时的等价配置（含 WebSocket / SSE 关键项） |

## 前提条件（只有你能做）

1. **一台 Ubuntu 22.04/24.04 云服务器**，建议 2 核 2G 起。
2. **云厂商控制台的安全组放行** `22`、`80`、`443`（无域名模式临时再放 `8000`）。
3. **（有域名时）域名 A 记录指向服务器公网 IP**，并且已备案（国内服务器 80/443 对外服务需要 ICP 备案）。
4. 能 SSH 登录服务器（root 或带 sudo 的账号）。

## 方式一：有域名（推荐，自动 HTTPS）

本机（Windows PowerShell，在项目根目录）上传部署包：

```powershell
scp -r docker\prod root@<服务器IP>:/tmp/dsa-deploy
```

登录服务器并执行：

```bash
ssh root@<服务器IP>
bash /tmp/dsa-deploy/setup-server.sh --domain stock.example.com
```

脚本结束后访问 `https://stock.example.com`，第一次打开会让你**设置管理员密码**。

顺手把必填项一起写进去（可选）：

```bash
bash /tmp/dsa-deploy/setup-server.sh \
  --domain stock.example.com \
  --stock-list "600519,300750,002594" \
  --llm-key "sk-你的DeepSeekKey"
```

## 方式二：暂时没域名（IP + 端口）

```bash
bash /tmp/dsa-deploy/setup-server.sh --public
```

访问 `http://<服务器IP>:8000`。这是临时形态：8000 对公网开放、没有 HTTPS。
配好域名和备案后，重跑一次 `--domain` 版本即可切换为「只绑本机 + HTTPS 反代」。

## 部署后必做

```bash
# 1. 补齐配置（密钥、自选股、推送、定时）
sudo vim /opt/dsa/.env

# 2. 应用配置
cd /opt/dsa && sudo docker compose up -d

# 3. 打开网页设置管理员密码
```

## 常用运维命令

```bash
cd /opt/dsa

docker compose ps                      # 状态
docker compose logs -f --tail=100      # 日志
docker compose restart                 # 重启
docker compose pull && docker compose up -d    # 升级到最新镜像

# 改管理员密码（忘记密码时）
docker compose exec -u dsa stock-server python -m src.auth reset_password

# 手动跑一次分析
docker compose exec -u dsa stock-server python main.py --stocks 600519 --no-notify

# 备份（数据 + 配置 + 报告）
sudo tar -czf /root/dsa-backup-$(date +%F).tar.gz -C /opt/dsa .env data reports
```

## 配置优先级（容易踩坑）

- `/opt/dsa/.env` 会作为**启动环境变量**注入容器，优先级**高于** Web 设置页保存到 `/app/data/runtime.env` 的值。
- 所以同一个键不要两边都配：**固定配置写 `.env`，临时调整用 Web 设置页**。
- 在 Web 里改了 `.env` 中也存在的键，重启容器后会变回 `.env` 的值；想持久化就改 `.env` 再 `docker compose up -d`。

## 常见问题

| 现象 | 原因 | 处理 |
|---|---|---|
| 浏览器打不开 | 云安全组没放行 80/443 | 控制台补入站规则 |
| 容器正常但网页超时 | 反代在缓冲 SSE | Caddy 需 `flush_interval -1`；Nginx 需 `proxy_buffering off` |
| HTTPS 证书签发失败 | DNS 未指向本机 / 80 端口被占 / 未备案 | 脚本会打印解析结果，按提示修 DNS 与安全组 |
| 分析进度条不动 | 同「缓冲 SSE」；或容器内存不足被杀 | 看 `docker compose logs`，必要时调高 `DSA_MEMORY_LIMIT` |
| 每天收到两份报告 | 同时跑 `analyzer` 容器和 `SCHEDULE_ENABLED=true` | 只保留一个调度入口 |
| Telegram 推送失败 | 国内服务器访问不到 `api.telegram.org` | 换国内渠道，或配代理后设 `NOTIFICATION_PROXY_URL` |
| 登录后很快掉线 | 反代没传 `X-Forwarded-Proto` | 用包内的 Caddyfile / nginx.conf，别自己删这几行 |
| Web 改了配置重启就丢 | 启动环境变量覆盖 | 见上面「配置优先级」 |

## 香港 / 海外服务器（免备案）最短路径

不涉及 ICP 备案，域名随绑随用，适合自用或小范围分享。步骤就是「买机器 → 解析域名 → 放行端口 → 跑脚本」：

```bash
# 1) 买 2C2G / Ubuntu 22.04 的香港或新加坡轻量服务器，记下公网 IP
# 2) 域名 A 记录指向该 IP（用 Cloudflare 时先设 DNS only / 灰云）
# 3) 云控制台安全组放行 22 / 80 / 443
# 4) 本机上传并执行
scp -r docker/prod root@<服务器IP>:/tmp/dsa-deploy
ssh root@<服务器IP> "bash /tmp/dsa-deploy/setup-server.sh --domain stock.example.com"
```

和国内服务器相比只有两点差异：

- **香港节点通常能直连 `api.telegram.org`**，`TELEGRAM_*` 配好即可推送，不需要 `NOTIFICATION_PROXY_URL`。
- **国内行情源（东财 / 腾讯 / 新浪）从香港访问可能偏慢或被限流**；项目会自动降级到 Baostock 等可用源，若发现数据字段缺失较多，可补 `TUSHARE_TOKEN`（免费档够日线）。

Cloudflare 注意：橙色云（代理）开启后 Caddy 的 HTTP-01 证书签发会失败，**签发阶段必须先设灰云（DNS only）**，拿到证书后再决定是否开代理。

## 用 Nginx 代替 Caddy

脚本默认装 Caddy。想用 Nginx：

```bash
sudo apt install -y nginx certbot python3-certbot-nginx
sudo cp /tmp/dsa-deploy/nginx.conf /etc/nginx/sites-available/dsa
sudo sed -i "s/your-domain.com/stock.example.com/g" /etc/nginx/sites-available/dsa
sudo ln -sf /etc/nginx/sites-available/dsa /etc/nginx/sites-enabled/dsa
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d stock.example.com
```

然后确认 `/opt/dsa/.env` 里是 `BIND_ADDR=127.0.0.1`、`TRUST_X_FORWARDED_FOR=true`，最后 `cd /opt/dsa && docker compose up -d`。
