#!/bin/bash
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
FRPS_TOKEN="DFRN2vbG123"
FRP_VERSION="v0.62.1"
FRPS_PORT="7000"
FRPS_UDP_PORT="7001"
FRPS_KCP_PORT="7000"
FRPS_DASHBOARD_PORT="31410"
FRPS_DASHBOARD_USER="admin"
FRPS_DASHBOARD_PWD="yao581581"
SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')

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

uninstall_frps() {
    systemctl stop frps >/dev/null 2>&1
    systemctl disable frps >/dev/null 2>&1
    rm -f /etc/systemd/system/frps.service
    rm -rf /usr/local/frp /etc/frp
    systemctl daemon-reload >/dev/null 2>&1
}

install_frps() {
    uninstall_frps
    echo -e "${BLUE}» 下载 FRPS 服务端...${NC}"
    local FRP_NAME="frp_${FRP_VERSION#v}_linux_amd64"
    local FRP_FILE="${FRP_NAME}.tar.gz"
    cd /usr/local/ || {
        echo -e "${RED}✗ 无法进入 /usr/local/ 目录${NC}"
        return 1
    }
    echo -e "${CYAN}  正在下载: ${FRP_FILE}${NC}" >/dev/null 2>&1
    wget -q "https://github.com/fatedier/frp/releases/download/${FRP_VERSION}/${FRP_FILE}" -O "${FRP_FILE}" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ FRP 下载失败！${NC}"
        return 1
    fi
    echo -e "${BLUE}» 解压 FRPS 安装包...${NC}"
    if ! tar -zxf "${FRP_FILE}"; then
        echo -e "${RED}✗ FRP 解压失败！${NC}"
        rm -f "${FRP_FILE}"
        return 1
    fi
    echo -e "${BLUE}» 安装 FRPS 可执行文件...${NC}"
    cd "${FRP_NAME}" 
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ 无法进入 FRP 目录！${NC}"
        return 1
    fi
    rm -f frpc*
    mkdir -p /usr/local/frp
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ 创建 /usr/local/frp 目录失败！${NC}"
        return 1
    fi
    if ! cp frps /usr/local/frp/; then
        echo -e "${RED}✗ 拷贝 frps 可执行文件失败！${NC}"
        return 1
    fi
    chmod +x /usr/local/frp/frps
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ 设置 frps 可执行权限失败！${NC}"
        return 1
    fi
    echo -e "${BLUE}» 创建 FRPS 配置文件...${NC}"
    mkdir -p /etc/frp
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ 创建 /etc/frp 目录失败！${NC}"
        return 1
    fi
    cat > /etc/frp/frps.toml << EOF
bindAddr = "0.0.0.0"
bindPort = ${FRPS_PORT}
kcpBindPort = ${FRPS_KCP_PORT}
auth.method = "token"
auth.token = "${FRPS_TOKEN}"
webServer.addr = "0.0.0.0"
webServer.port = ${FRPS_DASHBOARD_PORT}
webServer.user = "${FRPS_DASHBOARD_USER}"
webServer.password = "${FRPS_DASHBOARD_PWD}"
enablePrometheus = true
transport.tls.force = true
EOF
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ 写入 frps.toml 配置文件失败！${NC}"
        return 1
    fi
    echo -e "${BLUE}» 创建 FRPS 服务单元...${NC}"
    cat > /etc/systemd/system/frps.service << EOF
[Unit]
Description=Frp Server Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/frp/frps -c /etc/frp/frps.toml
Restart=always
RestartSec=20

[Install]
WantedBy=multi-user.target
EOF
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ 写入 frps.service 文件失败！${NC}"
        return 1
    fi
    echo -e "${BLUE}» 配置防火墙规则...${NC}"
    if command -v ufw >/dev/null 2>&1; then
        ufw allow ${FRPS_PORT}/tcp >/dev/null 2>&1
        ufw allow ${FRPS_DASHBOARD_PORT}/tcp >/dev/null 2>&1
        echo -e "${CYAN}  └─ 已添加 UFW 防火墙规则${NC}"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=${FRPS_PORT}/tcp >/dev/null 2>&1
        firewall-cmd --permanent --add-port=${FRPS_DASHBOARD_PORT}/tcp >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
        echo -e "${CYAN}  └─ 已添加 firewalld 防火墙规则${NC}"
    fi
    systemctl daemon-reload
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ 重新加载 systemd 配置失败！${NC}"
        return 1
    fi
    systemctl enable frps >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ 启用 frps 服务失败！${NC}"
        return 1
    fi
    echo -e "${CYAN}  └─ 启用并启动 FRPS 服务...${NC}"
    systemctl start frps >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ 启动 frps 服务失败！${NC}"
        journalctl -u frps.service --no-pager -n 20
        return 1
    fi
    if systemctl is-active frps >/dev/null 2>&1; then
      echo -e "${CYAN}  └─ FRPS 服务已成功启动...${NC}"
    else
        echo -e "${RED}✗ FRPS服务启动失败${NC}"
        return 1
    fi
    rm -f /usr/local/${FRP_FILE}
    rm -rf /usr/local/${FRP_NAME}
}

add_cron_job() {
    local cron_entry='24 15 24 * * find /usr/local -type f -name "*.log" -delete'
    (crontab -l 2>/dev/null | grep -v -F "$cron_entry") | crontab -
    (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
}

cleanup() {
    rm -rf /usr/local/frp_*
}

show_results() {
    echo -e "${YELLOW}╔═════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║               服务信息摘要                      ║${NC}"
    echo -e "${YELLOW}╚═════════════════════════════════════════════════╝${NC}"
    echo -e "${WHITE}${BOLD}▎ FRPS 服务信息${NC}"
    SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
    local frps_status=$(systemctl status frps --no-pager | grep -E 'Active:' | sed 's/^\s*Active: //g')
    echo -e "  ${BOLD}• 服务状态:${NC}   ${WHITE}${frps_status}${NC}"
    echo -e "  ${BOLD}• 服务器地址:${NC}   ${WHITE}${SERVER_IP}${NC}"
    echo -e "  ${BOLD}• FRPS 端口:${NC}    ${WHITE}${FRPS_PORT}${NC}"
    echo -e "  ${BOLD}• FRPS 令牌:${NC}    ${WHITE}${FRPS_TOKEN}${NC}"
    echo -e "  ${BOLD}• Web 管理界面:${NC} ${WHITE}http://${SERVER_IP}:${FRPS_DASHBOARD_PORT}${NC}"
}

show_menu() {
    echo -e "${YELLOW}╔═════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║                 FRPS 管理面板                  ║${NC}"
    echo -e "${YELLOW}╚═════════════════════════════════════════════════╝${NC}"
    echo -e "${LIGHT_GREEN}请选择要执行的操作:${NC}"
    echo -e "  ${BLUE}1)${NC} 安装 FRPS 服务"
    echo -e "  ${BLUE}2)${NC} 卸载 FRPS 服务" 
    echo -e "  ${BLUE}3)${NC} 退出脚本"
    echo -e "${YELLOW}═════════════════════════════════════════════════${NC}"
    echo -n "请输入选项 [1-3]: "
    read -r choice
    case "$choice" in
        1)
            check_root
            install_frps
            add_cron_job
            cleanup
            show_results
            ;;
        2)
            check_root
            uninstall_frps
            echo -e "${SUCCESS}✓ FRPS 服务已成功卸载。${NC}"
            sleep 2
            ;;
        3)
            echo -e "${GREEN}退出脚本。${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请输入 1-3 之间的数字。${NC}"
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
