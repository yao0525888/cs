#!/bin/bash

echo "=========================================="
echo "  客户数据管理系统 - Linux部署脚本"
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
    echo "正在从GitHub下载文件..."
    if command -v wget &> /dev/null; then
        wget -q "$GITHUB_URL" -O "$target_path"
    elif command -v curl &> /dev/null; then
        curl -sL "$GITHUB_URL" -o "$target_path"
    else
        echo "错误：未找到wget或curl，无法下载文件"
        echo "请手动安装: sudo apt install wget 或 sudo yum install wget"
        return 1
    fi
    
    if [ -f "$target_path" ] && [ -s "$target_path" ]; then
        echo "文件下载成功"
        return 0
    else
        echo "文件下载失败"
        return 1
    fi
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
if command -v apt-get &> /dev/null; then
    echo "更新软件包列表..."
    apt-get update 2>&1 | grep -v "404  Not Found" || true
    
    echo "检查Nginx是否已安装..."
    if command -v nginx &> /dev/null; then
        echo "Nginx已安装，跳过安装步骤"
    else
        echo "安装Nginx..."
        if ! apt-get install -y nginx 2>&1 | tee /tmp/nginx_install.log; then
            echo "安装过程中出现错误，尝试使用--fix-missing选项..."
            if ! apt-get install -y --fix-missing nginx 2>&1 | grep -v "404  Not Found"; then
                echo "尝试仅从主源安装（跳过security源）..."
                apt-get install -y -o Acquire::http::AllowRedirect=false nginx || {
                    echo ""
                    echo "=========================================="
                    echo "安装Nginx时遇到软件源问题"
                    echo "=========================================="
                    echo "请尝试以下方法之一："
                    echo ""
                    echo "方法1：修复软件源"
                    echo "  sudo sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list"
                    echo "  sudo sed -i 's/security.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list"
                    echo "  sudo apt-get update"
                    echo "  sudo apt-get install -y nginx"
                    echo ""
                    echo "方法2：使用官方源"
                    echo "  sudo sed -i 's/mirrors.tencentyun.com/deb.debian.org/g' /etc/apt/sources.list"
                    echo "  sudo apt-get update"
                    echo "  sudo apt-get install -y nginx"
                    echo ""
                    echo "方法3：手动安装（如果Nginx已部分安装）"
                    echo "  检查Nginx是否可用: nginx -v"
                    echo "  如果可用，可以继续部署"
                    echo "=========================================="
                    echo ""
                    read -p "是否继续部署（如果Nginx已安装）？[y/N]: " continue_choice
                    if [[ ! $continue_choice =~ ^[Yy]$ ]]; then
                        exit 1
                    fi
                }
            fi
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

echo "获取文件..."
if ! get_file "$WEB_DIR/$FILE_NAME"; then
    echo "错误：无法获取文件"
    exit 1
fi
chown www-data:www-data "$WEB_DIR/$FILE_NAME" 2>/dev/null || chown nginx:nginx "$WEB_DIR/$FILE_NAME" 2>/dev/null || true
chmod 644 "$WEB_DIR/$FILE_NAME"

echo "配置Nginx..."
if [ -d "/etc/nginx/sites-available" ]; then
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
    cat > /etc/nginx/conf.d/customer-data.conf <<EOF
server {
    listen $PORT;
    server_name _;
    
    root $WEB_DIR;
    index $FILE_NAME;
    
    location / {
        try_files \$uri \$uri/ /$FILE_NAME;
    }
}
EOF
fi

if command -v nginx &> /dev/null; then
    echo "测试Nginx配置..."
    nginx -t || {
        echo "警告：Nginx配置测试失败，但继续部署..."
    }
    echo "启动Nginx服务..."
    systemctl restart nginx || service nginx restart || true
    systemctl enable nginx 2>/dev/null || true
else
    echo "错误：Nginx未正确安装，无法继续"
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

