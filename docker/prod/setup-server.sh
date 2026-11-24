#!/usr/bin/env bash
# ==========================================================
# 股票智能分析系统 - 服务器一键部署（Ubuntu 22.04 / 24.04）
#
# 用法：
#   有域名（推荐，自动 HTTPS）：
#     sudo bash setup-server.sh --domain stock.example.com
#
#   没域名（先用 IP:8000 访问，临时调试）：
#     sudo bash setup-server.sh --public
#
#   可选参数：
#     --stock-list "600519,300750"   同时写入自选股
#     --llm-key "sk-xxxx"            同时写入 DEEPSEEK_API_KEY
#     --dir /opt/dsa                 安装目录（默认 /opt/dsa）
#
# 脚本做的事：装 Docker/Compose → 配防火墙 → 准备目录和 .env →
#             （可选）装 Caddy 并配 HTTPS 反代 → 启动容器 → 健康检查
# 可重复执行：已存在的 .env 不会被覆盖，容器会就地更新。
# ==========================================================
set -euo pipefail

APP_DIR="/opt/dsa"
DOMAIN=""
PUBLIC_MODE=0
STOCK_LIST_ARG=""
LLM_KEY_ARG=""

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
blue()  { printf '\033[36m%s\033[0m\n' "$*"; }
die()   { red "错误: $*"; exit 1; }

usage() {
    sed -n '3,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain)     DOMAIN="${2:-}"; shift 2 ;;
        --public)     PUBLIC_MODE=1; shift ;;
        --stock-list) STOCK_LIST_ARG="${2:-}"; shift 2 ;;
        --llm-key)    LLM_KEY_ARG="${2:-}"; shift 2 ;;
        --dir)        APP_DIR="${2:-}"; shift 2 ;;
        -h|--help)    usage; exit 0 ;;
        *)            die "未知参数: $1（用 --help 查看用法）" ;;
    esac
done

[[ $EUID -eq 0 ]] || die "请用 root 执行：sudo bash setup-server.sh ..."
command -v apt-get >/dev/null || die "该脚本只支持 Debian/Ubuntu 系"

if [[ -n "$DOMAIN" && "$PUBLIC_MODE" -eq 1 ]]; then
    die "--domain 与 --public 只能选一个"
fi

# 把 KEY=VALUE 写进 .env（已存在则覆盖该行，不存在则追加）
set_env() {
    local key="$1" value="$2" file="$3"
    local escaped="${value//&/\\&}"
    escaped="${escaped//|/\\|}"
    if grep -qE "^[[:space:]]*#?[[:space:]]*${key}=" "$file"; then
        sed -i -E "s|^[[:space:]]*#?[[:space:]]*${key}=.*|${key}=${escaped}|" "$file"
    else
        printf '%s=%s\n' "$key" "$value" >> "$file"
    fi
}

blue "==> 1/6 安装基础依赖"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl git ufw >/dev/null

blue "==> 2/6 安装 Docker"
if ! command -v docker >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com | sh >/dev/null
    systemctl enable --now docker
fi
if ! docker compose version >/dev/null 2>&1; then
    apt-get install -y -qq docker-compose-plugin >/dev/null 2>&1 \
        || curl -fsSL https://get.docker.com | sh >/dev/null
fi
docker compose version >/dev/null 2>&1 || die "Docker Compose 插件安装失败，请手动安装 docker-compose-plugin"
green "    docker $(docker --version | awk '{print $3}' | tr -d ,) / compose $(docker compose version --short)"

blue "==> 3/6 配置防火墙"
ufw allow 22/tcp  >/dev/null
ufw allow 80/tcp  >/dev/null
ufw allow 443/tcp >/dev/null
if [[ "$PUBLIC_MODE" -eq 1 ]]; then
    ufw allow 8000/tcp >/dev/null
fi
ufw --force enable >/dev/null
green "    已放行 22/80/443$([[ "$PUBLIC_MODE" -eq 1 ]] && echo ' 和 8000')"

blue "==> 4/6 准备目录与配置"
mkdir -p "$APP_DIR"/{data,logs,reports}
cp -f "$SRC_DIR/docker-compose.yml" "$APP_DIR/docker-compose.yml"
[[ -f "$APP_DIR/.env" ]] || cp "$SRC_DIR/.env.prod.example" "$APP_DIR/.env"
ENV_FILE="$APP_DIR/.env"
chmod 600 "$ENV_FILE"

if [[ -n "$DOMAIN" ]]; then
    set_env BIND_ADDR "127.0.0.1" "$ENV_FILE"
    set_env TRUST_X_FORWARDED_FOR "true" "$ENV_FILE"
else
    set_env BIND_ADDR "0.0.0.0" "$ENV_FILE"
    set_env TRUST_X_FORWARDED_FOR "false" "$ENV_FILE"
fi
set_env ADMIN_AUTH_ENABLED "true" "$ENV_FILE"
[[ -n "$STOCK_LIST_ARG" ]] && set_env STOCK_LIST "$STOCK_LIST_ARG" "$ENV_FILE"
[[ -n "$LLM_KEY_ARG" ]] && set_env DEEPSEEK_API_KEY "$LLM_KEY_ARG" "$ENV_FILE"
green "    配置目录: $APP_DIR"

blue "==> 5/6 反向代理 / HTTPS"
if [[ -n "$DOMAIN" ]]; then
    # DNS 预检（不阻断，只告警）
    server_ip="$(curl -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)"
    resolved="$(getent hosts "$DOMAIN" | awk '{print $1}' | head -n1 || true)"
    if [[ -n "$server_ip" && -n "$resolved" && "$server_ip" != "$resolved" ]]; then
        red "    [警告] $DOMAIN 解析到 $resolved，本机公网 IP 是 $server_ip"
        red "           请确认 A 记录已指向该服务器，否则 HTTPS 证书签发会失败"
    fi

    if ! command -v caddy >/dev/null 2>&1; then
        (apt-get install -y -qq caddy >/dev/null 2>&1) \
            || { apt-get install -y -qq software-properties-common >/dev/null; add-apt-repository -y universe >/dev/null; apt-get update -qq; apt-get install -y -qq caddy >/dev/null; } \
            || die "Caddy 安装失败，可改用 docker/prod/nginx.conf + certbot（见 README）"
    fi
    sed "s/your-domain.com/${DOMAIN}/g" "$SRC_DIR/Caddyfile" > /etc/caddy/Caddyfile
    caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1 || die "Caddyfile 校验失败"
    systemctl enable --now caddy >/dev/null 2>&1 || true
    systemctl reload caddy 2>/dev/null || systemctl restart caddy
    green "    Caddy 已配置: https://${DOMAIN} -> 127.0.0.1:8000"
else
    green "    跳过反代：将直接通过 http://<服务器IP>:8000 访问"
fi

blue "==> 6/6 启动容器"
cd "$APP_DIR"
docker compose --env-file .env up -d

printf '    等待服务就绪'
for _ in $(seq 1 30); do
    if curl -fsS --max-time 3 http://127.0.0.1:8000/api/health >/dev/null 2>&1; then
        printf '\n'
        green "    服务健康检查通过"
        break
    fi
    printf '.'
    sleep 2
done

if ! curl -fsS --max-time 3 http://127.0.0.1:8000/api/health >/dev/null 2>&1; then
    red "    健康检查未通过，最近日志："
    docker compose logs --tail=40 server || true
    exit 1
fi

echo
green "================ 部署完成 ================"
if [[ -n "$DOMAIN" ]]; then
    echo "  访问地址 : https://${DOMAIN}"
else
    echo "  访问地址 : http://<服务器公网IP>:8000"
    echo "  提示     : 临时模式对公网开放 8000，配好域名后请重跑带 --domain 的脚本"
fi
echo "  配置目录 : ${APP_DIR}"
echo "  配置文件 : ${ENV_FILE}"
echo
echo "  下一步（必须）："
echo "    1. 云厂商控制台安全组放行 22/80/443$([[ "$PUBLIC_MODE" -eq 1 ]] && echo '/8000')"
echo "    2. 编辑配置并重启："
echo "         sudo vim ${ENV_FILE}      # 填 STOCK_LIST / DEEPSEEK_API_KEY 等"
echo "         cd ${APP_DIR} && sudo docker compose up -d"
echo "    3. 打开网页，第一次访问会要求设置管理员密码"
echo
echo "  常用命令："
echo "    查看状态 : cd ${APP_DIR} && docker compose ps"
echo "    查看日志 : cd ${APP_DIR} && docker compose logs -f --tail=100"
echo "    重启     : cd ${APP_DIR} && docker compose restart"
echo "    改密码   : cd ${APP_DIR} && docker compose exec -u dsa stock-server python -m src.auth reset_password"
echo "=========================================="
