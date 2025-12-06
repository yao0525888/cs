#!/bin/bash

echo "=========================================="
echo "  客户数据管理系统 - Linux部署脚本1"
echo "=========================================="
echo ""

WEB_DIR="/var/www/html"
FILE_NAME="default.html"
GITHUB_URL="https://github.com/yao0525888/hysteria/releases/download/v1/default.html"
PORT="7009"
CURRENT_DIR=$(pwd)

if [ "$EUID" -ne 0 ]; then 
    echo "错误：请使用sudo运行此脚本"
    exit 1
fi

download_file() {
    local target_path=$1
    local target_dir=$(dirname "$target_path")
    
    if [ ! -d "$target_dir" ]; then
        echo "创建目录: $target_dir"
        mkdir -p "$target_dir"
    fi
    
    echo "正在从GitHub下载文件..."
    if command -v wget &> /dev/null; then
        if wget -q "$GITHUB_URL" -O "$target_path"; then
            if [ -f "$target_path" ] && [ -s "$target_path" ]; then
                echo "文件下载成功"
                return 0
            fi
        fi
    elif command -v curl &> /dev/null; then
        if curl -sL "$GITHUB_URL" -o "$target_path"; then
            if [ -f "$target_path" ] && [ -s "$target_path" ]; then
                echo "文件下载成功"
                return 0
            fi
        fi
    else
        echo "错误：未找到wget或curl，无法下载文件"
        echo "请手动安装: sudo apt install wget 或 sudo yum install wget"
        return 1
    fi
    
    echo "文件下载失败"
    return 1
}

get_file() {
    local target_path=$1
    if [ -f "$CURRENT_DIR/$FILE_NAME" ]; then
        echo "使用本地文件..."
        cp "$CURRENT_DIR/$FILE_NAME" "$target_path"
        return 0
    else
        if download_file "$target_path"; then
            return 0
        else
            return 1
        fi
    fi
}

echo "正在安装Nginx..."
NGINX_INSTALLED=false

if command -v apt-get &> /dev/null; then
    echo "检查Nginx是否已安装..."
    if command -v nginx &> /dev/null && [ -d "/etc/nginx" ]; then
        echo "Nginx已安装，版本: $(nginx -v 2>&1)"
        NGINX_INSTALLED=true
    else
        echo ""
        echo "=========================================="
        echo "从GitHub源码编译安装Nginx"
        echo "=========================================="
        echo ""
        echo "开始从GitHub源码编译安装Nginx..."
        
        BUILD_DIR="/tmp/nginx-build"
        rm -rf "$BUILD_DIR"
        mkdir -p "$BUILD_DIR"
        cd "$BUILD_DIR"
        
        echo "检查编译依赖..."
        MISSING_DEPS=""
        command -v gcc >/dev/null 2>&1 || MISSING_DEPS="$MISSING_DEPS gcc"
        command -v make >/dev/null 2>&1 || MISSING_DEPS="$MISSING_DEPS make"
        command -v git >/dev/null 2>&1 || MISSING_DEPS="$MISSING_DEPS git"
        
        if [ -n "$MISSING_DEPS" ]; then
            echo "缺少编译依赖: $MISSING_DEPS"
            echo "尝试自动安装编译依赖..."
            
            if command -v apt-get &> /dev/null; then
                echo "使用apt-get安装编译工具..."
                apt-get update 2>&1 | grep -v "404" | grep -v "Failed" | grep -v "Err:" | grep -v "Ign:" || true
                apt-get install -y gcc make git 2>&1 | grep -v "404" | grep -v "Failed" | grep -v "Err:" | grep -v "Ign:" || {
                    echo "警告：部分依赖安装可能失败，继续尝试..."
                }
            elif command -v yum &> /dev/null; then
                echo "使用yum安装编译工具..."
                yum install -y gcc make git 2>&1 || {
                    echo "警告：部分依赖安装可能失败，继续尝试..."
                }
            elif command -v dnf &> /dev/null; then
                echo "使用dnf安装编译工具..."
                dnf install -y gcc make git 2>&1 || {
                    echo "警告：部分依赖安装可能失败，继续尝试..."
                }
            else
                echo "未找到包管理器，无法自动安装依赖"
            fi
            
            echo "重新检查编译依赖..."
            MISSING_DEPS=""
            command -v gcc >/dev/null 2>&1 || MISSING_DEPS="$MISSING_DEPS gcc"
            command -v make >/dev/null 2>&1 || MISSING_DEPS="$MISSING_DEPS make"
            command -v git >/dev/null 2>&1 || MISSING_DEPS="$MISSING_DEPS git"
            
            if [ -n "$MISSING_DEPS" ]; then
                echo "错误：仍缺少编译依赖: $MISSING_DEPS"
                echo "请手动安装这些工具后重新运行脚本"
                echo ""
                echo "安装命令："
                if command -v apt-get &> /dev/null; then
                    echo "  sudo apt-get install -y gcc make git"
                elif command -v yum &> /dev/null; then
                    echo "  sudo yum install -y gcc make git"
                elif command -v dnf &> /dev/null; then
                    echo "  sudo dnf install -y gcc make git"
                fi
                exit 1
            else
                echo "编译依赖安装成功"
            fi
        else
            echo "编译依赖已满足"
        fi
        
        echo "克隆Nginx源码..."
        if git clone https://github.com/nginx/nginx.git 2>&1; then
            cd nginx
            
            echo "配置编译选项（使用最简配置）..."
            auto/configure --prefix=/usr/local/nginx --with-http_ssl_module 2>&1 || {
                echo "使用默认配置..."
                auto/configure --prefix=/usr/local/nginx 2>&1
            }
            
            echo "编译Nginx..."
            if make -j$(nproc 2>/dev/null || echo 1) 2>&1; then
                echo "安装Nginx..."
                make install 2>&1
                
                if [ -f "/usr/local/nginx/sbin/nginx" ]; then
                    echo "创建符号链接..."
                    ln -sf /usr/local/nginx/sbin/nginx /usr/local/bin/nginx 2>/dev/null || true
                    ln -sf /usr/local/nginx/sbin/nginx /usr/bin/nginx 2>/dev/null || true
                    
                    echo "创建必要的目录..."
                    mkdir -p /etc/nginx/conf.d
                    mkdir -p /var/log/nginx
                    mkdir -p /var/cache/nginx
                    
                    echo "创建systemd服务文件..."
                    cat > /etc/systemd/system/nginx.service <<'EOF'
[Unit]
Description=The nginx HTTP and reverse proxy server
After=network.target remote-fs.target nss-lookup.target

[Service]
Type=forking
PIDFile=/var/run/nginx.pid
ExecStartPre=/usr/local/nginx/sbin/nginx -t
ExecStart=/usr/local/nginx/sbin/nginx
ExecReload=/bin/kill -s HUP $MAINPID
KillSignal=SIGQUIT
TimeoutStopSec=5
KillMode=process
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
                    
                    systemctl daemon-reload
                    
                    if [ -f "/usr/local/nginx/sbin/nginx" ] || command -v nginx &> /dev/null; then
                        echo "Nginx编译安装成功"
                        NGINX_INSTALLED=true
                    fi
                fi
            else
                echo "编译失败，请检查错误信息"
            fi
            
            cd /
            rm -rf "$BUILD_DIR"
        else
            echo "克隆源码失败，请检查网络连接和git是否安装"
            exit 1
        fi
        
        if [ "$NGINX_INSTALLED" = false ]; then
            echo ""
            echo "=========================================="
            echo "Nginx编译安装失败"
            echo "=========================================="
            echo "请检查："
            echo "1. 网络连接是否正常"
            echo "2. 是否安装了编译工具（gcc, make, git）"
            echo "3. 是否有足够的磁盘空间"
            echo ""
            echo "手动编译安装命令："
            echo "   cd /tmp"
            echo "   git clone https://github.com/nginx/nginx.git"
            echo "   cd nginx"
            echo "   auto/configure --prefix=/usr/local/nginx --with-http_ssl_module"
            echo "   make"
            echo "   sudo make install"
            echo ""
            echo "=========================================="
            exit 1
        fi
    fi
elif command -v yum &> /dev/null; then
    yum install -y nginx
elif command -v dnf &> /dev/null; then
    dnf install -y nginx
else
    echo "错误：未找到包管理器"
    exit 1
fi

echo "确保Web目录存在..."
if [ ! -d "$WEB_DIR" ]; then
    echo "创建Web目录: $WEB_DIR"
    mkdir -p "$WEB_DIR"
fi

echo "获取文件..."
if ! get_file "$WEB_DIR/$FILE_NAME"; then
    echo "错误：无法获取文件"
    echo "请检查网络连接或手动下载文件到: $WEB_DIR/$FILE_NAME"
    exit 1
fi

echo "设置文件权限..."
chown www-data:www-data "$WEB_DIR/$FILE_NAME" 2>/dev/null || chown nginx:nginx "$WEB_DIR/$FILE_NAME" 2>/dev/null || chown root:root "$WEB_DIR/$FILE_NAME" 2>/dev/null || true
chmod 644 "$WEB_DIR/$FILE_NAME"

echo "配置Nginx..."
if [ ! -d "/etc/nginx" ]; then
    if [ -d "/usr/local/nginx" ]; then
        echo "检测到从源码安装的Nginx，创建配置目录..."
        mkdir -p /etc/nginx/conf.d
        if [ ! -f "/etc/nginx/nginx.conf" ]; then
            if [ -f "/usr/local/nginx/conf/nginx.conf" ]; then
                cp /usr/local/nginx/conf/nginx.conf /etc/nginx/nginx.conf
            else
                echo "警告：未找到nginx.conf配置文件"
            fi
        fi
    else
    echo ""
    echo "=========================================="
    echo "错误：/etc/nginx 目录不存在"
    echo "Nginx未正确安装"
    echo "=========================================="
    echo "请先安装Nginx："
    echo ""
    echo "1. 修复软件源："
    echo "   sudo sed -i 's/mirrors.tencentyun.com/mirrors.aliyun.com/g' /etc/apt/sources.list"
    echo "   sudo apt-get update"
    echo ""
    echo "2. 安装Nginx："
    echo "   sudo apt-get install -y nginx"
    echo ""
    echo "3. 重新运行部署脚本"
    echo "=========================================="
    exit 1
    fi
fi

if [ -d "/etc/nginx/sites-available" ]; then
    if [ ! -d "/etc/nginx/sites-enabled" ]; then
        mkdir -p /etc/nginx/sites-enabled
    fi
    cat > /etc/nginx/sites-available/customer-data <<EOF
server {
    listen $PORT;
    server_name _;
    
    root $WEB_DIR;
    index $FILE_NAME;
    
    location / {
        try_files \$uri \$uri/ /$FILE_NAME;
    }
    
    location ~* \.(html|css|js|json)$ {
        expires 1h;
        add_header Cache-Control "public";
    }
    
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
}
EOF
    ln -sf /etc/nginx/sites-available/customer-data /etc/nginx/sites-enabled/
else
    if [ ! -d "/etc/nginx/conf.d" ]; then
        mkdir -p /etc/nginx/conf.d
    fi
    cat > /etc/nginx/conf.d/customer-data.conf <<EOF
server {
    listen $PORT;
    server_name _;
    
    root $WEB_DIR;
    index $FILE_NAME;
    
    location / {
        try_files \$uri \$uri/ /$FILE_NAME;
    }
    
    location ~* \.(html|css|js|json)$ {
        expires 1h;
        add_header Cache-Control "public";
    }
    
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
}
EOF
fi

echo "检查Nginx是否可用..."
NGINX_BIN=""
if command -v nginx &> /dev/null; then
    NGINX_BIN=$(which nginx)
elif [ -f "/usr/local/nginx/sbin/nginx" ]; then
    NGINX_BIN="/usr/local/nginx/sbin/nginx"
    ln -sf "$NGINX_BIN" /usr/local/bin/nginx 2>/dev/null || true
    ln -sf "$NGINX_BIN" /usr/bin/nginx 2>/dev/null || true
fi

if [ -n "$NGINX_BIN" ] || command -v nginx &> /dev/null; then
    if [ -n "$NGINX_BIN" ]; then
        echo "Nginx已安装: $($NGINX_BIN -v 2>&1)"
    else
        echo "Nginx已安装: $(nginx -v 2>&1)"
    fi
    echo "测试Nginx配置..."
    if [ -n "$NGINX_BIN" ]; then
        if $NGINX_BIN -t 2>&1; then
            CONFIG_TEST=true
        else
            CONFIG_TEST=false
        fi
    else
        if nginx -t 2>&1; then
            CONFIG_TEST=true
        else
            CONFIG_TEST=false
        fi
    fi
    
    if [ "$CONFIG_TEST" = true ]; then
        echo "Nginx配置测试通过"
    else
        echo "警告：Nginx配置测试失败，但继续部署..."
    fi
    echo "启动Nginx服务..."
    systemctl restart nginx 2>/dev/null || service nginx restart 2>/dev/null || /etc/init.d/nginx restart 2>/dev/null || true
    systemctl enable nginx 2>/dev/null || true
    sleep 2
    if systemctl is-active --quiet nginx || pgrep -x nginx > /dev/null; then
        echo "Nginx服务运行正常"
    else
        echo "警告：Nginx服务可能未启动，请手动检查"
    fi
else
    echo ""
    echo "=========================================="
    echo "错误：Nginx未正确安装"
    echo "=========================================="
    echo "由于软件源问题，Nginx安装失败"
    echo ""
    echo "请手动执行以下命令安装Nginx："
    echo ""
    echo "1. 修复软件源："
    echo "   sudo sed -i 's/mirrors.tencentyun.com/mirrors.aliyun.com/g' /etc/apt/sources.list"
    echo "   sudo sed -i 's/security.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list"
    echo "   sudo apt-get update"
    echo ""
    echo "2. 安装Nginx："
    echo "   sudo apt-get install -y nginx"
    echo ""
    echo "3. 重新运行部署脚本："
    echo "   sudo bash deploy.sh"
    echo ""
    echo "=========================================="
    exit 1
fi

echo "配置防火墙..."
if command -v ufw &> /dev/null; then
    ufw allow $PORT/tcp
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port=$PORT/tcp
    firewall-cmd --reload
fi

echo ""
echo "✅ Nginx部署完成！"

echo ""
echo "=========================================="
echo "部署完成！"
echo ""
SERVER_IP=$(hostname -I | awk '{print $1}')
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(ip addr show | grep "inet " | grep -v 127.0.0.1 | head -1 | awk '{print $2}' | cut -d/ -f1)
fi
echo "服务器IP地址: $SERVER_IP"
echo "访问地址: http://$SERVER_IP:$PORT/$FILE_NAME"
echo ""
echo "=========================================="

