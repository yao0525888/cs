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
  SET_PASS_RESULT=$("$XUI_BIN" setting -username "$USERNAME" -password "$PASSWORD" 2>&1)
  echo "$SET_PASS_RESULT"
  
  DB_FILE="/etc/x-ui/x-ui.db"
  if [ ! -f "$DB_FILE" ]; then
    DB_FILE="/usr/local/x-ui/bin/x-ui.db"
  fi
  if [ ! -f "$DB_FILE" ]; then
    DB_FILE="/usr/local/3x-ui/bin/x-ui.db"
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

  echo "通过命令行设置账号密码..."
  SET_RESULT=$("$XUI_BIN" setting -username "$NEW_USERNAME" -password "$NEW_PASSWORD" 2>&1)
  echo "$SET_RESULT"

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
      echo "设置面板路径为根目录..."
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

install_ssl() {
  echo "==== 配置 SSL 证书 ===="
  
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

  echo "1) 生成自签名证书（无需域名，浏览器会显示警告但连接加密）"
  echo "2) 使用已有证书文件"
  read -rp "请选择 [1/2，默认: 1]: " ssl_choice
  ssl_choice=${ssl_choice:-1}

  if [ "$ssl_choice" = "1" ]; then
    echo "生成自签名证书（无需域名）..."
    
    if ! command -v openssl >/dev/null 2>&1; then
      echo "安装 openssl..."
      apt update -y && apt install -y openssl || {
        echo "openssl 安装失败"
        return 1
      }
    fi

    SERVER_IP=$(curl -4s https://api.ipify.org || curl -4s https://ifconfig.me || echo "127.0.0.1")
    CERT_DIR="/usr/local/x-ui/cert"
    mkdir -p "$CERT_DIR" 2>/dev/null || CERT_DIR="/root/cert" && mkdir -p "$CERT_DIR"
    
    CERT_FILE="$CERT_DIR/cert.pem"
    KEY_FILE="$CERT_DIR/key.pem"

    echo "正在生成自签名证书（有效期 99999 天，约 274 年）..."
    openssl req -x509 -nodes -days 99999 -newkey rsa:2048 \
      -keyout "$KEY_FILE" \
      -out "$CERT_FILE" \
      -subj "/C=CN/ST=State/L=City/O=Organization/CN=$SERVER_IP" \
      -addext "subjectAltName=IP:$SERVER_IP" 2>/dev/null || {
      openssl req -x509 -nodes -days 99999 -newkey rsa:2048 \
        -keyout "$KEY_FILE" \
        -out "$CERT_FILE" \
        -subj "/C=CN/ST=State/L=City/O=Organization/CN=$SERVER_IP" 2>/dev/null || {
        echo "证书生成失败"
        return 1
      }
    }

    if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
      echo "证书生成成功！"
      echo "证书文件：$CERT_FILE"
      echo "私钥文件：$KEY_FILE"
    else
      echo "证书文件未找到"
      return 1
    fi
  else
    read -rp "请输入证书文件路径（.pem 或 .crt）: " CERT_FILE
    read -rp "请输入私钥文件路径（.key）: " KEY_FILE
    
    if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
      echo "证书文件或私钥文件不存在"
      return 1
    fi
  fi

  echo "配置 SSL 证书到 x-ui 面板..."
  "$XUI_BIN" setting -certFile "$CERT_FILE" -keyFile "$KEY_FILE" 2>&1 || \
  "$XUI_BIN" setting -cert "$CERT_FILE" -key "$KEY_FILE" 2>&1 || true

  echo "重启 x-ui 服务..."
  systemctl restart x-ui 2>/dev/null || service x-ui restart 2>/dev/null || "$XUI_BIN" restart 2>/dev/null || true
  sleep 2

  echo "==== SSL 配置完成 ===="
  SERVER_IP=$(curl -4s https://api.ipify.org || curl -4s https://ifconfig.me || echo "<你的公网IP>")
  echo "请访问：https://$SERVER_IP:$PANEL_PORT/"
  echo "注意：自签名证书浏览器会显示安全警告，点击'高级'->'继续访问'即可"
  echo "（连接仍然是加密的，只是证书未经过 CA 认证）"
}

download_cert() {
  echo "==== 下载 SSL 证书 ===="
  
  CERT_PATHS=(
    "/usr/local/x-ui/cert/cert.pem"
    "/root/cert/cert.pem"
    "/usr/local/3x-ui/cert/cert.pem"
    "/etc/x-ui/cert.pem"
  )
  
  KEY_PATHS=(
    "/usr/local/x-ui/cert/key.pem"
    "/root/cert/key.pem"
    "/usr/local/3x-ui/cert/key.pem"
    "/etc/x-ui/key.pem"
  )

  CERT_FILE=""
  KEY_FILE=""

  for cert in "${CERT_PATHS[@]}"; do
    if [ -f "$cert" ]; then
      CERT_FILE="$cert"
      break
    fi
  done

  for key in "${KEY_PATHS[@]}"; do
    if [ -f "$key" ]; then
      KEY_FILE="$key"
      break
    fi
  done

  if [ -z "$CERT_FILE" ] || [ -z "$KEY_FILE" ]; then
    echo "未找到证书文件，请先配置 SSL 证书（选项 4）"
    return 1
  fi

  echo "找到证书文件："
  echo "证书：$CERT_FILE"
  echo "私钥：$KEY_FILE"
  echo ""

  if command -v openssl >/dev/null 2>&1; then
    echo "证书信息："
    openssl x509 -in "$CERT_FILE" -noout -subject -issuer -dates 2>/dev/null || true
    echo ""
  fi

  SERVER_IP=$(curl -4s https://api.ipify.org || curl -4s https://ifconfig.me || hostname -I | awk '{print $1}')
  
  echo "==== 下载方式 ===="
  echo ""
  echo "方式 1：使用 SCP 下载（推荐）"
  echo "在本地电脑执行以下命令："
  echo "  scp root@$SERVER_IP:$CERT_FILE ./cert.pem"
  echo "  scp root@$SERVER_IP:$KEY_FILE ./key.pem"
  echo ""
  echo "方式 2：使用 SFTP 客户端（如 FileZilla、WinSCP）"
  echo "  服务器地址：$SERVER_IP"
  echo "  用户名：root"
  echo "  证书路径：$CERT_FILE"
  echo "  私钥路径：$KEY_FILE"
  echo ""
  echo "方式 3：直接查看文件内容（复制后保存为文件）"
  echo ""
  read -rp "是否显示证书文件内容？[y/N]: " show_content
  if [ "$show_content" = "y" ] || [ "$show_content" = "Y" ]; then
    echo ""
    echo "==== 证书文件内容 (cert.pem) ===="
    cat "$CERT_FILE"
    echo ""
    echo "==== 私钥文件内容 (key.pem) ===="
    cat "$KEY_FILE"
    echo ""
  fi
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
echo "3) 重置账号密码"
echo "4) 配置 SSL 证书（支持自签名，无需域名）"
echo "5) 下载 SSL 证书"
echo "0) 退出"
read -rp "请输入选项[1/2/3/4/5/0]: " choice

case "$choice" in
  1) install_panel ;;
  2) uninstall_panel ;;
  3) reset_account ;;
  4) install_ssl ;;
  5) download_cert ;;
  0) echo "已退出"; exit 0 ;;
  *) echo "无效选项"; exit 1 ;;
esac

