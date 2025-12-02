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

  echo "更新软件源并安装依赖 curl socat sqlite3..."
  apt update -y
  apt install -y curl socat sqlite3

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

  XUI_BIN=""
  for bin in "${BIN_CANDIDATES[@]}"; do
    if command -v "$bin" >/dev/null 2>&1 || [ -x "$bin" ]; then
      XUI_BIN="$bin"
      echo "找到可执行文件：$bin"
      break
    fi
  done

  if [ -z "$XUI_BIN" ]; then
    echo "未找到 x-ui 可执行文件，请手动配置。"
    return 1
  fi

  echo "设置面板端口为 $PANEL_PORT..."
  "$XUI_BIN" setting -port "$PANEL_PORT" 2>&1 || true

  echo "设置用户名和密码..."
  "$XUI_BIN" setting -username "$USERNAME" -password "$PASSWORD" 2>&1 || true

  DB_FILE="/etc/x-ui/x-ui.db"
  if [ ! -f "$DB_FILE" ]; then
    DB_FILE="/usr/local/x-ui/bin/x-ui.db"
  fi
  if [ ! -f "$DB_FILE" ]; then
    DB_FILE="/usr/local/3x-ui/bin/x-ui.db"
  fi

  if [ -f "$DB_FILE" ] && command -v sqlite3 >/dev/null 2>&1; then
    echo "通过数据库直接设置用户名和密码..."
    PASSWORD_HASH=$(echo -n "$PASSWORD" | sha256sum | awk '{print $1}')
    sqlite3 "$DB_FILE" "UPDATE users SET username = '$USERNAME', password = '$PASSWORD_HASH' WHERE id = 1;" 2>/dev/null || \
    sqlite3 "$DB_FILE" "INSERT OR REPLACE INTO users (id, username, password) VALUES (1, '$USERNAME', '$PASSWORD_HASH');" 2>/dev/null || \
    sqlite3 "$DB_FILE" "UPDATE setting SET value = '$USERNAME' WHERE key = 'username'; UPDATE setting SET value = '$PASSWORD_HASH' WHERE key = 'password';" 2>/dev/null || true
  fi

  echo "设置面板路径为根目录（固定路径）..."
  "$XUI_BIN" setting -webBasePath / 2>&1 || "$XUI_BIN" setting -webPath / 2>&1 || true

  if [ -f "$DB_FILE" ] && command -v sqlite3 >/dev/null 2>&1; then
    echo "通过数据库强制设置路径为根目录..."
    sqlite3 "$DB_FILE" "UPDATE setting SET value = '/' WHERE key = 'webBasePath';" 2>/dev/null || \
    sqlite3 "$DB_FILE" "INSERT OR REPLACE INTO setting (key, value) VALUES ('webBasePath', '/');" 2>/dev/null || true
    
    echo "验证路径设置..."
    WEB_PATH=$(sqlite3 "$DB_FILE" "SELECT value FROM setting WHERE key = 'webBasePath';" 2>/dev/null || echo "")
    if [ "$WEB_PATH" != "/" ]; then
      echo "路径设置未生效，尝试再次设置..."
      sqlite3 "$DB_FILE" "DELETE FROM setting WHERE key = 'webBasePath'; INSERT INTO setting (key, value) VALUES ('webBasePath', '/');" 2>/dev/null || true
    fi
  fi

  echo "重启 x-ui 服务以应用配置..."
  systemctl restart x-ui 2>/dev/null || service x-ui restart 2>/dev/null || "$XUI_BIN" restart 2>/dev/null || true
  sleep 3

  if [ -f "$DB_FILE" ] && command -v sqlite3 >/dev/null 2>&1; then
    echo "最终验证路径..."
    FINAL_PATH=$(sqlite3 "$DB_FILE" "SELECT value FROM setting WHERE key = 'webBasePath';" 2>/dev/null || echo "")
    if [ "$FINAL_PATH" = "/" ]; then
      echo "✓ 路径已成功设置为根目录 /"
    else
      echo "⚠ 路径可能仍为随机路径，请手动在面板设置中修改"
    fi
  fi

  echo "尝试放行 7010 端口（如启用 ufw）..."
  if command -v ufw >/dev/null 2>&1; then
    ufw allow "${PANEL_PORT}"/tcp || true
  fi

  echo "==== 安装成功 ===="
  SERVER_IP=$(curl -4s https://api.ipify.org || curl -4s https://ifconfig.me || echo "<你的公网IP>")

  echo "面板地址：http://$SERVER_IP:$PANEL_PORT/"
  echo "用户名：$USERNAME"
  echo "密  码：$PASSWORD"
  echo ""
  echo "注意：如果路径不是根目录，请运行脚本选择选项 3 重置账号，或手动在面板设置中修改路径"
}

reset_account() {
  echo "==== 重置面板账号密码 ===="
  
  BIN_CANDIDATES=(
    "3x-ui"
    "/usr/local/3x-ui/3x-ui"
    "/usr/bin/3x-ui"
    "/usr/local/x-ui/x-ui"
    "x-ui"
  )

  XUI_BIN=""
  for bin in "${BIN_CANDIDATES[@]}"; do
    if command -v "$bin" >/dev/null 2>&1 || [ -x "$bin" ]; then
      XUI_BIN="$bin"
      break
    fi
  done

  if [ -z "$XUI_BIN" ]; then
    echo "未找到 x-ui 可执行文件，请先安装面板。"
    return 1
  fi

  NEW_USERNAME="admin"
  NEW_PASSWORD="admin"
  echo "重置为：用户名=admin, 密码=admin"

  echo "尝试通过命令行设置..."
  "$XUI_BIN" setting -username "$NEW_USERNAME" -password "$NEW_PASSWORD" 2>&1 || true

  DB_FILE="/etc/x-ui/x-ui.db"
  if [ ! -f "$DB_FILE" ]; then
    DB_FILE="/usr/local/x-ui/bin/x-ui.db"
  fi
  if [ ! -f "$DB_FILE" ]; then
    DB_FILE="/usr/local/3x-ui/bin/x-ui.db"
  fi

  if [ -f "$DB_FILE" ]; then
    if ! command -v sqlite3 >/dev/null 2>&1; then
      echo "安装 sqlite3 工具..."
      apt update -y && apt install -y sqlite3 2>/dev/null || true
    fi
    
    if command -v sqlite3 >/dev/null 2>&1; then
      echo "通过数据库直接重置账号密码..."
      PASSWORD_HASH=$(echo -n "$NEW_PASSWORD" | sha256sum | awk '{print $1}')
      sqlite3 "$DB_FILE" "UPDATE users SET username = '$NEW_USERNAME', password = '$PASSWORD_HASH' WHERE id = 1;" 2>/dev/null || \
      sqlite3 "$DB_FILE" "INSERT OR REPLACE INTO users (id, username, password) VALUES (1, '$NEW_USERNAME', '$PASSWORD_HASH');" 2>/dev/null || \
      sqlite3 "$DB_FILE" "UPDATE setting SET value = '$NEW_USERNAME' WHERE key = 'username'; UPDATE setting SET value = '$PASSWORD_HASH' WHERE key = 'password';" 2>/dev/null || true
      
      echo "同时设置面板路径为根目录..."
      sqlite3 "$DB_FILE" "UPDATE setting SET value = '/' WHERE key = 'webBasePath';" 2>/dev/null || \
      sqlite3 "$DB_FILE" "INSERT OR REPLACE INTO setting (key, value) VALUES ('webBasePath', '/');" 2>/dev/null || true
    fi
  fi

  echo "重启 x-ui 服务..."
  systemctl restart x-ui 2>/dev/null || service x-ui restart 2>/dev/null || "$XUI_BIN" restart 2>/dev/null || true
  sleep 2

  echo "==== 重置完成 ===="
  SERVER_IP=$(curl -4s https://api.ipify.org || curl -4s https://ifconfig.me || echo "<你的公网IP>")
  echo "面板地址：http://$SERVER_IP:7010/"
  echo "用户名：$NEW_USERNAME"
  echo "密码：$NEW_PASSWORD"
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

echo "====== 3x-ui 管理脚本1 ======"
echo "1) 安装面板"
echo "2) 卸载面板"
echo "3) 重置账号密码"
echo "0) 退出"
read -rp "请输入选项[1/2/3/0]: " choice

case "$choice" in
  1) install_panel ;;
  2) uninstall_panel ;;
  3) reset_account ;;
  0) echo "已退出"; exit 0 ;;
  *) echo "无效选项"; exit 1 ;;
esac

