#!/usr/bin/env bash
# 3x-ui 一键安装脚本（Debian/Ubuntu）
# 默认：面板端口 7010，用户名/密码：admin

set -e

PANEL_PORT=7010
USERNAME="admin"
PASSWORD="admin"
INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"

# 必须 root 运行
if [ "$(id -u)" -ne 0 ]; then
  echo "请使用 root 用户运行此脚本：sudo bash $0"
  exit 1
fi

echo "==== 3x-ui 一键安装开始（Debian/Ubuntu）===="
echo "面板端口：$PANEL_PORT"
echo "用户名/密码：$USERNAME/$PASSWORD"

if ! command -v apt >/dev/null 2>&1; then
  echo "检测到当前系统不是基于 Debian/Ubuntu（未找到 apt），脚本退出。"
  exit 1
fi

echo "更新软件源并安装依赖 curl socat..."
apt update -y
apt install -y curl socat

echo "下载并执行 3x-ui 官方安装脚本..."
bash <(curl -Ls "$INSTALL_SCRIPT_URL")

echo "尝试设置面板端口、用户名和密码..."

# 常见可执行文件路径（不同版本可能略有差异）
BIN_CANDIDATES=(
  "3x-ui"
  "/usr/local/3x-ui/3x-ui"
  "/usr/bin/3x-ui"
  "/usr/local/x-ui/x-ui"
  "x-ui"
)

SET_OK=0
for bin in "${BIN_CANDIDATES[@]}"; do
  if command -v "$bin" >/dev/null 2>&1 || [ -x "$bin" ]; then
    echo "使用可执行文件：$bin"
    "$bin" setting -port "$PANEL_PORT" -username "$USERNAME" -password "$PASSWORD" >/dev/null 2>&1 && SET_OK=1 && break
  fi
done

if [ "$SET_OK" -ne 1 ]; then
  echo "未能通过命令行自动设置端口/用户名/密码，请安装完成后在面板中手动修改。"
fi

echo "尝试放行 7010 端口（如启用 ufw）..."
if command -v ufw >/dev/null 2>&1; then
  ufw allow "${PANEL_PORT}"/tcp || true
fi

echo "==== 安装流程结束 ===="
echo "如无意外，请访问：  http://<你的服务器IP>:$PANEL_PORT"
echo "用户名：$USERNAME"
echo "密  码：$PASSWORD"


