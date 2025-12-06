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
if command -v apt-get &> /dev/null; then
    echo "检查Nginx是否已安装..."
    if command -v nginx &> /dev/null; then
        echo "Nginx已安装，版本: $(nginx -v 2>&1)"
    else
        echo "更新软件包列表（忽略404错误）..."
        apt-get update 2>&1 | grep -v "404  Not Found" | grep -v "Failed to fetch" || true
        
        echo "安装Nginx（忽略缺失的包）..."
        if apt-get install -y --fix-missing nginx 2>&1 | grep -v "404  Not Found" | grep -v "Failed to fetch"; then
            echo "Nginx安装完成"
        else
            echo ""
            echo "=========================================="
            echo "Nginx安装遇到软件源问题"
            echo "=========================================="
            echo "正在尝试修复软件源..."
            
            if [ -f /etc/apt/sources.list ]; then
                echo "备份当前sources.list..."
                cp /etc/apt/sources.list /etc/apt/sources.list.bak
                
                echo "切换到阿里云镜像源..."
                sed -i 's|mirrors.tencentyun.com|mirrors.aliyun.com|g' /etc/apt/sources.list
                sed -i 's|security.debian.org|mirrors.aliyun.com|g' /etc/apt/sources.list 2>/dev/null || true
                
                echo "更新软件包列表..."
                apt-get update 2>&1 | grep -v "404  Not Found" | grep -v "Failed to fetch" || true
                
                echo "重新尝试安装Nginx..."
                if apt-get install -y nginx 2>&1 | grep -v "404  Not Found" | grep -v "Failed to fetch"; then
                    echo "Nginx安装成功"
                else
                    echo "安装仍然失败，检查Nginx是否可用..."
                    if command -v nginx &> /dev/null; then
                        echo "Nginx已可用，继续部署"
                    else
                        echo ""
                        echo "请手动安装Nginx："
                        echo "  sudo apt-get update"
                        echo "  sudo apt-get install -y nginx"
                        echo ""
                        read -p "是否继续部署（如果Nginx已安装）？[y/N]: " continue_choice
                        if [[ ! $continue_choice =~ ^[Yy]$ ]]; then
                            exit 1
                        fi
                    fi
                fi
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
    echo "错误：/etc/nginx 目录不存在，Nginx可能未正确安装"
    echo "请手动安装Nginx: sudo apt-get install -y nginx"
    exit 1
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
if command -v nginx &> /dev/null; then
    echo "Nginx已安装: $(nginx -v 2>&1)"
    echo "测试Nginx配置..."
    if nginx -t 2>&1; then
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

