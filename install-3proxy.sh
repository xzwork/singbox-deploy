#!/usr/bin/env bash
set -e

RAW_BASE="https://raw.githubusercontent.com/xzwork/singbox-deploy/main"
PANEL_URL="${RAW_BASE}/3p"
TARGET="/usr/local/bin/3p"

echo
echo "=============================================="
echo "        3proxy 管理面板安装程序"
echo "=============================================="
echo

if [ "$(id -u)" != "0" ]; then
    echo "[ERROR] 请使用 root 用户运行"
    exit 1
fi

if [ ! -f /etc/alpine-release ]; then
    echo "[ERROR] 当前脚本仅支持 Alpine Linux"
    exit 1
fi

echo "[INFO] Alpine: $(cat /etc/alpine-release)"

# 确保 curl/bash 存在
apk add --no-cache bash curl >/dev/null 2>&1 || true

echo "[INFO] 正在下载 3p 管理面板..."

mkdir -p /usr/local/bin

curl -fsSL "$PANEL_URL" -o "${TARGET}.tmp"

if [ ! -s "${TARGET}.tmp" ]; then
    echo "[ERROR] 下载失败或文件为空"
    rm -f "${TARGET}.tmp"
    exit 1
fi

# 简单检查，防止下载到了 HTML / 404 页面
if ! head -1 "${TARGET}.tmp" | grep -q "bash"; then
    echo "[ERROR] 下载到的文件看起来不是 Bash 脚本"
    rm -f "${TARGET}.tmp"
    exit 1
fi

# 去除可能的 Windows CRLF
sed -i 's/\r$//' "${TARGET}.tmp"

chmod +x "${TARGET}.tmp"
mv "${TARGET}.tmp" "$TARGET"

echo
echo "[OK] 3proxy 管理面板安装完成"
echo
echo "以后直接执行："
echo
echo "    3p"
echo
echo "=============================================="
