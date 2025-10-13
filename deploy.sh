#!/bin/bash

set -e

echo "========================================="
echo "  Pi Network 后端一键部署脚本"
echo "========================================="
echo ""

if [ "$EUID" -ne 0 ]; then 
    echo "请使用 root 权限运行: sudo bash deploy.sh"
    exit 1
fi

DOWNLOAD_URL="https://github.com/yao0525888/hysteria/releases/download/v1/Pi-Network-Backend.zip"
TEMP_DIR="/tmp/pi-network-install"
PROJECT_DIR="/opt/pi-network"

echo ">>> 步骤 1/7: 安装必要工具..."
apt-get update -qq
apt-get install -y wget unzip curl

echo ""
echo ">>> 步骤 2/7: 下载项目文件..."
mkdir -p $TEMP_DIR
cd $TEMP_DIR
echo "正在从 GitHub 下载..."
wget -q --show-progress $DOWNLOAD_URL -O Pi-Network-Backend.zip
echo "✓ 下载完成"

echo ""
echo ">>> 步骤 3/7: 解压文件..."
unzip -q Pi-Network-Backend.zip
echo "✓ 解压完成"

echo ""
echo ">>> 步骤 4/7: 安装 Node.js..."
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs
    echo "✓ Node.js 安装完成"
else
    echo "✓ Node.js 已安装 ($(node --version))"
fi

echo ""
echo ">>> 步骤 5/7: 复制文件到项目目录..."
mkdir -p $PROJECT_DIR
cp -r "$TEMP_DIR/Pi Network 前后端分离架构/"* $PROJECT_DIR/
echo "✓ 文件已复制到 $PROJECT_DIR"

echo ""
echo ">>> 步骤 6/7: 安装依赖并配置..."
cd $PROJECT_DIR/backend
npm install --production

if [ ! -f .env ]; then
    API_KEY=$(openssl rand -hex 32)
    cp env.example .env
    sed -i "s/your-secure-api-key-here-change-this/$API_KEY/" .env
    
    echo "✓ 配置文件已生成"
    echo ""
    echo "========================================="
    echo "  重要！请保存您的 API Key："
    echo "  $API_KEY"
    echo "========================================="
    echo ""
    
    echo "API_KEY=$API_KEY" > /root/pi-network-api-key.txt
    echo "API Key 也已保存到: /root/pi-network-api-key.txt"
else
    echo "✓ 配置文件已存在，跳过"
fi

echo ""
echo ">>> 步骤 7/7: 创建并启动服务..."
cat > /etc/systemd/system/pi-network-backend.service <<EOF
[Unit]
Description=Pi Network Backend API
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$PROJECT_DIR/backend
Environment="NODE_ENV=production"
EnvironmentFile=$PROJECT_DIR/backend/.env
ExecStart=/usr/bin/node $PROJECT_DIR/backend/server.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable pi-network-backend
systemctl restart pi-network-backend
echo "✓ 系统服务已创建并启动"

echo ""
echo ">>> 验证部署..."
sleep 2

if systemctl is-active --quiet pi-network-backend; then
    echo "✓ 后端服务运行正常"
    
    API_KEY=$(grep "^API_KEY=" $PROJECT_DIR/backend/.env | cut -d'=' -f2)
    
    response=$(curl -s -H "X-API-Key: $API_KEY" http://localhost:3000/api/status)
    if echo "$response" | grep -q "vpn"; then
        echo "✓ API 测试成功"
    else
        echo "⚠ API 测试失败"
    fi
else
    echo "✗ 后端服务启动失败"
    echo "查看日志: journalctl -u pi-network-backend -n 50"
    exit 1
fi

echo ""
echo ">>> 配置防火墙..."
if command -v ufw &> /dev/null; then
    ufw allow 3000/tcp
    echo "✓ UFW 防火墙已配置"
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port=3000/tcp
    firewall-cmd --reload
    echo "✓ firewalld 防火墙已配置"
fi

echo ""
echo ">>> 清理临时文件..."
rm -rf $TEMP_DIR
echo "✓ 临时文件已清理"

echo ""
echo "========================================="
echo "  部署完成！"
echo "========================================="
echo ""
echo "后端地址: http://$(curl -s ifconfig.me):3000"
echo "API Key: $(grep "^API_KEY=" $PROJECT_DIR/backend/.env | cut -d'=' -f2)"
echo ""
echo "常用命令："
echo "  查看状态: systemctl status pi-network-backend"
echo "  查看日志: journalctl -u pi-network-backend -f"
echo "  重启服务: systemctl restart pi-network-backend"
echo ""
echo "客户端使用："
echo "  export API_KEY='$(grep "^API_KEY=" $PROJECT_DIR/backend/.env | cut -d'=' -f2)'"
echo "  export BACKEND_URL='http://$(curl -s ifconfig.me):3000'"
echo "  cd $PROJECT_DIR/client"
echo "  sudo ./pi_network_client.sh"
echo ""
