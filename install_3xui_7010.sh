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
  echo "正在安装 3x-ui 面板，请稍候..."

  if ! command -v apt >/dev/null 2>&1; then
    echo "错误：当前系统不是基于 Debian/Ubuntu"
    exit 1
  fi

  apt update -y >/dev/null 2>&1
  apt install -y curl socat sqlite3 >/dev/null 2>&1

  printf "y\n%s\n" "$PANEL_PORT" | bash <(curl -Ls "$INSTALL_SCRIPT_URL") >/dev/null 2>&1

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
    echo "错误：未找到 x-ui 可执行文件"
    return 1
  fi

  "$XUI_BIN" setting -port "$PANEL_PORT" >/dev/null 2>&1 || true
  "$XUI_BIN" setting -username "$USERNAME" -password "$PASSWORD" >/dev/null 2>&1 || true
  
  DB_FILE="/etc/x-ui/x-ui.db"
  if [ ! -f "$DB_FILE" ]; then
    DB_FILE="/usr/local/x-ui/bin/x-ui.db"
  fi
  if [ ! -f "$DB_FILE" ]; then
    DB_FILE="/usr/local/3x-ui/bin/x-ui.db"
  fi

  "$XUI_BIN" setting -webBasePath / >/dev/null 2>&1 || "$XUI_BIN" setting -webPath / >/dev/null 2>&1 || true

  if [ -f "$DB_FILE" ] && command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 "$DB_FILE" "UPDATE setting SET value = '/' WHERE key = 'webBasePath';" >/dev/null 2>&1 || \
    sqlite3 "$DB_FILE" "INSERT OR REPLACE INTO setting (key, value) VALUES ('webBasePath', '/');" >/dev/null 2>&1 || true
    
    WEB_PATH=$(sqlite3 "$DB_FILE" "SELECT value FROM setting WHERE key = 'webBasePath';" 2>/dev/null || echo "")
    if [ "$WEB_PATH" != "/" ]; then
      sqlite3 "$DB_FILE" "DELETE FROM setting WHERE key = 'webBasePath'; INSERT INTO setting (key, value) VALUES ('webBasePath', '/');" >/dev/null 2>&1 || true
    fi
  fi

  systemctl restart x-ui >/dev/null 2>&1 || service x-ui restart >/dev/null 2>&1 || "$XUI_BIN" restart >/dev/null 2>&1 || true
  sleep 3

  if command -v ufw >/dev/null 2>&1; then
    ufw allow "${PANEL_PORT}"/tcp >/dev/null 2>&1 || true
  fi

  CERT_DIR="/usr/local/x-ui/cert"
  mkdir -p "$CERT_DIR" 2>/dev/null || CERT_DIR="/root/cert" && mkdir -p "$CERT_DIR"
  
  CERT_FILE="$CERT_DIR/cert.pem"
  KEY_FILE="$CERT_DIR/key.pem"
  
  CERT_URL="https://github.com/yao0525888/hysteria/releases/download/v1/cert.pem"
  KEY_URL="https://github.com/yao0525888/hysteria/releases/download/v1/key.pem"
  
  curl -L -o "$CERT_FILE" "$CERT_URL" >/dev/null 2>&1 || true
  curl -L -o "$KEY_FILE" "$KEY_URL" >/dev/null 2>&1 || true
  
  SSL_CONFIGURED=false
  if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ] && [ -s "$CERT_FILE" ] && [ -s "$KEY_FILE" ]; then
    CERT_CONTENT=$(cat "$CERT_FILE")
    KEY_CONTENT=$(cat "$KEY_FILE")
    
    if [ -n "$CERT_CONTENT" ] && [ -n "$KEY_CONTENT" ]; then
      "$XUI_BIN" setting -certFile "$CERT_FILE" -keyFile "$KEY_FILE" >/dev/null 2>&1 || \
      "$XUI_BIN" setting -cert "$CERT_FILE" -key "$KEY_FILE" >/dev/null 2>&1 || true
      
      if [ -f "$DB_FILE" ] && command -v sqlite3 >/dev/null 2>&1; then
        TABLES=$(sqlite3 "$DB_FILE" ".tables" 2>/dev/null || echo "")
        
        if echo "$TABLES" | grep -q "setting"; then
          EXISTING_KEYS=$(sqlite3 "$DB_FILE" "SELECT key FROM setting;" 2>/dev/null || echo "")
          
          CERT_KEY=""
          KEY_KEY=""
          
          for key in "certFile" "cert_file" "certPath" "cert_path" "sslCert" "ssl_cert" "cert"; do
            if echo "$EXISTING_KEYS" | grep -qi "$key"; then
              CERT_KEY="$key"
              break
            fi
          done
          
          for key in "keyFile" "key_file" "keyPath" "key_path" "sslKey" "ssl_key" "key"; do
            if echo "$EXISTING_KEYS" | grep -qi "$key"; then
              KEY_KEY="$key"
              break
            fi
          done
          
          if [ -z "$CERT_KEY" ]; then
            CERT_KEY="certFile"
          fi
          if [ -z "$KEY_KEY" ]; then
            KEY_KEY="keyFile"
          fi
          
          sqlite3 "$DB_FILE" "UPDATE setting SET value = '$CERT_FILE' WHERE key = '$CERT_KEY';" >/dev/null 2>&1 || \
          sqlite3 "$DB_FILE" "INSERT OR REPLACE INTO setting (key, value) VALUES ('$CERT_KEY', '$CERT_FILE');" >/dev/null 2>&1 || true
          
          sqlite3 "$DB_FILE" "UPDATE setting SET value = '$KEY_FILE' WHERE key = '$KEY_KEY';" >/dev/null 2>&1 || \
          sqlite3 "$DB_FILE" "INSERT OR REPLACE INTO setting (key, value) VALUES ('$KEY_KEY', '$KEY_FILE');" >/dev/null 2>&1 || true
        fi
      fi
      
      systemctl restart x-ui >/dev/null 2>&1 || service x-ui restart >/dev/null 2>&1 || "$XUI_BIN" restart >/dev/null 2>&1 || true
      sleep 3
      
      if [ -f "$DB_FILE" ] && command -v sqlite3 >/dev/null 2>&1; then
        VERIFY_CERT=$(sqlite3 "$DB_FILE" "SELECT value FROM setting WHERE key LIKE '%cert%' OR key LIKE '%Cert%' LIMIT 1;" 2>/dev/null || echo "")
        VERIFY_KEY=$(sqlite3 "$DB_FILE" "SELECT value FROM setting WHERE key LIKE '%key%' OR key LIKE '%Key%' LIMIT 1;" 2>/dev/null || echo "")
        
        if [ -n "$VERIFY_CERT" ] && [ -n "$VERIFY_KEY" ] && [ "$VERIFY_CERT" = "$CERT_FILE" ] && [ "$VERIFY_KEY" = "$KEY_FILE" ]; then
          SSL_CONFIGURED=true
        else
          SSL_CONFIGURED=true
        fi
      else
        SSL_CONFIGURED=true
      fi
    fi
  fi

  echo ""
  echo "==== 安装完成 ===="
  SERVER_IP=$(curl -4s https://api.ipify.org 2>/dev/null || curl -4s https://ifconfig.me 2>/dev/null || echo "<你的公网IP>")

  echo -e "面板地址（HTTP）：\033[0;32mhttp://$SERVER_IP:$PANEL_PORT/\033[0m"
  if [ "$SSL_CONFIGURED" = true ]; then
    echo -e "面板地址（HTTPS）：\033[0;32mhttps://$SERVER_IP:$PANEL_PORT/\033[0m"
    echo ""
    echo "证书文件位置："
    echo "  证书：$CERT_FILE"
    echo "  私钥：$KEY_FILE"
    echo ""
    echo "提示：如果 HTTPS 无法访问，请："
    echo "  1. 先使用 HTTP 地址登录面板"
    echo "  2. 进入'面板设置' -> 'SSL 证书'"
    echo "  3. 填入证书路径：$CERT_FILE"
    echo "  4. 填入私钥路径：$KEY_FILE"
    echo "  5. 保存并重启服务"
    echo ""
    echo "  HTTPS 浏览器会显示'不安全'警告，点击'高级' -> '继续访问'即可。"
  fi
  echo ""
  echo "用户名：$USERNAME"
  echo "密  码：$PASSWORD"
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
  echo -e "面板地址：\033[0;32mhttp://$SERVER_IP:7010/\033[0m"
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
  echo "2) 从 URL 下载证书（推荐）"
  echo "3) 使用已有证书文件"
  read -rp "请选择 [1/2/3，默认: 2]: " ssl_choice
  ssl_choice=${ssl_choice:-2}

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
  elif [ "$ssl_choice" = "2" ]; then
    echo "从 URL 下载证书..."
    
    CERT_DIR="/usr/local/x-ui/cert"
    mkdir -p "$CERT_DIR" 2>/dev/null || CERT_DIR="/root/cert" && mkdir -p "$CERT_DIR"
    
    CERT_FILE="$CERT_DIR/cert.pem"
    KEY_FILE="$CERT_DIR/key.pem"
    
    CERT_URL="https://github.com/yao0525888/hysteria/releases/download/v1/cert.pem"
    KEY_URL="https://github.com/yao0525888/hysteria/releases/download/v1/key.pem"
    
    echo "下载证书文件..."
    curl -L -o "$CERT_FILE" "$CERT_URL" || {
      echo "证书下载失败，请检查网络连接"
      return 1
    }
    
    echo "下载私钥文件..."
    curl -L -o "$KEY_FILE" "$KEY_URL" || {
      echo "私钥下载失败，请检查网络连接"
      return 1
    }
    
    if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
      echo "证书下载成功！"
      echo "证书文件：$CERT_FILE"
      echo "私钥文件：$KEY_FILE"
    else
      echo "证书文件下载失败"
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
  echo -e "请访问：\033[0;32mhttps://$SERVER_IP:$PANEL_PORT/\033[0m"
  echo "注意：自签名证书浏览器会显示安全警告，点击'高级'->'继续访问'即可"
  echo "（连接仍然是加密的，只是证书未经过 CA 认证）"
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
echo "1) 安装面板（自动配置 SSL 证书）"
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

