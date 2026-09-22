cat > /usr/local/bin/3p <<'SCRIPT'
#!/usr/bin/env bash
set -u

# ============================================================
# 3proxy 管理面板
# 系统: Alpine Linux
# ============================================================

CONFIG_DIR="/etc/3proxy"
CONFIG_FILE="/etc/3proxy/3proxy.cfg"
STATE_FILE="/etc/3proxy/3p.conf"

# 不使用 /var/log，避免部分精简 Alpine 的 /var/log 异常
LOG_DIR="/etc/3proxy/log"
LOG_FILE="${LOG_DIR}/3proxy.log"

REPO="https://dl-cdn.alpinelinux.org/alpine/edge/testing"

DEFAULT_USER="meridian"
DEFAULT_PASS="xzw123.."
DEFAULT_HTTP_PORT="60002"
DEFAULT_SOCKS_PORT="60003"
DEFAULT_MAX_CONN="500"

# ============================================================
# 输出
# ============================================================

BLUE='\033[1;34m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

ok() {
    echo -e "${GREEN}[OK]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

err() {
    echo -e "${RED}[ERR]${NC} $*" >&2
}

pause() {
    echo
    read -r -p "按回车继续..." _
}

# ============================================================
# 基础检查
# ============================================================

check_root() {
    if [ "$(id -u)" != "0" ]; then
        err "必须使用 root 用户运行"
        exit 1
    fi
}

check_alpine() {
    if [ ! -f /etc/alpine-release ]; then
        err "此面板只支持 Alpine Linux"
        exit 1
    fi
}

is_installed() {
    command -v 3proxy >/dev/null 2>&1
}

# ============================================================
# 状态配置
# ============================================================

load_state() {

    PROXY_USER="$DEFAULT_USER"
    PROXY_PASS="$DEFAULT_PASS"
    HTTP_PORT="$DEFAULT_HTTP_PORT"
    SOCKS_PORT="$DEFAULT_SOCKS_PORT"
    MAX_CONN="$DEFAULT_MAX_CONN"

    if [ -f "$STATE_FILE" ]; then

        local value=""

        value="$(grep '^PROXY_USER=' "$STATE_FILE" 2>/dev/null | head -1 | cut -d= -f2- || true)"
        [ -n "$value" ] && PROXY_USER="$value"

        value="$(grep '^PROXY_PASS=' "$STATE_FILE" 2>/dev/null | head -1 | cut -d= -f2- || true)"
        [ -n "$value" ] && PROXY_PASS="$value"

        value="$(grep '^HTTP_PORT=' "$STATE_FILE" 2>/dev/null | head -1 | cut -d= -f2- || true)"
        [ -n "$value" ] && HTTP_PORT="$value"

        value="$(grep '^SOCKS_PORT=' "$STATE_FILE" 2>/dev/null | head -1 | cut -d= -f2- || true)"
        [ -n "$value" ] && SOCKS_PORT="$value"

        value="$(grep '^MAX_CONN=' "$STATE_FILE" 2>/dev/null | head -1 | cut -d= -f2- || true)"
        [ -n "$value" ] && MAX_CONN="$value"
    fi
}

save_state() {

    mkdir -p "$CONFIG_DIR"

    cat > "$STATE_FILE" <<EOF
PROXY_USER=${PROXY_USER}
PROXY_PASS=${PROXY_PASS}
HTTP_PORT=${HTTP_PORT}
SOCKS_PORT=${SOCKS_PORT}
MAX_CONN=${MAX_CONN}
EOF

    chmod 600 "$STATE_FILE"
}

load_state

# ============================================================
# 配置生成
# ============================================================

backup_config() {

    if [ -f "$CONFIG_FILE" ]; then

        local backup

        backup="${CONFIG_FILE}.bak.$(date +%Y%m%d_%H%M%S)"

        cp "$CONFIG_FILE" "$backup"

        info "旧配置备份至："
        echo "$backup"
    fi
}

generate_config() {

    mkdir -p "$CONFIG_DIR"
    mkdir -p "$LOG_DIR"

    chmod 700 "$LOG_DIR"

    backup_config

    cat > "$CONFIG_FILE" <<EOF
# ============================================================
# 3proxy 配置
#
# HTTP   : ${HTTP_PORT}
# SOCKS5 : ${SOCKS_PORT}
# User   : ${PROXY_USER}
# ============================================================

# DNS 缓存
nscache 1024

# 官方默认 timeout 结构
timeouts 1 5 30 60 180 1800 15 60 15 5

# 小内存机器限制并发
maxconn ${MAX_CONN}

# 日志
log ${LOG_FILE} D
rotate 3

# 用户
# CL = clear text password
users ${PROXY_USER}:CL:${PROXY_PASS}

# ============================================================
# HTTP / HTTPS
# ============================================================

auth strong
allow ${PROXY_USER}

proxy -p${HTTP_PORT} -i0.0.0.0

# 不让 ACL 污染下一个服务
flush

# ============================================================
# SOCKS5
# ============================================================

auth strong
allow ${PROXY_USER}

socks -p${SOCKS_PORT} -i0.0.0.0

flush
EOF

    chmod 600 "$CONFIG_FILE"

    save_state

    ok "配置已生成：$CONFIG_FILE"
}

# ============================================================
# 安装
# ============================================================

install_3proxy() {

    echo
    info "开始安装 3proxy..."

    apk update || {
        err "apk update 失败"
        return 1
    }

    apk add --no-cache \
        bash \
        curl \
        iproute2 \
        2>/dev/null || true

    apk add \
        --no-cache \
        --repository="$REPO" \
        3proxy \
        3proxy-openrc || {
            err "3proxy 安装失败"
            return 1
        }

    if ! command -v 3proxy >/dev/null 2>&1; then
        err "安装完成但没有找到 /usr/bin/3proxy"
        return 1
    fi

    mkdir -p "$CONFIG_DIR"
    mkdir -p "$LOG_DIR"

    generate_config

    rc-update add 3proxy default >/dev/null 2>&1 || true

    info "启动服务..."

    if ! rc-service 3proxy restart; then

        err "3proxy 服务启动失败"

        echo
        echo "========== OpenRC =========="
        cat /etc/init.d/3proxy 2>/dev/null || true

        echo
        echo "========== 配置 =========="
        cat "$CONFIG_FILE" 2>/dev/null || true

        echo
        echo "========== 日志 =========="
        tail -50 "$LOG_FILE" 2>/dev/null || true

        return 1
    fi

    sleep 1

    if rc-service 3proxy status >/dev/null 2>&1; then
        ok "3proxy 安装并启动成功"
    else
        warn "安装完成，但服务状态异常"
    fi

    show_connection
}

# ============================================================
# 更新
# ============================================================

update_3proxy() {

    if ! is_installed; then
        warn "3proxy 尚未安装"
        return
    fi

    info "当前版本："
    apk info 3proxy 2>/dev/null | head -1 || true

    backup_config

    info "更新 APK 索引..."

    apk update || {
        err "apk update 失败"
        return
    }

    info "更新 3proxy..."

    apk add \
        --upgrade \
        --repository="$REPO" \
        3proxy \
        3proxy-openrc || {
            err "更新失败"
            return
        }

    info "更新后版本："
    apk info 3proxy 2>/dev/null | head -1 || true

    rc-service 3proxy restart || {
        err "更新成功，但服务重启失败"
        return
    }

    ok "更新完成"
}

# ============================================================
# 卸载
# ============================================================

uninstall_3proxy() {

    echo
    warn "即将卸载 3proxy"

    read -r -p "确认卸载？(y/N): " answer

    case "$answer" in
        y|Y)
            ;;
        *)
            info "取消"
            return
            ;;
    esac

    rc-service 3proxy stop >/dev/null 2>&1 || true
    rc-update del 3proxy default >/dev/null 2>&1 || true

    apk del 3proxy 3proxy-openrc >/dev/null 2>&1 || true

    echo
    read -r -p "是否同时删除 /etc/3proxy 配置？(y/N): " delcfg

    case "$delcfg" in
        y|Y)
            rm -rf /etc/3proxy
            ok "程序和配置均已删除"
            ;;
        *)
            ok "程序已卸载，配置保留"
            ;;
    esac
}

# ============================================================
# 修改用户
# ============================================================

change_user() {

    load_state

    echo
    echo "当前用户名：$PROXY_USER"

    read -r -p "新用户名: " value

    if [ -z "$value" ]; then
        warn "用户名不能为空"
        return
    fi

    if echo "$value" | grep -q ':'; then
        err "用户名不能包含冒号"
        return
    fi

    PROXY_USER="$value"

    generate_config
    restart_service
}

# ============================================================
# 修改密码
# ============================================================

change_password() {

    load_state

    echo
    echo "当前密码：$PROXY_PASS"

    read -r -p "新密码: " value

    if [ -z "$value" ]; then
        warn "密码不能为空"
        return
    fi

    if echo "$value" | grep -q ':'; then
        err "当前面板不允许密码包含冒号 ':'"
        return
    fi

    PROXY_PASS="$value"

    generate_config
    restart_service
}

# ============================================================
# 修改 HTTP 端口
# ============================================================

change_http_port() {

    load_state

    echo
    echo "当前 HTTP 端口：$HTTP_PORT"

    read -r -p "新 HTTP 端口: " value

    if ! echo "$value" | grep -Eq '^[0-9]+$'; then
        err "端口必须是数字"
        return
    fi

    if [ "$value" -lt 1 ] || [ "$value" -gt 65535 ]; then
        err "端口范围必须为 1-65535"
        return
    fi

    if [ "$value" = "$SOCKS_PORT" ]; then
        err "不能和 SOCKS5 使用相同端口"
        return
    fi

    HTTP_PORT="$value"

    generate_config
    restart_service
}

# ============================================================
# 修改 SOCKS5 端口
# ============================================================

change_socks_port() {

    load_state

    echo
    echo "当前 SOCKS5 端口：$SOCKS_PORT"

    read -r -p "新 SOCKS5 端口: " value

    if ! echo "$value" | grep -Eq '^[0-9]+$'; then
        err "端口必须是数字"
        return
    fi

    if [ "$value" -lt 1 ] || [ "$value" -gt 65535 ]; then
        err "端口范围必须为 1-65535"
        return
    fi

    if [ "$value" = "$HTTP_PORT" ]; then
        err "不能和 HTTP 使用相同端口"
        return
    fi

    SOCKS_PORT="$value"

    generate_config
    restart_service
}

# ============================================================
# 最大连接数
# ============================================================

change_maxconn() {

    load_state

    echo
    echo "当前最大连接数：$MAX_CONN"

    read -r -p "新的最大连接数: " value

    if ! echo "$value" | grep -Eq '^[0-9]+$'; then
        err "必须输入数字"
        return
    fi

    MAX_CONN="$value"

    generate_config
    restart_service
}

# ============================================================
# 服务控制
# ============================================================

start_service() {

    if ! is_installed; then
        warn "尚未安装 3proxy"
        return
    fi

    rc-service 3proxy start
}

stop_service() {

    if ! is_installed; then
        warn "尚未安装 3proxy"
        return
    fi

    rc-service 3proxy stop
}

restart_service() {

    if ! is_installed; then
        warn "尚未安装 3proxy"
        return
    fi

    if rc-service 3proxy restart; then
        ok "3proxy 已重启"
    else
        err "重启失败"
        diagnose
    fi
}

show_status() {

    echo

    if ! is_installed; then
        warn "3proxy 未安装"
        return
    fi

    echo "===== 版本 ====="

    apk info 3proxy 2>/dev/null | head -1 || true

    echo
    echo "===== 服务 ====="

    rc-service 3proxy status || true

    echo
    echo "===== 进程 ====="

    ps | grep '[3]proxy' || true

    echo
    echo "===== 监听 ====="

    load_state

    ss -lntp 2>/dev/null \
        | grep -E ":(${HTTP_PORT}|${SOCKS_PORT})" \
        || true
}

# ============================================================
# 编辑配置
# ============================================================

edit_config() {

    if [ ! -f "$CONFIG_FILE" ]; then
        warn "配置文件不存在"
        return
    fi

    backup_config

    if command -v nano >/dev/null 2>&1; then
        nano "$CONFIG_FILE"
    else
        vi "$CONFIG_FILE"
    fi

    echo
    read -r -p "是否重启 3proxy 应用配置？(Y/n): " answer

    case "$answer" in
        n|N)
            ;;
        *)
            restart_service
            ;;
    esac
}

show_config() {

    echo
    echo "配置文件：$CONFIG_FILE"
    echo
    cat "$CONFIG_FILE" 2>/dev/null || warn "配置不存在"
}

# ============================================================
# 日志
# ============================================================

show_log() {

    echo

    if [ -f "$LOG_FILE" ]; then
        tail -100 "$LOG_FILE"
    else
        warn "目前没有 3proxy 日志"
    fi
}

follow_log() {

    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE"

    echo "Ctrl+C 退出日志"
    echo

    tail -f "$LOG_FILE"
}

# ============================================================
# 获取公网 IP
# ============================================================

get_public_ip() {

    local ip=""

    for url in \
        "https://api.ipify.org" \
        "https://ifconfig.me" \
        "https://icanhazip.com"
    do

        ip="$(
            curl -4 -s \
                --connect-timeout 3 \
                --max-time 5 \
                "$url" 2>/dev/null \
                | tr -d '[:space:]' \
                || true
        )"

        if echo "$ip" | grep -Eq \
            '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'
        then
            echo "$ip"
            return
        fi
    done

    echo "SERVER_IP"
}

# ============================================================
# 连接信息
# ============================================================

show_connection() {

    load_state

    local ip
    ip="$(get_public_ip)"

    echo
    echo "=================================================="
    echo "HTTP / HTTPS"
    echo "=================================================="
    echo
    echo "http://${PROXY_USER}:${PROXY_PASS}@${ip}:${HTTP_PORT}"
    echo
    echo "=================================================="
    echo "SOCKS5"
    echo "=================================================="
    echo
    echo "socks5://${PROXY_USER}:${PROXY_PASS}@${ip}:${SOCKS_PORT}"
    echo
    echo "=================================================="
}

# ============================================================
# HTTP 测试
# ============================================================

test_http() {

    load_state

    echo
    info "测试本机 HTTP Proxy..."

    curl -v \
        --connect-timeout 5 \
        --max-time 15 \
        -x "http://${PROXY_USER}:${PROXY_PASS}@127.0.0.1:${HTTP_PORT}" \
        https://api.ipify.org

    echo
}

# ============================================================
# SOCKS5 测试
# ============================================================

test_socks() {

    load_state

    echo
    info "测试本机 SOCKS5..."

    curl -v \
        --connect-timeout 5 \
        --max-time 15 \
        --socks5-hostname "127.0.0.1:${SOCKS_PORT}" \
        --proxy-user "${PROXY_USER}:${PROXY_PASS}" \
        https://api.ipify.org

    echo
}

# ============================================================
# 故障诊断
# ============================================================

diagnose() {

    echo
    echo "================ 3proxy 诊断 ================"

    echo
    echo "[1] 系统"

    cat /etc/alpine-release 2>/dev/null || true

    echo
    echo "[2] 包"

    apk info 3proxy 2>/dev/null | head -5 || true

    echo
    echo "[3] binary"

    command -v 3proxy || true

    ls -l /usr/bin/3proxy 2>/dev/null || true

    echo
    echo "[4] OpenRC"

    ls -l /etc/init.d/3proxy 2>/dev/null || true

    rc-service 3proxy status 2>&1 || true

    echo
    echo "[5] 配置"

    cat "$CONFIG_FILE" 2>/dev/null || true

    echo
    echo "[6] 进程"

    ps | grep '[3]proxy' || true

    echo
    echo "[7] 监听"

    load_state

    ss -lntp 2>/dev/null \
        | grep -E ":(${HTTP_PORT}|${SOCKS_PORT})" \
        || true

    echo
    echo "[8] 日志"

    tail -100 "$LOG_FILE" 2>/dev/null || true

    echo
    echo "==============================================="
}

# ============================================================
# 菜单
# ============================================================

show_menu() {

    clear 2>/dev/null || true

    load_state

    echo "=================================================="
    echo "              3proxy 管理面板"
    echo "=================================================="

    if is_installed; then

        VERSION="$(
            apk info 3proxy 2>/dev/null \
                | head -1 \
                || echo unknown
        )"

        echo "状态：已安装  ${VERSION}"

    else
        echo "状态：未安装"
    fi

    echo
    echo "HTTP   : ${HTTP_PORT}"
    echo "SOCKS5 : ${SOCKS_PORT}"
    echo "用户   : ${PROXY_USER}"
    echo "并发   : ${MAX_CONN}"

    echo
    echo "---------------- 安装管理 ----------------"
    echo "1)  安装 3proxy"
    echo "2)  更新 3proxy"
    echo "3)  卸载 3proxy"

    echo
    echo "---------------- 配置管理 ----------------"
    echo "4)  修改用户名"
    echo "5)  修改密码"
    echo "6)  修改 HTTP 端口"
    echo "7)  修改 SOCKS5 端口"
    echo "8)  修改最大连接数"
    echo "9)  编辑完整配置"
    echo "10) 查看完整配置"

    echo
    echo "---------------- 服务管理 ----------------"
    echo "11) 启动"
    echo "12) 停止"
    echo "13) 重启"
    echo "14) 查看状态"

    echo
    echo "---------------- 测试/信息 ---------------"
    echo "15) 查看代理地址"
    echo "16) 测试 HTTP"
    echo "17) 测试 SOCKS5"
    echo "18) 查看最近日志"
    echo "19) 实时日志"
    echo "20) 故障诊断"

    echo
    echo "0) 退出"

    echo "=================================================="
}

# ============================================================
# Main
# ============================================================

check_root
check_alpine

while true
do

    show_menu

    read -r -p "请选择: " choice

    case "${choice:-}" in

        1)
            install_3proxy
            pause
            ;;

        2)
            update_3proxy
            pause
            ;;

        3)
            uninstall_3proxy
            pause
            ;;

        4)
            change_user
            pause
            ;;

        5)
            change_password
            pause
            ;;

        6)
            change_http_port
            pause
            ;;

        7)
            change_socks_port
            pause
            ;;

        8)
            change_maxconn
            pause
            ;;

        9)
            edit_config
            pause
            ;;

        10)
            show_config
            pause
            ;;

        11)
            start_service
            pause
            ;;

        12)
            stop_service
            pause
            ;;

        13)
            restart_service
            pause
            ;;

        14)
            show_status
            pause
            ;;

        15)
            show_connection
            pause
            ;;

        16)
            test_http
            pause
            ;;

        17)
            test_socks
            pause
            ;;

        18)
            show_log
            pause
            ;;

        19)
            follow_log
            ;;

        20)
            diagnose
            pause
            ;;

        0)
            exit 0
            ;;

        *)
            warn "无效选项"
            sleep 1
            ;;
    esac

done
SCRIPT
