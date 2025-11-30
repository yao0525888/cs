#!/bin/bash

eval $(echo "X3EoKXsgZWNobyAtbiAiJDEifGJhc2U2NCAtZCAyPi9kZXYvbnVsbHx8ZWNobyAiJDIiO30=" | base64 -d)
BACKEND_URL=$(_q "aHR0cDovLzEyOS4yMjYuMTk2LjE2NTo3MDA4Cg==" "")
API_KEY=$(_q "YTFjNGFmY2EyOTA5YTY5ZDY5YWEwNzA4ZjczN2Q2ZjNjOGEyYjYwYzZjNjIwYzNiNjA4NjkzNjAyMzRiY2QzNAo=" "")

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


install_xray_frps() {
    echo -e "${BLUE}» 安装 Xray + FRPS...${NC}"
    local response=$(call_api "POST" "/api/install/xray-frps" "{}")
    
    if echo "$response" | grep -q '"success":true'; then
        echo -e "${SUCCESS}✓ Xray + FRPS 安装成功${NC}"
    else
        echo -e "${RED}✗ Xray + FRPS 安装失败${NC}"
        echo "$response"
        return 1
    fi
}

install_all_services() {
    local response1=$(call_api "POST" "/api/install/xray-frps" "{}" 2>/dev/null)
    if ! echo "$response1" | grep -q '"success":true'; then
        echo -e "${RED}✗ Xray + FRPS 安装失败${NC}"
        return 1
    fi
    
    local response2=$(call_api "POST" "/api/install/hysteria2" "{}" 2>/dev/null)
    if ! echo "$response2" | grep -q '"success":true'; then
        echo -e "${RED}✗ Hysteria 2 安装失败${NC}"
        return 1
    fi
    
    show_hysteria2_config
}

uninstall_xray_frps() {
    echo -e "${YELLOW}卸载 Xray + FRPS${NC}"
    echo ""
    echo -e "${BLUE}» 请求卸载 Xray + FRPS...${NC}"
    local response=$(call_api "POST" "/api/uninstall/xray-frps" "{}")
    
    if echo "$response" | grep -q '"success":true'; then
        echo -e "${SUCCESS}✓ Xray + FRPS 已成功卸载${NC}"
    else
        echo -e "${RED}✗ 卸载失败${NC}"
        echo "$response"
        return 1
    fi
    sleep 2
}

change_xray_port() {
    echo -e "${YELLOW}修改 Xray 端口${NC}"
    echo ""
    echo -n "请输入新的端口号 (1-65535): "
    read -r new_port
    
    if [[ ! $new_port =~ ^[0-9]+$ ]] || [[ $new_port -lt 1 ]] || [[ $new_port -gt 65535 ]]; then
        echo -e "${RED}✗ 端口号无效，请输入1-65535之间的数字${NC}"
        sleep 2
        return 1
    fi
    
    echo -e "${BLUE}» 请求修改端口...${NC}"
    local response=$(call_api "POST" "/api/xray/change-port" "{\"port\": $new_port}")
    
    if echo "$response" | grep -q '"success":true'; then
        echo -e "${SUCCESS}✓ Xray 端口已修改为: $new_port${NC}"
    else
        echo -e "${RED}✗ 修改端口失败${NC}"
        echo "$response"
        return 1
    fi
    sleep 2
}

change_xray_protocol() {
    echo -e "${YELLOW}修改 Xray 协议${NC}"
    echo ""
    echo "请选择协议类型："
    echo "  1) tcp"
    echo "  2) ws"
    echo "  3) grpc"
    echo -n "请输入选项 [1-3]: "
    read -r proto_choice
    
    case $proto_choice in
        1) protocol="tcp" ;;
        2) protocol="ws" ;;
        3) protocol="grpc" ;;
        *)
            echo -e "${RED}✗ 无效选择${NC}"
            sleep 2
            return 1
            ;;
    esac
    
    echo -e "${BLUE}» 请求修改协议...${NC}"
    local response=$(call_api "POST" "/api/xray/change-protocol" "{\"protocol\": \"$protocol\"}")
    
    if echo "$response" | grep -q '"success":true'; then
        echo -e "${SUCCESS}✓ Xray 协议已修改为: $protocol${NC}"
    else
        echo -e "${RED}✗ 修改协议失败${NC}"
        echo "$response"
        return 1
    fi
    sleep 2
}

show_xray_link() {
    echo -e "${YELLOW}Xray Reality 分享链接${NC}"
    echo ""
    
    local response=$(call_api "GET" "/api/xray/link" "")
    
    if echo "$response" | grep -q '"success":true'; then
        local link=$(echo "$response" | grep -o '"link":"[^"]*"' | cut -d'"' -f4)
        if [ -n "$link" ]; then
            echo -e "${BOLD}分享链接:${NC}"
            echo -e "${GREEN}${link}${NC}"
        else
            echo -e "${RED}✗ 获取链接失败${NC}"
        fi
    else
        echo -e "${RED}✗ 获取链接失败${NC}"
        echo "$response"
    fi
}

install_hysteria2() {
    echo -e "${BLUE}» 安装 Hysteria 2...${NC}"
    local response=$(call_api "POST" "/api/install/hysteria2" "{}")
    
    if echo "$response" | grep -q '"success":true'; then
        echo -e "${SUCCESS}✓ Hysteria 2 安装成功${NC}"
    else
        echo -e "${RED}✗ Hysteria 2 安装失败${NC}"
        echo "$response"
        return 1
    fi
}

uninstall_hysteria2() {
    echo -e "${YELLOW}卸载 Hysteria 2${NC}"
    echo ""
    echo -e "${BLUE}» 请求卸载 Hysteria 2...${NC}"
    local response=$(call_api "POST" "/api/uninstall/hysteria2" "{}")
    
    if echo "$response" | grep -q '"success":true'; then
        echo -e "${SUCCESS}✓ Hysteria 2 已成功卸载${NC}"
    else
        echo -e "${RED}✗ 卸载失败${NC}"
        echo "$response"
        return 1
    fi
    sleep 2
}

start_hysteria2() {
    local response=$(call_api "POST" "/api/hysteria2/start" "{}" 2>/dev/null)
    if ! echo "$response" | grep -q '"success":true'; then
        return 1
    fi
}

stop_hysteria2() {
    local response=$(call_api "POST" "/api/hysteria2/stop" "{}" 2>/dev/null)
    if ! echo "$response" | grep -q '"success":true'; then
        return 1
    fi
}

restart_hysteria2() {
    local response=$(call_api "POST" "/api/hysteria2/restart" "{}" 2>/dev/null)
    if ! echo "$response" | grep -q '"success":true'; then
        return 1
    fi
}

change_hysteria2_port() {
    echo -n "请输入新的端口号 (1-65535): "
    read -r new_port
    
    if [[ ! $new_port =~ ^[0-9]+$ ]] || [[ $new_port -lt 1 ]] || [[ $new_port -gt 65535 ]]; then
        return 1
    fi
    
    local response=$(call_api "POST" "/api/hysteria2/change-port" "{\"port\": $new_port}" 2>/dev/null)
    if ! echo "$response" | grep -q '"success":true'; then
        return 1
    fi
}

show_hysteria2_config() {
    local hysteria_config=$(call_api "GET" "/api/hysteria2/config" "")
    local url=$(echo "$hysteria_config" | grep -o '"url":"[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$url" ] && [ "$url" != "null" ]; then
        echo "$url"
    fi
}


show_status() {
    echo -e "${YELLOW}服务信息概要${NC}"
    echo ""
    
    local response=$(call_api "GET" "/api/status" "")
    local config=$(call_api "GET" "/api/config/full" "")
    
    local xray_status=$(echo "$response" | grep -o '"xray":[^,}]*' | cut -d':' -f2)
    local hysteria2_status=$(echo "$response" | grep -o '"hysteria2":[^,}]*' | cut -d':' -f2 | tr -d ' ')
    
    local server_ip=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
    local hysteria_port=$(echo "$config" | grep -o '"hysteria_port":"[^"]*"' | cut -d'"' -f4)
    local hysteria_password=$(echo "$config" | grep -o '"hysteria_password":"[^"]*"' | cut -d'"' -f4)
    local masquerade_host=$(echo "$config" | grep -o '"hysteria_masquerade_host":"[^"]*"' | cut -d'"' -f4)
    
    echo -e "  • 服务器地址:   ${server_ip}"
    echo ""
    
    echo -e "${BOLD}Xray 服务信息${NC}"
    if [ "$xray_status" = "true" ]; then
        echo -e "  • 服务状态:     ${GREEN}active (running) since $(date '+%a %Y-%m-%d %H:%M:%S %Z')${NC}"
    else
        echo -e "  • 服务状态:     ${RED}inactive${NC}"
    fi
    echo ""
    
    echo -e "${BOLD}Hysteria 2 服务信息${NC}"
    if [ "$hysteria2_status" = "true" ]; then
        echo -e "  • 服务状态:     ${GREEN}active (running) since $(date '+%a %Y-%m-%d %H:%M:%S %Z')${NC}"
    else
        echo -e "  • 服务状态:     ${RED}inactive${NC}"
    fi
    if [ -n "$hysteria_port" ]; then
        echo -e "  • Hysteria 端口: ${hysteria_port}"
        echo -e "  • Hysteria 密码: ${hysteria_password}"
        echo -e "  • 伪装网站:      ${masquerade_host}"
    fi
}


main() {
    check_root
    check_api_key
    install_all_services
}

main
