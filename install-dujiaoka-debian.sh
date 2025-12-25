#!/usr/bin/env bash
# ==========================================================
# 一键安装 dujiaoka   Author: Cursor AI   Date: 2025-12-25
#  - 适用系统：Debian 11 / 12 ×64
#  - 功   能：自动安装 Nginx + PHP-FPM + MySQL + Redis 并部署 dujiaoka
#  - 选   择：可输入域名启用 HTTPS，也可留空只用服务器 IP
#  - 管理员：用户名 damin   密码 yao581581
# ==========================================================
set -euo pipefail

## ===== 可调整项 =====
APP_DIR=/var/www/dujiaoka
REPO_URL="https://github.com/assimon/dujiaoka.git"
BRANCH=master

ADMIN_USER=damin
ADMIN_PASS=yao581581

DB_NAME=dujiaoka
DB_USER=dujiaoka
DB_PASS="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 24)"

# PHP 版本（留空=系统默认：Debian11→7.4，Debian12→8.2）
PHP_VER=""
## ====================

echo "================ dujiaoka 一键安装脚本 ================"
echo "提示：脚本会全自动安装 Nginx / PHP / MySQL / Redis 等组件。"
echo "-------------------------------------------------------"
read -rp "请输入安装访问域名(留空则使用服务器 IP 访问)： " SITE_DOMAIN
USE_DOMAIN=false
if [[ -n "$SITE_DOMAIN" ]]; then USE_DOMAIN=true; fi
echo "-------------------------------------------------------"
echo "管理员账号：$ADMIN_USER"
echo "管理员密码：$ADMIN_PASS"
echo "数据库名：$DB_NAME"
echo "数据库用户：$DB_USER"
echo "数据库密码：$DB_PASS"
echo "======================================================="
read -rp "确认无误后回车继续，Ctrl+C 退出..."

if [[ $EUID -ne 0 ]]; then
  echo "请以 root 身份运行( sudo -i )"; exit 1; fi

DEBIAN_VER="$(. /etc/os-release && echo "${VERSION_ID}")"
[[ "$DEBIAN_VER" =~ ^11|12$ ]] || {
  echo "仅支持 Debian 11/12 ，当前 ${DEBIAN_VER}"; exit 1; }

echo "[1/10] 更新系统..."
apt-get update -y
apt-get install -y curl wget git unzip zip ca-certificates lsb-release gnupg2 \
                   apt-transport-https software-properties-common

echo "[2/10] 安装 Nginx..."
apt-get install -y nginx

echo "[3/10] 安装 Redis..."
apt-get install -y redis-server

echo "[4/10] 安装 MySQL..."
if ! command -v mysql >/dev/null 2>&1; then
  cd /tmp && wget -q https://dev.mysql.com/get/mysql-apt-config_0.8.29-1_all.deb \
       -O mysql-apt-config.deb
  echo "mysql-apt-config mysql-apt-config/select-server select mysql-8.0 debconf" \
      | debconf-set-selections
  DEBIAN_FRONTEND=noninteractive dpkg -i mysql-apt-config.deb >/dev/null 2>&1
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-community-server
fi

echo "[5/10] 安装 PHP$PHP_VER ..."
if [[ -z "$PHP_VER" ]]; then
  PHP_VER=$([[ "$DEBIAN_VER" == 11 ]] && echo 7.4 || echo 8.2); fi
apt-get install -y php${PHP_VER}-{fpm,cli,common,curl,mbstring,xml,zip,gd,mysql,bcmath,redis,intl,opcache}

echo "[6/10] 安装 Composer..."
command -v composer >/dev/null 2>&1 || \
  curl -fsSL https://getcomposer.org/installer | php -- \
      --install-dir=/usr/local/bin --filename=composer

echo "[7/10] 拉取 dujiaoka..."
rm -rf "$APP_DIR"; mkdir -p "$APP_DIR"
git clone --depth 1 -b "$BRANCH" "$REPO_URL" "$APP_DIR"
chown -R www-data:www-data "$APP_DIR"

echo "[8/10] 安装 PHP 依赖 & 初始化 .env..."
sudo -u www-data bash -lc "
  cd '$APP_DIR'
  cp -n .env.example .env
  composer install --no-dev -o
  php artisan key:generate --force
"
sed -i "s/^DB_HOST=.*/DB_HOST=127.0.0.1/;
        s/^DB_PORT=.*/DB_PORT=3306/;
        s/^DB_DATABASE=.*/DB_DATABASE=$DB_NAME/;
        s/^DB_USERNAME=.*/DB_USERNAME=$DB_USER/;
        s/^DB_PASSWORD=.*/DB_PASSWORD=$DB_PASS/" "$APP_DIR/.env"

echo "[9/10] 创建数据库 & 赋权..."
mysql -uroot <<SQL
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
SQL

echo "[10/10] 导入表 & 创建管理员..."
sudo -u www-data bash -lc "cd '$APP_DIR' && php artisan migrate --force"
sudo -u www-data bash -lc "cd '$APP_DIR' && php artisan admin:create \
      --username='$ADMIN_USER' --password='$ADMIN_PASS' || true"

PHP_FPM_SOCK=/run/php/php${PHP_VER}-fpm.sock
NGINX_CONF=/etc/nginx/sites-available/dujiaoka
cat > "$NGINX_CONF" <<NGINX
server {
    listen 80;
    $( $USE_DOMAIN && echo "server_name $SITE_DOMAIN;" || echo "server_name _;" )
    root $APP_DIR/public;
    index index.php index.html;

    client_max_body_size 50m;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$PHP_FPM_SOCK;
    }
    location ~* \.(jpg|jpeg|gif|png|css|js|ico|svg|woff|woff2|ttf|eot)\$ {
        expires 30d;
        access_log off;
    }
}
NGINX

ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/dujiaoka
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# ===== 申请证书 =====
if $USE_DOMAIN; then
  echo "检测到域名，自动申请 SSL 证书..."
  apt-get install -y certbot python3-certbot-nginx
  certbot --nginx --non-interactive --agree-tos -m admin@$SITE_DOMAIN -d "$SITE_DOMAIN"
fi

systemctl enable --now nginx redis-server php${PHP_VER}-fpm

IP_ADDR="$(hostname -I | awk '{print $1}')"
echo
echo "=========== dujiaoka 安装完成 ==========="
if $USE_DOMAIN; then
  echo "请稍等 1~2 分钟让证书自动配置生效。"
  echo "前台地址: https://$SITE_DOMAIN/"
  echo "后台地址: https://$SITE_DOMAIN/admin"
else
  echo "前台地址: http://$IP_ADDR/"
  echo "后台地址: http://$IP_ADDR/admin"
fi
echo
echo "管理员账号: $ADMIN_USER"
echo "管理员密码: $ADMIN_PASS   (请登录后立即修改!)"
echo "========================================"

