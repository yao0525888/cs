#!/usr/bin/env bash

set -e

PANEL_PORT=7010
USERNAME="admin"
PASSWORD="admin"
INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"

if [ "$(id -u)" -ne 0 ]; then
  echo "请使用 root 用户运行此脚本：sudo bash $0"
  exit 1
fi

install_panel() {
  echo "==== 3x-ui 一键安装（Debian/Ubuntu）===="
  echo "面板端口：$PANEL_PORT"
  echo "用户名/密码：$USERNAME/$PASSWORD"

  if ! command -v apt >/dev/null 2>&1; then
    echo "检测到当前系统不是基于 Debian/Ubuntu（未找到 apt），脚本退出。"
    exit 1
  fi

  echo "更新软件源并安装依赖 curl socat..."
  apt update -y
  apt install -y curl socat

  echo "下载并执行 3x-ui 官方安装脚本（自动回答端口问题为 $PANEL_PORT）..."
  printf "y\n%s\n" "$PANEL_PORT" | bash <(curl -Ls "$INSTALL_SCRIPT_URL")

  echo "尝试设置面板端口、用户名和密码..."

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

  echo "==== 安装成功 ===="
  SERVER_IP=$(curl -4s https://api.ipify.org || curl -4s https://ifconfig.me || echo "<你的公网IP>")

  echo "面板地址：http://$SERVER_IP:$PANEL_PORT"
  echo "用户名：$USERNAME"
  echo "密  码：$PASSWORD"
}

uninstall_panel() {
  echo "==== 卸载 3x-ui 面板 ===="

  if command -v x-ui >/dev/null 2>&1; then
    x-ui uninstall
  elif command -v 3x-ui >/dev/null 2>&1; then
    3x-ui uninstall
  elif [ -x /usr/local/x-ui/x-ui ]; then
    /usr/local/x-ui/x-ui uninstall
  elif [ -x /usr/local/3x-ui/3x-ui ]; then
    /usr/local/3x-ui/3x-ui uninstall
  else
    echo "未找到 x-ui / 3x-ui 可执行文件，可能尚未安装。"
  fi
}

echo "====== 3x-ui 管理脚本 ======"
echo "1) 安装面板"
echo "2) 卸载面板"
echo "0) 退出"
read -rp "请输入选项[1/2/0]: " choice

case "$choice" in
  1) install_panel ;;
  2) uninstall_panel ;;
  0) echo "已退出"; exit 0 ;;
  *) echo "无效选项"; exit 1 ;;
esac

