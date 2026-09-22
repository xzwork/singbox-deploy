#!/usr/bin/env bash
set -e

RAW_BASE="https://raw.githubusercontent.com/xzwork/singbox-deploy/main"
PANEL_URL="${RAW_BASE}/tp"
TARGET="/usr/local/bin/tp"

echo
echo "=============================================="
echo "        Tinyproxy 管理面板安装程序"
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

apk add --no-cache bash curl >/dev/null 2>&1 || true

mkdir -p /usr/local/bin

echo "[INFO] 下载 tp 管理面板..."

curl -fsSL "$PANEL_URL" -o "${TARGET}.tmp"

if [ ! -s "${TARGET}.tmp" ]; then
    echo "[ERROR] 下载失败或文件为空"
    rm -f "${TARGET}.tmp"
    exit 1
fi

sed -i 's/\r$//' "${TARGET}.tmp"

chmod +x "${TARGET}.tmp"

mv "${TARGET}.tmp" "$TARGET"

echo
echo "[OK] Tinyproxy 管理面板安装完成"
echo
echo "运行："
echo
echo "    tp"
echo
