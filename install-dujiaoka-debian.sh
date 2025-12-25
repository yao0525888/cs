#!/usr/bin/env bash
set -euo pipefail

# ====== 可修改项 ======
APP_DIR="/var/www/dujiaoka"
REPO_URL="https://github.com/assimon/dujiaoka.git"
BRANCH="master"

ADMIN_USER="damin"
ADMIN_PASS="yao581581"

DB_NAME="dujiaoka"
DB_USER="dujiaoka"
# 自动生成数据库密码
DB_PASS="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 24)"

# PHP 版本（Debian 11 默认 7.4，Debian 12 默认 8.2）
# dujiaoka 常见可用：7.4/8.0/8.1/8.2（以项目实际要求为准）
PHP_VER=""   # 留空表示自动选择系统默认
# =====================

if [[ $EUID -ne 0 ]]; then
  echo "请用 root 运行：sudo -i 后再执行。"
  exit 1
fi

DEBIAN_VER="$(. /etc/os-release && echo "${VERSION_ID}")"
if [[ "${DEBIAN_VER}" != "11" && "${DEBIAN_VER}" != "12" ]]; then
  echo "仅支持 Debian 11/12，当前：${DEBIAN_VER}"
  exit 1
fi

echo "[1/9] 安装基础依赖..."
# 不执行系统更新（按你的要求）
# apt-get update -y
apt-get install -y curl wget git unzip zip ca-certificates lsb-release gnupg2 apt-transport-https software-properties-common

echo "[2/9] 安装 Nginx..."
apt-get install -y nginx

echo "[3/9] 安装 Redis..."
apt-get install -y redis-server

echo "[4/9] 安装 MariaDB..."
# 使用 Debian 官方源自带的 MariaDB，确保 100% 无交互安装
if ! command -v mysql >/dev/null 2>&1; then
  DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server mariadb-client
fi
systemctl enable mariadb
systemctl restart mariadb

echo "[5/9] 安装 PHP-FPM + 扩展 + Composer..."
# 选择 PHP 版本：留空则用系统默认
if [[ -z "${PHP_VER}" ]]; then
  if [[ "${DEBIAN_VER}" == "11" ]]; then PHP_VER="7.4"; else PHP_VER="8.2"; fi
fi

# Debian 官方源不一定含旧版本；这里优先尝试系统源安装对应版本，失败则提示你改用默认或走 sury 源
set +e
apt-get install -y \
  "php${PHP_VER}-fpm" \
  "php${PHP_VER}-cli" \
  "php${PHP_VER}-common" \
  "php${PHP_VER}-curl" \
  "php${PHP_VER}-mbstring" \
  "php${PHP_VER}-xml" \
  "php${PHP_VER}-zip" \
  "php${PHP_VER}-gd" \
  "php${PHP_VER}-mysql" \
  "php${PHP_VER}-bcmath" \
  "php${PHP_VER}-redis" \
  "php${PHP_VER}-intl" \
  "php${PHP_VER}-opcache"
PHP_OK=$?
set -e

if [[ $PHP_OK -ne 0 ]]; then
  echo "安装 php${PHP_VER} 失败。可能系统源不提供该版本。"
  echo "你可以："
  echo "1) 告诉我你希望用 Debian 默认 PHP（Debian 12=8.2）我给你改脚本"
  echo "2) 或启用 sury 源安装指定版本（我也可提供）"
  exit 1
fi

if ! command -v composer >/dev/null 2>&1; then
  curl -fsSL https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
fi

echo "[6/9] 拉取 dujiaoka 代码..."
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}"
git clone -b "${BRANCH}" --depth 1 "${REPO_URL}" "${APP_DIR}"

chown -R www-data:www-data "${APP_DIR}"

echo "[7/9] 配置 .env 并安装依赖..."
cd "${APP_DIR}"

if [[ -f .env.example && ! -f .env ]]; then
  cp .env.example .env
fi

# 生成 APP_KEY（Laravel 风格）
sudo -u www-data bash -lc "cd '${APP_DIR}' && composer install --no-dev -o"
sudo -u www-data bash -lc "cd '${APP_DIR}' && php artisan key:generate --force"

# 配置数据库/缓存（尽量用通用键名；若项目 env 键不同，报错贴我我来适配）
sed -i "s/^DB_HOST=.*/DB_HOST=127.0.0.1/g" .env || true
sed -i "s/^DB_PORT=.*/DB_PORT=3306/g" .env || true
sed -i "s/^DB_DATABASE=.*/DB_DATABASE=${DB_NAME}/g" .env || true
sed -i "s/^DB_USERNAME=.*/DB_USERNAME=${DB_USER}/g" .env || true
sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=${DB_PASS}/g" .env || true

# Redis
grep -q "^REDIS_HOST=" .env 2>/dev/null && sed -i "s/^REDIS_HOST=.*/REDIS_HOST=127.0.0.1/g" .env || true
grep -q "^REDIS_PORT=" .env 2>/dev/null && sed -i "s/^REDIS_PORT=.*/REDIS_PORT=6379/g" .env || true

echo "[8/9] 创建数据库和用户..."
# MySQL root 登录方式在不同安装模式不同：优先尝试 socket
mysql -uroot -e "SELECT 1;" >/dev/null 2>&1 || true

mysql -uroot <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

echo "[9/9] 初始化 dujiaoka 数据表 & 创建管理员..."
sudo -u www-data bash -lc "cd '${APP_DIR}' && php artisan migrate --force" || true

# dujiaoka 创建管理员命令/表字段可能随版本变化：
# 这里优先尝试 artisan 命令；若不存在则提示你把报错贴出来我再适配（我能改成直接写库）
set +e
sudo -u www-data bash -lc "cd '${APP_DIR}' && php artisan admin:create --username='${ADMIN_USER}' --password='${ADMIN_PASS}'" 
CREATE_ADMIN_OK=$?
set -e

if [[ $CREATE_ADMIN_OK -ne 0 ]]; then
  echo "未能通过 artisan 创建管理员（可能该版本命令不同）。"
  echo "先继续完成 Nginx 配置。安装后你把上述报错复制给我，我给你适配成正确的创建方式。"
fi

echo "配置 Nginx 站点..."
PHP_FPM_SOCK="/run/php/php${PHP_VER}-fpm.sock"
NGINX_SITE="/etc/nginx/sites-available/dujiaoka"

cat > "${NGINX_SITE}" <<'NGINX'
server {
    listen 80;
    server_name _;
    root /var/www/dujiaoka/public;

    index index.php index.html;

    client_max_body_size 50m;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:__PHP_FPM_SOCK__;
    }

    location ~* \.(jpg|jpeg|gif|png|css|js|ico|svg|woff|woff2|ttf|eot)$ {
        expires 30d;
        access_log off;
    }
}
NGINX

sed -i "s#__PHP_FPM_SOCK__#${PHP_FPM_SOCK}#g" "${NGINX_SITE}"

ln -sf "${NGINX_SITE}" /etc/nginx/sites-enabled/dujiaoka
rm -f /etc/nginx/sites-enabled/default || true

nginx -t
systemctl restart nginx
systemctl enable nginx

systemctl enable redis-server || true
systemctl restart redis-server || true

systemctl enable "php${PHP_VER}-fpm"
systemctl restart "php${PHP_VER}-fpm"

echo
IP_ADDR="$(hostname -I | awk '{print $1}')"
echo "安装完成。"
echo "访问地址:   http://${IP_ADDR}/"
echo "后台入口一般为: http://${IP_ADDR}/admin （若不对，把实际后台路径告诉我）"
echo
echo "数据库信息："
echo "  DB:   ${DB_NAME}"
echo "  User: ${DB_USER}"
echo "  Pass: ${DB_PASS}"
echo
echo "管理员（按你要求）："
echo "  User: ${ADMIN_USER}"
echo "  Pass: ${ADMIN_PASS}"
echo
echo "强烈建议：登录后台后立刻修改密码。"