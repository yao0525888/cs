#!/bin/bash

# ========================================
# 配置区域 - 请修改以下配置
# ========================================
BACKEND_URL="http://43.153.43.189:3000"
API_KEY="a1c4afca2909a69d69aa0708f737d6f3c8a2b60c6c620c3b60869360234bcd34"
# ========================================

LIGHT_GREEN='\033[1;32m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'
WHITE='\033[1;37m'
CYAN='\033[0;36m'
BOLD='\033[1m'
SUCCESS="${BOLD}${LIGHT_GREEN}"

log_info() {
    echo -e "${NC}$1"
}

log_step() {
    echo -e "${NC}$1"
}

log_success() {
    echo -e "${NC}$1"
}

log_error() {
    echo -e "${NC}$1"
    exit 1
}

log_sub_step() {
    echo -e "${NC}$1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 sudo 或 root 权限运行脚本"
    fi
}

check_api_key() {
    if [ -z "$API_KEY" ]; then
        log_error "请设置 API_KEY 环境变量"
    fi
}

call_api() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    
    if [ "$method" = "GET" ]; then
        curl -s -X GET \
            -H "X-API-Key: $API_KEY" \
            -H "Content-Type: application/json" \
            "${BACKEND_URL}${endpoint}"
    else
        curl -s -X POST \
            -H "X-API-Key: $API_KEY" \
            -H "Content-Type: application/json" \
            -d "$data" \
            "${BACKEND_URL}${endpoint}"
    fi
}

install_softether() {
    echo -e "${BLUE}» 安装 SoftEther VPN...${NC}"
    local response=$(call_api "POST" "/api/install/softether" "{}")
    
    if echo "$response" | grep -q '"success":true'; then
        echo -e "${SUCCESS}✓ SoftEther VPN 安装成功${NC}"
    else
        echo -e "${RED}✗ SoftEther VPN 安装失败${NC}"
        echo "$response"
        return 1
    fi
}

install_frps() {
    echo -e "${BLUE}» 安装 FRPS 服务...${NC}"
    local response=$(call_api "POST" "/api/install/frps" "{}")
    
    if echo "$response" | grep -q '"success":true'; then
        echo -e "${SUCCESS}✓ FRPS 安装成功${NC}"
    else
        echo -e "${RED}✗ FRPS 安装失败${NC}"
        echo "$response"
        return 1
    fi
}

uninstall_all() {
    echo -e "${YELLOW}╔═════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║               卸载所有服务                      ║${NC}"
    echo -e "${YELLOW}╚═════════════════════════════════════════════════╝${NC}"
    
    echo -e "${BLUE}» 请求卸载所有服务...${NC}"
    local response=$(call_api "POST" "/api/uninstall/all" "{}")
    
    if echo "$response" | grep -q '"success":true'; then
        echo -e "${SUCCESS}✓ 所有服务已成功卸载${NC}"
    else
        echo -e "${RED}✗ 卸载失败${NC}"
        echo "$response"
        return 1
    fi
    sleep 2
}

show_status() {
    echo -e "${YELLOW}╔═════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║               服务信息概要                      ║${NC}"
    echo -e "${YELLOW}╚═════════════════════════════════════════════════╝${NC}"
    echo ""
    
    local response=$(call_api "GET" "/api/status" "")
    local config=$(call_api "GET" "/api/config/full" "")
    
    local vpn_status=$(echo "$response" | grep -o '"vpn":[^,}]*' | cut -d':' -f2)
    local frps_status=$(echo "$response" | grep -o '"frps":[^,}]*' | cut -d':' -f2)
    
    local server_ip=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
    local vpn_hub=$(echo "$config" | grep -o '"vpn_hub":"[^"]*"' | cut -d'"' -f4)
    local vpn_user=$(echo "$config" | grep -o '"vpn_user":"[^"]*"' | cut -d'"' -f4)
    local vpn_password=$(echo "$config" | grep -o '"vpn_password":"[^"]*"' | cut -d'"' -f4)
    local admin_password=$(echo "$config" | grep -o '"admin_password":"[^"]*"' | cut -d'"' -f4)
    local frp_port=$(echo "$config" | grep -o '"frp_port":"[^"]*"' | cut -d'"' -f4)
    local frp_dashboard_port=$(echo "$config" | grep -o '"frp_dashboard_port":"[^"]*"' | cut -d'"' -f4)
    local frp_token=$(echo "$config" | grep -o '"frp_token":"[^"]*"' | cut -d'"' -f4)
    local frp_dashboard_user=$(echo "$config" | grep -o '"frp_dashboard_user":"[^"]*"' | cut -d'"' -f4)
    local frp_dashboard_pwd=$(echo "$config" | grep -o '"frp_dashboard_pwd":"[^"]*"' | cut -d'"' -f4)
    
    echo -e "${BOLD}FRPS 服务信息${NC}"
    if [ "$frps_status" = "true" ]; then
        echo -e "  • 服务状态:     ${GREEN}active (running) since $(date '+%a %Y-%m-%d %H:%M:%S %Z')${NC}"
    else
        echo -e "  • 服务状态:     ${RED}inactive${NC}"
    fi
    echo -e "  • 服务器地址:   ${server_ip}"
    echo -e "  • FRPS 端口:    ${frp_port}"
    echo -e "  • FRPS 令牌:    ${frp_token}"
    echo -e "  • Web 管理界面: http://${server_ip}:${frp_dashboard_port}"
    echo ""
    
    echo -e "${BOLD}SoftEtherVPN 服务信息${NC}"
    if [ "$vpn_status" = "true" ]; then
        echo -e "  • 服务状态:     ${GREEN}active (running) since $(date '+%a %Y-%m-%d %H:%M:%S %Z')${NC}"
    else
        echo -e "  • 服务状态:     ${RED}inactive${NC}"
    fi
    echo -e "  • 服务器地址:   ${server_ip}"
    echo -e "  • VPN Hub:      ${vpn_hub}"
    echo -e "  • VPN 用户名:   ${vpn_user}"
    echo -e "  • VPN 密码:     ${vpn_password}"
    echo -e "  • 管理密码:     ${admin_password}!"
}

install_softether_and_frps() {
    check_root
    check_api_key
    
    if ! install_softether; then
        echo -e "${RED}✗ SoftEther VPN 安装失败，继续安装 FRPS...${NC}"
    fi
    
    install_frps
    
    echo -e "${SUCCESS}✓ SoftEtherVPN 和 FRPS 安装完成${NC}"
    echo ""
    show_status
    exit 0
}

show_menu() {
    echo -e "${YELLOW}╔═════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║               Pi Network 管理面板              ║${NC}"
    echo -e "${YELLOW}║               (客户端版本)                     ║${NC}"
    echo -e "${YELLOW}╚═════════════════════════════════════════════════╝${NC}"
    echo -e "${LIGHT_GREEN}请选择要执行的操作:${NC}"
    echo -e "  ${BLUE}1)${NC} 安装 SoftEtherVPN 和 FRPS 服务"
    echo -e "  ${BLUE}2)${NC} 卸载所有服务" 
    echo -e "  ${BLUE}3)${NC} 查看服务状态"
    echo -e "  ${BLUE}4)${NC} 退出脚本"
    echo -e "${YELLOW}═════════════════════════════════════════════════${NC}"
    echo -n "请输入选项 [1-4]: "
    read -r choice
    case "$choice" in
        1)
            check_root
            check_api_key
            install_softether_and_frps
            ;;
        2)
            check_root
            check_api_key
            uninstall_all
            ;;
        3)
            check_api_key
            show_status
            echo ""
            read -p "按回车键继续..."
            ;;
        4)
            echo -e "${GREEN}退出脚本。${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请输入 1-4 之间的数字。${NC}"
            ;;
    esac
}

main() {
    while true; do
        clear
        show_menu
    done
}

main
