#!/usr/bin/env bash
# ==============================================================================
#  一键安装脚本：Nginx + PHP-FPM + MySQL + Redis 并部署 dujiaoka
# ------------------------------------------------------------------------------
#  适用:  Debian 11/12, Ubuntu 20.04/22.04  (全新最小系统最佳)
#  特性:
#    • 交互式输入域名, 自动申请 Let’s Encrypt HTTPS (可留空只用 IP, HTTP)
#    • 自动安装并配置所需服务, 克隆并部署 dujiaoka 至 /var/www/dujiaoka
#    • 创建数据库、生成随机 DB 密码, 写入 .env
#    • 创建后台管理员账号:  用户名 damin  密码 yao581581
# ------------------------------------------------------------------------------
#  使用:
#      sudo bash install_dujiaoka.sh
# ==============================================================================
set -euo pipefail

# ---------- 可自定义变量 -------------------------------------------------------
APP_DIR="/var/www/dujiaoka"             # 代码目录
NGINX_SITE="/etc/nginx/sites-available/dujiaoka.conf"
NGINX_SITE_LINK="/etc/nginx/sites-enabled/dujiaoka.conf"
DB_NAME="dujiaoka"
DB_USER="dujiaoka"
ADMIN_USER="damin"
ADMIN_PASS="yao581581"

# ---------- 必须以 root 运行 ---------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  echo "[错误] 请以 root (sudo) 运行该脚本" >&2
  exit 1
fi

# ---------- 检测系统 -----------------------------------------------------------
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "无法识别系统, /etc/os-release 不存在" >&2
  exit 1
fi

if [[ $ID != "ubuntu" && $ID != "debian" ]]; then
  echo "[错误] 仅支持 Debian/Ubuntu 系列" >&2
  exit 1
fi

# ---------- 交互获取域名 -------------------------------------------------------
read -rp "请输入要绑定的域名（留空则仅使用服务器 IP，不申请 HTTPS）：" DOMAIN || true
DOMAIN=${DOMAIN:-}

# ---------- 取得服务器出口 IP ---------------------------------------------------
SERVER_IP=$(ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++){if($i=="src"){print $(i+1); exit}}}')
SERVER_IP=${SERVER_IP:-127.0.0.1}

APP_URL="http://${SERVER_IP}"
if [[ -n $DOMAIN ]]; then
  APP_URL="https://${DOMAIN}"
fi

# ---------- APT 更新及安装 -----------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -y

# 基础工具
apt-get install -y ca-certificates curl wget gnupg lsb-release unzip zip tar git software-properties-common

# Nginx / Redis / Certbot
apt-get install -y nginx redis-server certbot python3-certbot-nginx

# PHP (使用系统自带版本)
apt-get install -y php-fpm php-cli php-common php-mysql php-redis php-curl php-gd php-mbstring \
                   php-xml php-zip php-bcmath php-intl php-soap composer

# MySQL (尝试安装 mysql-server, 若失败则 mariadb-server)
if ! apt-get install -y mysql-server; then
  apt-get install -y mariadb-server
fi

# 开机自启
systemctl enable --now nginx
systemctl enable --now redis-server
systemctl enable --now php*-fpm
systemctl enable --now mysql || systemctl enable --now mariadb

# ---------- 创建数据库及用户 ---------------------------------------------------
DB_PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)

mysql -uroot <<MYSQL
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
MYSQL

# ---------- 下载 & 安装 dujiaoka ----------------------------------------------
if [[ ! -d $APP_DIR ]]; then
  git clone https://github.com/assimon/dujiaoka.git "$APP_DIR"
else
  echo "目录 $APP_DIR 已存在, 跳过克隆"
fi

cd "$APP_DIR"
# 使用最新 release tag, 若失败则保持 master
LATEST_TAG=$(git describe --tags $(git rev-list --tags --max-count=1) 2>/dev/null || true)
if [[ -n $LATEST_TAG ]]; then
  git checkout "$LATEST_TAG"
fi

# Composer 依赖
composer install --no-interaction --no-dev --prefer-dist --optimize-autoloader

# 复制环境文件
cp -n .env.example .env

# 生成 APP_KEY
php artisan key:generate --force

# 更新 .env (DB、APP_URL)
sed -i "s@^DB_DATABASE=.*@DB_DATABASE=$DB_NAME@" .env
sed -i "s@^DB_USERNAME=.*@DB_USERNAME=$DB_USER@" .env
sed -i "s@^DB_PASSWORD=.*@DB_PASSWORD=$DB_PASS@" .env
sed -i "s@^APP_URL=.*@APP_URL=$APP_URL@" .env

# 数据库迁移 & seeder
php artisan migrate --seed --force

# 创建/修改管理员账号
ADMIN_HASH=$(php -r "echo password_hash('$ADMIN_PASS', PASSWORD_BCRYPT);")
mysql -uroot <<MYSQL
USE \`$DB_NAME\`;
INSERT INTO admin_users (id, username, password, name) VALUES (1,'$ADMIN_USER','$ADMIN_HASH','Administrator')
    ON DUPLICATE KEY UPDATE username='$ADMIN_USER', password='$ADMIN_HASH';
MYSQL

# 设置文件权限
chown -R www-data:www-data "$APP_DIR"
find "$APP_DIR" -type f -exec chmod 640 {} \;
find "$APP_DIR" -type d -exec chmod 750 {} \;

# ---------- 配置 Nginx ---------------------------------------------------------
PHP_FPM_SOCK=$(find /run/php -type s -name "php*fpm.sock" | head -n1)

cat > "$NGINX_SITE" <<NGINX
server {
    listen 80;
    server_name ${DOMAIN:-_};

    root ${APP_DIR}/public;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_FPM_SOCK};
    }

    location ~* \.(jpg|jpeg|gif|png|css|js|ico|svg|woff|woff2)$ {
        expires 30d;
        access_log off;
    }

    error_log /var/log/nginx/dujiaoka_error.log;
    access_log /var/log/nginx/dujiaoka_access.log;
}
NGINX

ln -sf "$NGINX_SITE" "$NGINX_SITE_LINK"
nginx -t && systemctl reload nginx

# ---------- HTTPS (可选) -------------------------------------------------------
if [[ -n $DOMAIN ]]; then
  echo "正在为 $DOMAIN 申请 Let's Encrypt 证书..."
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN" --redirect || true
fi

# ---------- 完成 ---------------------------------------------------------------
echo "====================================================================="
echo " dujiaoka 已安装完毕!"
echo " 地址:  $APP_URL"
echo " 后台:  $APP_URL/admin"
echo " 管理员用户名: $ADMIN_USER"
echo " 管理员密码:   $ADMIN_PASS"
echo " MySQL 数据库: $DB_NAME"
echo " MySQL 用户:   $DB_USER"
echo " MySQL 密码:   $DB_PASS"
echo "====================================================================="

