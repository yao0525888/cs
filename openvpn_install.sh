#!/bin/bash
RED="\033[31m"
GREEN="\033[32m\033[01m"
YELLOW="\033[33m\033[01m"
BLUE="\033[34m"
CYAN="\033[36m"
PURPLE="\033[35m"
WHITE="\033[37m"
BOLD="\033[1m"
PLAIN="\033[0m"

log_info() { echo -e "${CYAN}[$(date "+%Y-%m-%d %H:%M:%S")] [ℹ] ${WHITE}$1${PLAIN}"; }
log_warn() { echo -e "${YELLOW}[$(date "+%Y-%m-%d %H:%M:%S")] [⚠] ${YELLOW}$1${PLAIN}"; }
log_success() { echo -e "${GREEN}[$(date "+%Y-%m-%d %H:%M:%S")] [✓] ${GREEN}$1${PLAIN}"; }
log_error() { echo -e "${RED}[$(date "+%Y-%m-%d %H:%M:%S")] [✗] ${RED}$1${PLAIN}" >&2; }
log_debug() { echo -e "${PURPLE}[$(date "+%Y-%m-%d %H:%M:%S")] [🔍] ${PURPLE}$1${PLAIN}"; }
log_step() { echo -e "${BLUE}[$(date "+%Y-%m-%d %H:%M:%S")] [➜] ${BLUE}${BOLD}$1${PLAIN}"; }

error_exit() {
    log_error "$1"
    exit 1
}
DEFAULT_PORT=7005
DEFAULT_PROTOCOL="udp"
SERVER_IP=$(curl -s ifconfig.me)
CONFIG_DIR="/usr/local/openvpn"
SERVER_CONFIG="$CONFIG_DIR/server.conf"
CLIENT_CONFIG="$CONFIG_DIR/client.ovpn"
SILENT_MODE=false
FRP_VERSION="v0.62.1"
FRPS_PORT="7000"
FRPS_UDP_PORT="7001"
FRPS_KCP_PORT="7000"
FRPS_DASHBOARD_PORT="31410"
FRPS_TOKEN="DFRN2vbG123"
FRPS_DASHBOARD_USER="admin"
FRPS_DASHBOARD_PWD="yao58181"
if [ "$EUID" -ne 0 ]; then
    log_error "请使用 root 权限运行此脚本"
    exit 1
fi
install_dependencies() {
    log_step "正在安装依赖..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update &> /dev/null
        apt-get install -y gnupg2 &> /dev/null
        curl -s https://swupdate.openvpn.net/repos/repo-public.gpg | apt-key add - &> /dev/null
        echo "deb http://build.openvpn.net/debian/openvpn/stable $(lsb_release -cs) main" > /etc/apt/sources.list.d/openvpn.list
        apt-get update &> /dev/null
        DEBIAN_FRONTEND=noninteractive apt-get install -y openvpn easy-rsa openssl curl wget python3 iptables-persistent &> /dev/null || error_exit "依赖安装失败"
    elif command -v yum >/dev/null 2>&1; then
        yum install -y epel-release &> /dev/null
        yum install -y openvpn easy-rsa openssl curl wget python3 iptables-services &> /dev/null || error_exit "依赖安装失败"
    else
        error_exit "不支持的操作系统，无法安装OpenVPN依赖。"
    fi
    log_success "OpenVPN 依赖安装完成"
}
generate_certificates() {
    log_step "正在生成证书..."
    mkdir -p /usr/local/openvpn/easy-rsa/ > /dev/null 2>&1 || error_exit "无法创建 easy-rsa 目录"
    cp -r /usr/share/easy-rsa/* /usr/local/openvpn/easy-rsa/ > /dev/null 2>&1 || error_exit "复制 easy-rsa 文件失败"
    cd /usr/local/openvpn/easy-rsa/ || error_exit "无法进入 easy-rsa 目录"
    ./easyrsa --batch init-pki > /dev/null 2>&1 || error_exit "初始化 PKI 失败"
    yes "" | ./easyrsa --batch build-ca nopass > /dev/null 2>&1 || error_exit "生成 CA 证书失败"
    yes "" | ./easyrsa --batch build-server-full server nopass > /dev/null 2>&1 || error_exit "生成服务器证书失败"
    yes "" | ./easyrsa --batch build-client-full client nopass > /dev/null 2>&1 || error_exit "生成客户端证书失败"
    ./easyrsa --batch gen-dh > /dev/null 2>&1 || error_exit "生成 Diffie-Hellman 参数失败"
    openvpn --genkey secret /usr/local/openvpn/ta.key > /dev/null 2>&1 || error_exit "生成 ta.key 失败"
    cp /usr/local/openvpn/easy-rsa/pki/ca.crt /usr/local/openvpn/ > /dev/null 2>&1 || error_exit "复制 ca.crt 失败"
    cp /usr/local/openvpn/easy-rsa/pki/issued/server.crt /usr/local/openvpn/ > /dev/null 2>&1 || error_exit "复制 server.crt 失败"
    cp /usr/local/openvpn/easy-rsa/pki/private/server.key /usr/local/openvpn/ > /dev/null 2>&1 || error_exit "复制 server.key 失败"
    cp /usr/local/openvpn/easy-rsa/pki/dh.pem /usr/local/openvpn/ > /dev/null 2>&1 || error_exit "复制 dh.pem 失败"
}
create_server_config() {
    log_step "正在创建服务器配置..."
    cat > $SERVER_CONFIG << EOF || error_exit "创建服务器配置文件失败"
port $DEFAULT_PORT
proto $DEFAULT_PROTOCOL
dev tun
ca ca.crt
cert server.crt
key server.key
dh dh.pem
auth SHA256
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305:AES-256-CBC
data-ciphers-fallback AES-256-CBC
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
push "redirect-gateway def1"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
keepalive 10 120
tls-auth ta.key 0
remote-cert-tls client
user nobody
group nogroup
persist-key
persist-tun
status openvpn-status.log
log-append openvpn.log
verb 1
EOF
}
create_client_config() {
    log_step "正在创建客户端配置..."
    cat > $CLIENT_CONFIG << EOF || error_exit "创建客户端配置文件失败"
client
dev tun
proto $DEFAULT_PROTOCOL
remote $SERVER_IP $DEFAULT_PORT
resolv-retry infinite
nobind
persist-key
persist-tun
auth SHA256
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305:AES-256-CBC
data-ciphers-fallback AES-256-CBC
remote-cert-tls server
verb 1

<ca>
$(cat $CONFIG_DIR/easy-rsa/pki/ca.crt)
</ca>
<cert>
$(cat $CONFIG_DIR/easy-rsa/pki/issued/client.crt)
</cert>
<key>
$(cat $CONFIG_DIR/easy-rsa/pki/private/client.key)
</key>
<tls-auth>
$(cat $CONFIG_DIR/ta.key)
</tls-auth>
key-direction 1
EOF
}
setup_port_forwarding() {
    log_step "正在设置端口转发..."
    echo 1 > /proc/sys/net/ipv4/ip_forward
    sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1
    if ! grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf; then
        echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf > /dev/null 2>&1
    fi
    sysctl -p > /dev/null 2>&1
    PUB_IF=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
    cat > /etc/iptables.rules << EOF || error_exit "创建iptables规则文件失败"
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A FORWARD -i tun0 -o ${PUB_IF} -j ACCEPT
-A FORWARD -i ${PUB_IF} -o tun0 -m state --state RELATED,ESTABLISHED -j ACCEPT
COMMIT

*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 10.8.0.0/24 -o ${PUB_IF} -j MASQUERADE
COMMIT
EOF
    iptables-restore < /etc/iptables.rules || error_exit "应用iptables规则失败"
    cat > /etc/systemd/system/iptables.service << EOF || error_exit "创建iptables服务文件失败"
[Unit]
Description=Restore iptables rules
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/iptables.rules
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable iptables > /dev/null 2>&1 || error_exit "启用iptables服务失败"
}
start_service() {
    log_step "正在启动 OpenVPN 服务..."
    systemctl enable openvpn@server > /dev/null 2>&1 || error_exit "启用 OpenVPN 服务失败"
    systemctl start openvpn@server > /dev/null 2>&1 || error_exit "启动 OpenVPN 服务失败"
    if [[ ! -f /etc/systemd/system/openvpn-autostart.service ]]; then
        cat > /etc/systemd/system/openvpn-autostart.service << EOF || error_exit "创建 OpenVPN 自启动服务文件失败"
[Unit]
Description=OpenVPN Auto Start Service
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "systemctl start openvpn@server"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable openvpn-autostart >/dev/null 2>&1 || error_exit "启用 OpenVPN 自启动服务失败"
    fi
}
uninstall() {
    log_step "正在卸载 OpenVPN..."
    systemctl stop openvpn@server > /dev/null 2>&1
    systemctl disable openvpn@server > /dev/null 2>&1
    systemctl disable openvpn-autostart > /dev/null 2>&1
    rm -f /etc/systemd/system/openvpn-autostart.service > /dev/null 2>&1
    systemctl stop iptables > /dev/null 2>&1
    systemctl disable iptables > /dev/null 2>&1
    rm -f /etc/systemd/system/iptables.service > /dev/null 2>&1
    rm -f /etc/iptables.rules > /dev/null 2>&1
    apt-get remove -y openvpn > /dev/null 2>&1
    rm -rf /usr/local/openvpn > /dev/null 2>&1
    systemctl daemon-reload > /dev/null 2>&1
    for port in $DEFAULT_PORT 80; do
        local pid=$(lsof -t -i :$port)
        if [ -n "$pid" ]; then
            kill $pid > /dev/null 2>&1
            sleep 1
            if ps -p $pid > /dev/null 2>&1; then
                kill -9 $pid > /dev/null 2>&1
            fi
        fi
    done
}
change_port() {
    local new_port=$1
    log_step "正在修改端口为 $new_port..."
    sed -i "s/port [0-9]*/port $new_port/" $SERVER_CONFIG > /dev/null 2>&1 || error_exit "修改服务器端口失败"
    sed -i "s/remote $SERVER_IP [0-9]*/remote $SERVER_IP $new_port/" $CLIENT_CONFIG > /dev/null 2>&1 || error_exit "修改客户端端口失败"
    systemctl restart openvpn@server > /dev/null 2>&1 || error_exit "重启OpenVPN服务失败"
    log_success "端口已成功修改为 $new_port"
}
generate_download_link() {
    log_step "正在生成客户端下载链接..."
    local config_path="/usr/local/openvpn/client.ovpn"
    if [ -f "$config_path" ]; then
        if lsof -i :80 > /dev/null 2>&1; then
            log_error "错误：80 端口已被占用，请先关闭占用该端口的服务"
            exit 1
        fi
        log_success "客户端配置文件下载链接："
        log_info "http://$SERVER_IP/client.ovpn"
        mkdir -p /usr/local/openvpn || error_exit "无法创建下载目录 /usr/local/openvpn"
        (cd /usr/local/openvpn && python3 -m http.server 80 > /dev/null 2>&1 & 
         pid=$!
         sleep 600
         kill $pid 2>/dev/null) &
        exit 0
    else
        log_error "客户端配置文件不存在"
    fi
}
uninstall_frps() {
    log_step "卸载旧版FRPS服务..."
    systemctl stop frps >/dev/null 2>&1
    systemctl disable frps >/dev/null 2>&1
    rm -f /etc/systemd/system/frps.service
    rm -rf /usr/local/frp /etc/frp
    systemctl daemon-reload >/dev/null 2>&1
    log_success "旧版FRPS服务已成功卸载"
}
install_frps() {
    uninstall_frps
    log_step "安装FRPS服务..."
    local FRP_NAME="frp_${FRP_VERSION#v}_linux_amd64"
    local FRP_FILE="${FRP_NAME}.tar.gz"
    cd /usr/local/ || error_exit "无法进入/usr/local/目录"
    if ! wget "https://github.com/fatedier/frp/releases/download/${FRP_VERSION}/${FRP_FILE}" -O "${FRP_FILE}" >/dev/null 2>&1; then
        error_exit "FRP下载失败"
    fi
    if ! tar -zxf "${FRP_FILE}" >/dev/null 2>&1; then
        rm -f "${FRP_FILE}"
        error_exit "FRP解压失败"
    fi
    cd "${FRP_NAME}" || error_exit "无法进入FRP目录"
    rm -f frpc*
    mkdir -p /usr/local/frp || error_exit "创建/usr/local/frp目录失败"
    if ! cp frps /usr/local/frp/ >/dev/null 2>&1; then
        error_exit "拷贝frps可执行文件失败"
    fi
    chmod +x /usr/local/frp/frps >/dev/null 2>&1 || error_exit "设置frps可执行权限失败"
    mkdir -p /etc/frp || error_exit "创建/etc/frp目录失败"
    {
        echo "bindAddr = \"0.0.0.0\""
        echo "bindPort = ${FRPS_PORT}"
        echo "kcpBindPort = ${FRPS_KCP_PORT}"
        echo "auth.method = \"token\""
        echo "auth.token = \"${FRPS_TOKEN}\""
        echo "webServer.addr = \"0.0.0.0\""
        echo "webServer.port = ${FRPS_DASHBOARD_PORT}"
        echo "webServer.user = \"${FRPS_DASHBOARD_USER}\""
        echo "webServer.password = \"${FRPS_DASHBOARD_PWD}\""
        echo "enablePrometheus = true"
        echo "log.level = \"error\""
        echo "log.to = \"none\""
    } > /etc/frp/frps.toml || error_exit "写入frps.toml配置文件失败"
    {
        echo "[Unit]"
        echo "Description=Frp Server Service"
        echo "After=network.target"
        echo "[Service]"
        echo "Type=simple"
        echo "User=root"
        echo "Restart=on-failure"
        echo "RestartSec=5s"
        echo "ExecStart=/usr/local/frp/frps -c /etc/frp/frps.toml"
        echo "LimitNOFILE=1048576"
        echo "StandardOutput=null"
        echo "StandardError=null"
        echo "[Install]"
        echo "WantedBy=multi-user.target"
    } > /etc/systemd/system/frps.service || error_exit "写入frps.service文件失败"
    if command -v ufw >/dev/null 2>&1; then
        ufw allow ${FRPS_PORT}/tcp >/dev/null 2>&1
        ufw allow ${FRPS_DASHBOARD_PORT}/tcp >/dev/null 2>&1
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=${FRPS_PORT}/tcp >/dev/null 2>&1
        firewall-cmd --permanent --add-port=${FRPS_DASHBOARD_PORT}/tcp >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    fi
    if ! systemctl daemon-reload >/dev/null 2>&1; then
        error_exit "Systemd daemon-reload失败"
    fi
    if ! systemctl enable --now frps >/dev/null 2>&1; then
        error_exit "启用并启动FRPS服务失败"
    fi
    log_success "FRPS安装成功"
    show_frps_info
}
show_frps_info() {
    log_step "FRPS服务状态："
    systemctl status frps --no-pager | grep -E 'Active:'
    log_step "FRPS信息："
    log_info "服务器地址: $(curl -s ifconfig.me || hostname -I | awk '{print $1}')"
    log_info "FRPS 端口: ${FRPS_PORT}"
    log_info "FRPS 密码: ${FRPS_TOKEN}"
    log_info "Web管理界面: http://$(curl -s ifconfig.me || hostname -I | awk '{print $1}'):${FRPS_DASHBOARD_PORT}"
    log_info "Web管理用户名: ${FRPS_DASHBOARD_USER}"
    log_info "Web管理密码: ${FRPS_DASHBOARD_PWD}"
}
main_menu() {
    while true; do
        echo -e "${CYAN}╭────────────────────────────────────────────────────────────────────╮${PLAIN}"
        echo -e "${CYAN}│                       ${WHITE}${BOLD}OpenVPN + FRP 管理面板${PLAIN}${CYAN}                     │${PLAIN}"
        echo -e "${CYAN}╰────────────────────────────────────────────────────────────────────╯${PLAIN}"
        log_info "请选择操作："
        echo -e "${WHITE}  1) ${GREEN}安装 OpenVPN + FRP${PLAIN}"
        echo -e "${WHITE}  2) ${RED}卸载 OpenVPN${PLAIN}"
        echo -e "${WHITE}  3) ${BLUE}修改端口${PLAIN}"
        echo -e "${WHITE}  4) ${YELLOW}生成客户端下载链接${PLAIN}"
        echo -e "${WHITE}  5) ${RED}卸载 FRP${PLAIN}"
        echo -e "${WHITE}  6) ${CYAN}显示 FRP 信息${PLAIN}"
        echo -e "${WHITE}  7) ${PURPLE}退出${PLAIN}"
        read -t 30 -p "请输入数字 [1-7]: " choice
        if [ -z "$choice" ]; then
            continue
        fi
        case $choice in
            1)
                install_dependencies
                generate_certificates
                create_server_config
                create_client_config
                setup_port_forwarding
                start_service
                install_frps
                echo -e "${GREEN}╭────────────────────────────────────────────────────────────────────╮${PLAIN}"
                echo -e "${GREEN}│                          ${WHITE}${BOLD}安装完成${PLAIN}${GREEN}                                │${PLAIN}"
                echo -e "${GREEN}╰────────────────────────────────────────────────────────────────────╯${PLAIN}"
                generate_download_link
                exit 0
                ;;
            2)
                uninstall
                ;;
            3)
                new_port=7005
                change_port $new_port
                ;;
            4)
                generate_download_link
                ;;
            5)
                uninstall_frps
                ;;
            6)
                show_frps_info
                ;;
            7)
                log_warn "已退出"
                exit 0
                ;;
            *)
                log_error "无效选择，请重新输入"
                ;;
        esac
    done
}
main_menu
