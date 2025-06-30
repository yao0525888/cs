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
ADMIN_PASSWORD="Qaz123456!"
FRP_VERSION="v0.62.1"
FRPS_PORT="7006"
FRPS_KCP_PORT="7006"
FRPS_DASHBOARD_PORT="7007"
FRPS_TOKEN="DFRN2vbG123"
FRPS_DASHBOARD_USER="admin"
FRPS_DASHBOARD_PWD="yao581581"
SILENT_MODE=true
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

uninstall_all() {
    echo -e "${BLUE}» 卸载 FRPS 服务...${NC}"
    uninstall_frps
    echo -e "${BLUE}» 清理临时文件...${NC}"
    cleanup 
    systemctl daemon-reload >/dev/null 2>&1
    echo -e "${SUCCESS}✓ 所有服务已成功卸载。${NC}"
    sleep 2
}

show_results() {
    local frps_status=$(systemctl is-active frps 2>/dev/null || echo "inactive")
    SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
    echo -e "${YELLOW}>>> 服务状态${NC}"
    echo -e "FRPS 服务: ${WHITE}${frps_status}${NC}"
    echo -e "${YELLOW}>>> 服务器信息${NC}"
    echo -e "服务器 IP: ${WHITE}${SERVER_IP}${NC}"
    echo -e "FRP 版本: ${WHITE}${FRP_VERSION}${NC}"
    echo -e "${YELLOW}>>> 连接信息${NC}"
    echo -e "FRPS 端口: ${WHITE}${FRPS_PORT}/tcp${NC}"
    echo -e "FRPS KCP 端口: ${WHITE}${FRPS_KCP_PORT}/udp${NC}"
    echo -e "FRPS 令牌: ${WHITE}${FRPS_TOKEN}${NC}" 
    echo -e "${YELLOW}>>> 管理界面${NC}"
    echo -e "管理界面地址: ${WHITE}http://${SERVER_IP}:${FRPS_DASHBOARD_PORT}${NC}"
    echo -e "管理用户名: ${WHITE}${FRPS_DASHBOARD_USER}${NC}"
    echo -e "管理密码: ${WHITE}${FRPS_DASHBOARD_PWD}${NC}"
}

install_frp() {
    check_root
    uninstall_frps
    install_frps
    add_cron_job
    cleanup
    echo -e "${SUCCESS}✓ FRPS服务安装并启动成功！${NC}"
    show_results
    sleep 2
    exit 0
}

show_menu() {
    echo -e "${YELLOW}╔═════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║                   PiNetwork                     ║${NC}"
    echo -e "${YELLOW}╚═════════════════════════════════════════════════╝${NC}"
    echo -e "${LIGHT_GREEN}请选择要执行的操作:${NC}"
    echo -e "  ${BLUE}1)${NC} 安装 FRPS服务"
    echo -e "  ${BLUE}2)${NC} 卸载 FRPS服务" 
    echo -e "  ${BLUE}3)${NC} 退出脚本"
    echo -n "请输入选项 [1-3]: "
    read -r choice
    case "$choice" in
        1)
            check_root
            install_frp
            exit 0
            ;;
        2)
            check_root
            uninstall_all
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
