#!/bin/bash
export LANG=en_US.UTF-8
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
PLAIN="\033[0m"
red(){ echo -e "\033[31m\033[01m$1\033[0m"; }
green(){ echo -e "\033[32m\033[01m$1\033[0m"; }
yellow(){ echo -e "\033[33m\033[01m$1\033[0m"; }

# 错误处理函数
error_exit() {
    red "$1" && exit 1
}

# 通用配置
QUIC_CONFIG="
  initStreamReceiveWindow: 16777216
  maxStreamReceiveWindow: 16777216
  initConnReceiveWindow: 33554432
  maxConnReceiveWindow: 33554432"

TLS_CONFIG="
  sni: www.bing.com
  insecure: true"

SOCKS5_CONFIG="
  listen: 127.0.0.1:5678"

TRANSPORT_CONFIG="
  udp:
    hopInterval: 30s"

# FRPS配置
FRP_VERSION="v0.62.1"
FRPS_PORT="8443"
FRPS_TOKEN="DFRN2vbG123"
SILENT_MODE=true

# 获取FRPS连接密码的函数
gen_frps_token() {
    echo "$FRPS_TOKEN"
}
FRPS_TOKEN=$(gen_frps_token)

# 卸载旧版FRPS
uninstall_frps() {
    yellow "卸载旧版FRPS服务..."
    systemctl stop frps >/dev/null 2>&1
    systemctl disable frps >/dev/null 2>&1
    rm -f /etc/systemd/system/frps.service
    rm -rf /usr/local/frp /etc/frp
    systemctl daemon-reload >/dev/null 2>&1
}

# 安装FRPS
install_frps() {
    uninstall_frps
    yellow "安装FRPS服务..."
    local FRP_NAME="frp_${FRP_VERSION#v}_linux_amd64"
    local FRP_FILE="${FRP_NAME}.tar.gz"
    cd /usr/local/ || error_exit "无法进入 /usr/local/ 目录"
    yellow "下载FRPS（版本：${FRP_VERSION}）..."
    if ! wget -q "https://github.com/fatedier/frp/releases/download/${FRP_VERSION}/${FRP_FILE}" -O "${FRP_FILE}" >/dev/null 2>&1; then
        error_exit "FRPS下载失败"
    fi
    yellow "解压FRPS安装包..."
    if ! tar -zxf "${FRP_FILE}" >/dev/null 2>&1; then
        rm -f "${FRP_FILE}"
        error_exit "FRPS解压失败"
    fi
    cd "${FRP_NAME}" || error_exit "无法进入解压目录"
    rm -f frpc*
    yellow "安装FRPS可执行文件..."
    mkdir -p /usr/local/frp || error_exit "创建 /usr/local/frp 目录失败"
    if ! cp frps /usr/local/frp/; then
        error_exit "拷贝 frps 可执行文件失败"
    fi
    chmod +x /usr/local/frp/frps
    if [ $? -ne 0 ]; then
        error_exit "设置 frps 可执行权限失败"
    fi
    yellow "创建FRPS配置文件..."
    mkdir -p /etc/frp || error_exit "创建 /etc/frp 目录失败"
    cat > /etc/frp/frps.toml << EOF
bindAddr = "127.0.0.1"
bindPort = ${FRPS_PORT}
auth.method = "token"
auth.token = "${FRPS_TOKEN}"
EOF
    if [ $? -ne 0 ]; then
        error_exit "写入 frps.toml 配置文件失败"
    fi
    yellow "创建FRPS服务单元..."
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
        error_exit "写入 frps.service 文件失败"
    fi

    
    systemctl daemon-reload
    if [ $? -ne 0 ]; then
        error_exit "重新加载 systemd 配置失败"
    fi
    systemctl enable frps >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        error_exit "启用 frps 服务失败"
    fi
    yellow "启用并启动FRPS服务..."
    systemctl start frps >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        error_exit "启动 frps 服务失败"
        journalctl -u frps.service --no-pager -n 20
    fi
    
    if systemctl is-active frps >/dev/null 2>&1; then
        green "FRPS服务已成功启动"
    else
        error_exit "FRPS服务启动失败"
    fi
    
    rm -f /usr/local/${FRP_FILE}
    rm -rf /usr/local/${FRP_NAME}
    
    green "FRPS安装成功"
    
    # 清理临时文件
    cleanup
    
    # 添加定时清理日志任务
    add_cron_job
    
    # 显示FRPS信息
    show_frps_info
}

# 清理临时文件
cleanup() {
    rm -rf /usr/local/frp_* /usr/local/frp_*_linux_amd64
}

# 添加定时清理日志任务
add_cron_job() {
    local cron_entry='0 3 1 * * find /usr/local -type f -name "*.log" -delete'
    (crontab -l 2>/dev/null | grep -v -F "$cron_entry") | crontab -
    (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
}

[[ -z $(type -P curl) ]] && { [[ ! $SYSTEM == "CentOS" ]] && ${PACKAGE_UPDATE[int]}; ${PACKAGE_INSTALL[int]} curl; }
realip() { 
    ip=$(curl -s4m8 ip.sb -k) || ip=$(curl -s6m8 ip.sb -k) 
    if [[ -z "$ip" ]]; then
        ip=$(curl -s4m8 ipinfo.io/ip) || ip=$(curl -s6m8 ipinfo.io/ip)
    fi
    if [[ -z "$ip" ]]; then
        ip=$(curl -s4m8 api.ipify.org) || ip=$(curl -s6m8 api64.ipify.org)
    fi
    if [[ -z "$ip" ]]; then
        ip=$(curl -s4m8 ifconfig.me) || ip=$(curl -s6m8 ifconfig.me)
    fi
    echo "$ip"
}

declare -A COUNTRY_MAP=(
  ["US"]="美国" ["CN"]="中国" ["HK"]="香港" ["TW"]="台湾" ["JP"]="日本" ["KR"]="韩国"
  ["SG"]="新加坡" ["AU"]="澳大利亚" ["DE"]="德国" ["GB"]="英国" ["CA"]="加拿大" ["FR"]="法国"
  ["IN"]="印度" ["IT"]="意大利" ["RU"]="俄罗斯" ["BR"]="巴西" ["NL"]="荷兰" ["SE"]="瑞典"
  ["NO"]="挪威" ["FI"]="芬兰" ["DK"]="丹麦" ["CH"]="瑞士" ["ES"]="西班牙" ["PT"]="葡萄牙"
  ["AT"]="奥地利" ["BE"]="比利时" ["IE"]="爱尔兰" ["PL"]="波兰" ["NZ"]="新西兰" ["MX"]="墨西哥"
  ["ID"]="印度尼西亚" ["TH"]="泰国" ["VN"]="越南" ["MY"]="马来西亚" ["PH"]="菲律宾"
  ["TR"]="土耳其" ["AE"]="阿联酋" ["SA"]="沙特阿拉伯" ["ZA"]="南非" ["IL"]="以色列" 
  ["UA"]="乌克兰" ["GR"]="希腊" ["CZ"]="捷克" ["HU"]="匈牙利" ["RO"]="罗马尼亚" 
  ["BG"]="保加利亚" ["HR"]="克罗地亚" ["RS"]="塞尔维亚" ["EE"]="爱沙尼亚" ["LV"]="拉脱维亚"
  ["LT"]="立陶宛" ["SK"]="斯洛伐克" ["SI"]="斯洛文尼亚" ["IS"]="冰岛" ["LU"]="卢森堡"
  ["UK"]="英国"
)

get_ip_region() {
    local ip=$1
    if [[ -z "$ip" ]]; then
        realip
    fi

    local chinese_region=""
    local country_code=""

    chinese_region=$(curl -s "https://cip.cc/${ip}" | grep "数据二" | cut -d ":" -f2 | awk '{print $1}')
    if [[ -n "$chinese_region" && "$chinese_region" != *"timeout"* ]]; then
        echo "$chinese_region"
        return
    fi

    country_code=$(curl -s -m 5 "https://ipinfo.io/${ip}/json" | grep -o '"country":"[^"]*"' | cut -d ':' -f2 | tr -d '",')

    if [[ -z "$country_code" ]]; then
        country_code=$(curl -s -m 5 "https://api.ip.sb/geoip/${ip}" | grep -o '"country_code":"[^"]*"' | cut -d ':' -f2 | tr -d '",')
    fi

    if [[ -z "$country_code" ]]; then
        country_code=$(curl -s -m 5 "https://ipapi.co/${ip}/country")

        if [[ "$country_code" == *"error"* || "$country_code" == *"reserved"* ]]; then
            country_code=""
        fi
    fi

    if [[ -z "$country_code" ]]; then
        country_code=$(curl -s -m 5 "http://ip-api.com/json/${ip}?fields=countryCode" | grep -o '"countryCode":"[^"]*"' | cut -d ':' -f2 | tr -d '",')
    fi

    if [[ -n "$country_code" ]]; then
        local country_name="${COUNTRY_MAP[$country_code]}"
        if [[ -n "$country_name" ]]; then
            echo "$country_name"
            return
        fi
    fi

    local continent=""
    continent=$(curl -s -m 5 "http://ip-api.com/json/${ip}?fields=continent" | grep -o '"continent":"[^"]*"' | cut -d ':' -f2 | tr -d '",')

    if [[ -n "$continent" ]]; then
        case $continent in
            "North America") echo "北美洲" ;;
            "South America") echo "南美洲" ;;
            "Europe") echo "欧洲" ;;
            "Asia") echo "亚洲" ;;
            "Africa") echo "非洲" ;;
            "Oceania") echo "大洋洲" ;;
            "Antarctica") echo "南极洲" ;;
            *) echo "国外" ;;
        esac
        return
    fi

    echo "国外"
}

# 生成Hysteria2分享链接
generate_hy2_url() {
    local auth_pwd=$1
    local last_ip=$2
    local port=$3
    local node_name=$4
    echo "hysteria2://$auth_pwd@$last_ip:$port/?insecure=1&sni=www.bing.com#$node_name"
}

install_hy2() {
    systemctl stop vpn >/dev/null 2>&1
    systemctl disable vpn >/dev/null 2>&1
    rm -f /etc/systemd/system/vpn.service
    if pgrep vpnserver > /dev/null; then
        /usr/local/vpnserver/vpnserver stop >/dev/null 2>&1
    fi
    rm -rf /usr/local/vpnserver
    rm -rf /usr/local/vpnserver/packet_log /usr/local/vpnserver/security_log /usr/local/vpnserver/server_log
    systemctl daemon-reload >/dev/null 2>&1
    
    # 先获取公网IP
    ip=$(realip)
    if [[ -z "$ip" ]]; then
        yellow "无法获取公网IP，将使用内网IP"
        ip=$(hostname -I | awk '{print $1}')
    fi
    yellow "当前公网IP: $ip"
    
    wget -N https://raw.githubusercontent.com/Misaka-blog/hysteria-install/main/hy2/install_server.sh > /dev/null 2>&1 || error_exit "下载安装脚本失败"
    bash install_server.sh > /dev/null 2>&1 || error_exit "执行安装脚本失败"
    rm -f install_server.sh

    if [[ ! -f "/usr/local/bin/hysteria" ]]; then
        error_exit "Hysteria 2 安装失败！"
    fi

    mkdir -p /etc/hysteria || error_exit "无法创建Hysteria配置目录"

    yellow "下载TLS证书和密钥..."
    wget -q "https://raw.githubusercontent.com/yao0525888/cs/main/cert.crt" -O /etc/hysteria/cert.crt || error_exit "下载证书失败"
    wget -q "https://raw.githubusercontent.com/yao0525888/cs/main/private.key" -O /etc/hysteria/private.key || error_exit "下载密钥失败"
    chmod 644 /etc/hysteria/cert.crt /etc/hysteria/private.key

    auth_pwd="9e264d67-fe47-4d2f-b55e-631a12e46a30"

    cat << EOF > /etc/hysteria/config.yaml || error_exit "无法创建Hysteria配置文件"
listen: :443

tls:
  cert: /etc/hysteria/cert.crt
  key: /etc/hysteria/private.key

quic:$QUIC_CONFIG

auth:
  type: password
  password: $auth_pwd

masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true
EOF

    if [[ -n $(echo $ip | grep ":") ]]; then
        last_ip="[$ip]"
    else
        last_ip=$ip
    fi

    # 再次确认IP地址（以防之前的变量失效）
    if [[ -z "$ip" || "$ip" == "" ]]; then
        ip=$(realip)
        if [[ -z "$ip" ]]; then
            ip=$(hostname -I | awk '{print $1}')
            yellow "使用内网IP: $ip"
        else
            yellow "使用公网IP: $ip"
        fi
    fi
    
    node_name=$(get_ip_region "$ip")

    # 生成分享链接
    url=$(generate_hy2_url "$auth_pwd" "$last_ip" "443" "$node_name")
    
    # 如果URL中缺少IP，尝试直接构建
    if [[ "$url" == *"@:"* || "$url" == *"@]:"* ]]; then
        yellow "分享链接IP异常，尝试修复..."
        direct_ip=$(realip)
        if [[ -n "$direct_ip" ]]; then
            url="hysteria2://$auth_pwd@$direct_ip:443/?insecure=1&sni=www.bing.com#$node_name"
        fi
    fi

    systemctl daemon-reload
    systemctl enable hysteria-server > /dev/null 2>&1 || error_exit "无法启用Hysteria服务"
    systemctl start hysteria-server || error_exit "无法启动Hysteria服务"

    if [[ ! -f /etc/systemd/system/hysteria-autostart.service ]]; then
        cat > /etc/systemd/system/hysteria-autostart.service << EOF || error_exit "无法创建Hysteria自启动服务文件"
[Unit]
Description=Hysteria 2 Auto Start Service
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "systemctl start hysteria-server"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable hysteria-autostart >/dev/null 2>&1 || error_exit "无法启用Hysteria自启动服务"
    fi

    if [[ -n $(systemctl status hysteria-server 2>/dev/null | grep -w active) ]]; then
        green "======================================================================================"
        green "Hysteria 2 安装成功！"
        yellow "端口: 443"
        yellow "密码: $auth_pwd"
        yellow "伪装网站: www.bing.com"
        yellow "TLS SNI: www.bing.com"
        yellow "节点名称: $node_name"
        echo ""
        green "======================================================================================"
        echo ""
        yellow "分享链接:"
        red "$url"
        echo ""
        
        # 添加定时清理日志任务
        add_cron_job
    else
        error_exit "Hysteria 2 服务启动失败，请检查日志"
    fi
}

# 卸载Hysteria2
uninstall_hy2() {
    systemctl stop hysteria-server >/dev/null 2>&1
    systemctl disable hysteria-server >/dev/null 2>&1
    systemctl disable hysteria-autostart >/dev/null 2>&1

    rm -f /etc/systemd/system/hysteria-autostart.service
    rm -f /lib/systemd/system/hysteria-server.service /lib/systemd/system/hysteria-server@.service
    rm -rf /usr/local/bin/hysteria /etc/hysteria

    systemctl daemon-reload

    green "Hysteria 2 已完全卸载！"
}

start_hy2() {
    systemctl start hysteria-server
    if [[ -n $(systemctl status hysteria-server 2>/dev/null | grep -w active) ]]; then
        green "Hysteria 2 已启动"
    else 
        red "Hysteria 2 启动失败"
    fi
}

stop_hy2() {
    systemctl stop hysteria-server
    green "Hysteria 2 已停止"
}

restart_hy2() {
    systemctl restart hysteria-server
    if [[ -n $(systemctl status hysteria-server 2>/dev/null | grep -w active) ]]; then
        green "Hysteria 2 已重启"
    else 
        red "Hysteria 2 重启失败"
    fi
}

show_config() {
    green "======================================================================================"
    yellow "无法显示客户端配置文件，因为已设置为不保存。请使用安装完成时显示的分享链接。"
    green "======================================================================================"
}

service_menu() {
    clear
    echo "#############################################################"
    echo -e "#                  ${GREEN}Hysteria 2 服务控制${PLAIN}                     #"
    echo "#############################################################"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} 启动 Hysteria 2"
    echo -e " ${GREEN}2.${PLAIN} 停止 Hysteria 2"
    echo -e " ${GREEN}3.${PLAIN} 重启 Hysteria 2"
    echo -e " ${GREEN}0.${PLAIN} 返回主菜单"
    echo ""
    read -rp "请输入选项 [0-3]: " switchInput
    case $switchInput in
        1) start_hy2 ;;
        2) stop_hy2 ;;
        3) restart_hy2 ;;
        0) menu ;;
        *) red "无效选项" ;;
    esac
    menu
}

# 修改Hysteria2端口
modify_hy2_port() {
    yellow "修改Hysteria2端口..."
    read -p "请输入新的端口号(1-65535): " NEW_PORT
    
    # 验证端口号
    if ! [[ "$NEW_PORT" =~ ^[0-9]+$ ]] || [ "$NEW_PORT" -lt 1 ] || [ "$NEW_PORT" -gt 65535 ]; then
        error_exit "无效的端口号，请输入1-65535之间的数字"
    fi
    
    # 检查端口是否被占用
    if netstat -tuln | grep -q ":$NEW_PORT "; then
        error_exit "端口 $NEW_PORT 已被占用"
    fi
    
    # 修改配置文件
    sed -i "s/listen: :[0-9]*/listen: :$NEW_PORT/" /etc/hysteria/config.yaml || error_exit "修改配置文件失败"
    
    # 重启服务
    systemctl restart hysteria-server || error_exit "重启Hysteria2服务失败"
    
    green "Hysteria2端口已修改为: $NEW_PORT"
    echo ""
    
    # 重新生成并显示分享链接
    local auth_pwd="9e264d67-fe47-4d2f-b55e-631a12e46a30"
    local ip
    realip
    local last_ip
    if [[ -n $(echo $ip | grep ":") ]]; then
        last_ip="[$ip]"
    else
        last_ip=$ip
    fi
    local node_name=$(get_ip_region "$ip")
    local new_url=$(generate_hy2_url "$auth_pwd" "$last_ip" "$NEW_PORT" "$node_name")

    yellow "新的分享链接:"
    red "$new_url"
    echo ""
}

menu() {
    clear
    echo "#############################################################"
    echo -e "#                 ${GREEN}Hysteria 2 一键配置脚本${PLAIN}                  #"
    echo "#############################################################"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} 安装 Hysteria 2"
    echo -e " ${RED}2.${PLAIN} 卸载 Hysteria 2"
    echo "------------------------------------------------------------"
    echo -e " ${GREEN}3.${PLAIN} 关闭、开启、重启 Hysteria 2"
    echo -e " ${GREEN}4.${PLAIN} 显示 Hysteria 2 配置文件"
    echo -e " ${GREEN}5.${PLAIN} 修改 Hysteria 2 端口"
    echo "------------------------------------------------------------"
    echo -e " ${GREEN}6.${PLAIN} 安装 FRPS"
    echo -e " ${RED}7.${PLAIN} 卸载 FRPS"
    echo -e " ${GREEN}8.${PLAIN} 显示 FRPS 信息"
    echo "------------------------------------------------------------"
    echo -e " ${GREEN}0.${PLAIN} 退出脚本"
    echo ""
    read -rp "请输入选项 [0-8]: " menuInput
    case $menuInput in
        1) install_hy2 ;;
        2) uninstall_hy2 ;;
        3) service_menu ;;
        4) show_config ;;
        5) modify_hy2_port ;;
        6) install_frps ;;
        7) uninstall_frps ;;
        8) show_frps_info ;;
        0) exit 0 ;;
        *) red "请输入正确的选项 [0-8]" && exit 1 ;;
    esac
}

# 显示FRPS信息
show_frps_info() {
    echo -e "\n${YELLOW}>>> FRPS服务状态：${PLAIN}"
    systemctl is-active frps
    echo -e "\n${YELLOW}>>> FRPS信息：${PLAIN}"
    echo -e "服务器地址: $(curl -s ifconfig.me || hostname -I | awk '{print $1}')"
    echo -e "FRPS TCP端口: $FRPS_PORT"
    echo -e "FRPS 密码: $FRPS_TOKEN"
    echo -e "FRPS KCP端口: $FRPS_KCP_PORT\n"
}

menu
