#!/bin/bash
export LANG=en_US.UTF-8
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"
HYSTERIA_PORT=7011
MASQUERADE_HOST=www.bing.com
HY_PASSWORD=9e264d67-fe47-4d2f-b55e-631a12e46a30
HY_OBFS_PASSWORD=wGW1duwjo7gWV0F4aqJu44jJBG4ELk3WNgbs3ATJu3M
red(){ echo -e "\033[31m\033[01m$1\033[0m"; }
green(){ echo -e "\033[32m\033[01m$1\033[0m"; }
yellow(){ echo -e "\033[33m\033[01m$1\033[0m"; }

[[ -z $(type -P curl) ]] && { [[ ! $SYSTEM == "CentOS" ]] && ${PACKAGE_UPDATE[int]}; ${PACKAGE_INSTALL[int]} curl; }
realip(){ ip=$(curl -s4m8 ip.sb -k) || ip=$(curl -s6m8 ip.sb -k); }
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

    local country_code=""

    country_code=$(curl -s -m 5 "https://ipinfo.io/${ip}/json" | grep -o '"country":"[^\"]*"' | cut -d ':' -f2 | tr -d '",')

    if [[ -z "$country_code" ]]; then
        country_code=$(curl -s -m 5 "https://api.ip.sb/geoip/${ip}" | grep -o '"country_code":"[^\"]*"' | cut -d ':' -f2 | tr -d '",')
    fi

    if [[ -z "$country_code" ]]; then
        country_code=$(curl -s -m 5 "https://ipapi.co/${ip}/country")
        if [[ "$country_code" == *"error"* || "$country_code" == *"reserved"* ]]; then
            country_code=""
        fi
    fi

    if [[ -z "$country_code" ]]; then
        country_code=$(curl -s -m 5 "http://ip-api.com/json/${ip}?fields=countryCode" | grep -o '"countryCode":"[^\"]*"' | cut -d ':' -f2 | tr -d '",')
    fi

    if [[ -n "$country_code" ]]; then
        local country_name="${COUNTRY_MAP[$country_code]}"
        if [[ -n "$country_name" ]]; then
            echo "$country_name"
            return
        fi
    fi

    echo "国外"
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
    realip
    wget -N https://raw.githubusercontent.com/Misaka-blog/hysteria-install/main/hy2/install_server.sh > /dev/null 2>&1
    bash install_server.sh > /dev/null 2>&1
    rm -f install_server.sh

    if [[ ! -f "/usr/local/bin/hysteria" ]]; then
        red "Hysteria 2 安装失败！" && exit 1
    fi

    mkdir -p /etc/hysteria

    wget -O /etc/hysteria/cert.crt https://github.com/yao0525888/hysteria/releases/download/v1/cert.crt
    wget -O /etc/hysteria/private.key https://github.com/yao0525888/hysteria/releases/download/v1/private.key
    chmod 644 /etc/hysteria/cert.crt /etc/hysteria/private.key

    cat << EOF > /etc/hysteria/config.yaml
listen: :$HYSTERIA_PORT

tls:
  cert: /etc/hysteria/cert.crt
  key: /etc/hysteria/private.key

quic:
  initStreamReceiveWindow: 16777216
  maxStreamReceiveWindow: 16777216
  initConnReceiveWindow: 33554432
  maxConnReceiveWindow: 33554432

obfs:
  type: salamander
  salamander:
    password: "$HY_OBFS_PASSWORD"

auth:
  type: password
  password: "$HY_PASSWORD"

masquerade:
  type: proxy
  proxy:
    url: https://$MASQUERADE_HOST
    rewriteHost: true
EOF

    if [[ -n $(echo $ip | grep ":") ]]; then
        last_ip="[$ip]"
    else
        last_ip=$ip
    fi

    mkdir -p /root/hy

    node_name=$(get_ip_region "$ip")

    cat << EOF > /root/hy/hy-client.yaml
server: $last_ip:7011-7050

auth:
  type: password
  password: "$HY_PASSWORD"

obfs:
  type: salamander
  salamander:
    password: "$HY_OBFS_PASSWORD"

tls:
  sni: $MASQUERADE_HOST
  insecure: true

quic:
  initStreamReceiveWindow: 16777216
  maxStreamReceiveWindow: 16777216
  initConnReceiveWindow: 33554432
  maxConnReceiveWindow: 33554432

fastOpen: true

socks5:
  listen: 127.0.0.1:5678

transport:
  type: udp
  udp:
    hopInterval: 20s
EOF

    cat << EOF > /root/hy/hy-client.json
{
  "server": "$last_ip:7011-7050",
  "auth": {
    "type": "password",
    "password": "$HY_PASSWORD"
  },
  "obfs": {
    "type": "salamander",
    "salamander": {
      "password": "$HY_OBFS_PASSWORD"
    }
  },
  "tls": {
    "sni": "$MASQUERADE_HOST",
    "insecure": true
  },
  "quic": {
    "initStreamReceiveWindow": 16777216,
    "maxStreamReceiveWindow": 16777216,
    "initConnReceiveWindow": 33554432,
    "maxConnReceiveWindow": 33554432
  },
  "socks5": {
    "listen": "127.0.0.1:5678"
  },
  "transport": {
    "type": "udp",
    "udp": {
      "hopInterval": "20s"
    }
  }
}
EOF

    url="hy2://$HY_PASSWORD@$last_ip:7011-7050/?insecure=1&sni=$MASQUERADE_HOST&obfs=salamander&obfs-password=$HY_OBFS_PASSWORD#$node_name"
    echo $url > /root/hy/url.txt

    cat > /etc/systemd/system/hysteria-server.service << EOF
[Unit]
Description=Hysteria 2 Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
Restart=on-failure
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    yellow "正在配置 iptables 端口转发（7012-7050 -> $HYSTERIA_PORT）..."
    
    INTERFACE=""
    if command -v ip &> /dev/null; then
        INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
        if [[ -z "$INTERFACE" ]]; then
            INTERFACE=$(ip -4 route show default | awk '{print $5}' | head -n1)
        fi
        if [[ -z "$INTERFACE" ]]; then
            INTERFACE=$(ip link show | grep -E "^[0-9]+:" | grep -v lo | head -n1 | awk -F': ' '{print $2}' | awk '{print $1}')
        fi
    fi
    
    if [[ -z "$INTERFACE" ]] && [ -d /sys/class/net ]; then
        for iface in /sys/class/net/*; do
            ifname=$(basename "$iface")
            if [[ "$ifname" != "lo" ]] && [ -f "$iface/operstate" ]; then
                if grep -q "up" "$iface/operstate" 2>/dev/null || [ -f "$iface/carrier" ]; then
                    INTERFACE="$ifname"
                    break
                fi
            fi
        done
    fi
    
    IPTABLES_CMD=""
    if command -v iptables &> /dev/null; then
        IPTABLES_CMD=$(command -v iptables)
    elif [ -f /sbin/iptables ]; then
        IPTABLES_CMD="/sbin/iptables"
    elif [ -f /usr/sbin/iptables ]; then
        IPTABLES_CMD="/usr/sbin/iptables"
    fi
    
    if [[ -n "$INTERFACE" ]] && [[ -n "$IPTABLES_CMD" ]]; then
        for port in {7012..7050}; do
            $IPTABLES_CMD -t nat -D PREROUTING -i $INTERFACE -p udp --dport $port -j REDIRECT --to-ports $HYSTERIA_PORT 2>/dev/null
        done
        
        for port in {7012..7050}; do
            $IPTABLES_CMD -t nat -A PREROUTING -i $INTERFACE -p udp --dport $port -j REDIRECT --to-ports $HYSTERIA_PORT
        done
        
        IP6TABLES_CMD=""
        if command -v ip6tables &> /dev/null; then
            IP6TABLES_CMD=$(command -v ip6tables)
        elif [ -f /sbin/ip6tables ]; then
            IP6TABLES_CMD="/sbin/ip6tables"
        elif [ -f /usr/sbin/ip6tables ]; then
            IP6TABLES_CMD="/usr/sbin/ip6tables"
        fi
        
        if [[ -n "$IP6TABLES_CMD" ]] && ip -6 route show default &> /dev/null 2>&1; then
            for port in {7012..7050}; do
                $IP6TABLES_CMD -t nat -A PREROUTING -i $INTERFACE -p udp --dport $port -j REDIRECT --to-ports $HYSTERIA_PORT 2>/dev/null
            done
        fi
        
        mkdir -p /etc/iptables
        if command -v iptables-save &> /dev/null; then
            iptables-save > /etc/iptables/rules.v4
        elif [ -f /sbin/iptables-save ]; then
            /sbin/iptables-save > /etc/iptables/rules.v4
        elif [ -f /usr/sbin/iptables-save ]; then
            /usr/sbin/iptables-save > /etc/iptables/rules.v4
        fi
        
        if [[ -n "$IP6TABLES_CMD" ]]; then
            if command -v ip6tables-save &> /dev/null; then
                ip6tables-save > /etc/iptables/rules.v6 2>/dev/null
            elif [ -f /sbin/ip6tables-save ]; then
                /sbin/ip6tables-save > /etc/iptables/rules.v6 2>/dev/null
            elif [ -f /usr/sbin/ip6tables-save ]; then
                /usr/sbin/ip6tables-save > /etc/iptables/rules.v6 2>/dev/null
            fi
        fi
        
        if [ -f /etc/sysconfig/iptables ]; then
            iptables-save > /etc/sysconfig/iptables
        fi
        
        if command -v netfilter-persistent &> /dev/null; then
            netfilter-persistent save 2>/dev/null
        elif command -v iptables-persistent &> /dev/null; then
            iptables-persistent save 2>/dev/null
        fi
        
        if [ ! -f /etc/systemd/system/iptables-restore.service ]; then
            cat > /etc/systemd/system/iptables-restore.service << 'IPTABLES_EOF'
[Unit]
Description=Restore iptables rules
After=network.target
Before=network-online.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/iptables/rules.v4
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
IPTABLES_EOF
            systemctl daemon-reload
            systemctl enable iptables-restore >/dev/null 2>&1
        fi
        
        green "✅ iptables 端口转发配置完成（接口: $INTERFACE）"
    else
        yellow "⚠️  未检测到 iptables 或网络接口"
        if [[ -z "$INTERFACE" ]]; then
            yellow "   检测到的网络接口: 无"
            yellow "   可用接口列表:"
            if command -v ip &> /dev/null; then
                ip link show | grep -E "^[0-9]+:" | awk -F': ' '{print "     - " $2}' || echo "     无法获取"
            elif [ -d /sys/class/net ]; then
                ls -1 /sys/class/net | grep -v lo | while read iface; do
                    echo "     - $iface"
                done
            fi
        else
            yellow "   检测到的网络接口: $INTERFACE"
        fi
        if [[ -z "$IPTABLES_CMD" ]]; then
            yellow "   iptables 命令: 未找到"
            yellow "   请安装 iptables: apt-get install iptables 或 yum install iptables"
        else
            yellow "   iptables 命令: $IPTABLES_CMD"
        fi
        yellow ""
        yellow "   手动配置命令:"
        if [[ -n "$INTERFACE" ]]; then
            yellow "   iptables -t nat -A PREROUTING -i $INTERFACE -p udp --dport 7012:7050 -j REDIRECT --to-ports $HYSTERIA_PORT"
        else
            yellow "   iptables -t nat -A PREROUTING -i <interface> -p udp --dport 7012:7050 -j REDIRECT --to-ports $HYSTERIA_PORT"
            yellow "   请将 <interface> 替换为实际网络接口名称（如 eth0、ens33 等）"
        fi
    fi

    systemctl daemon-reload
    systemctl enable hysteria-server > /dev/null 2>&1
    systemctl start hysteria-server

    if [[ ! -f /etc/systemd/system/hysteria-autostart.service ]]; then
        cat > /etc/systemd/system/hysteria-autostart.service << EOF
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
        systemctl enable hysteria-autostart >/dev/null 2>&1
    fi

    if [[ -n $(systemctl status hysteria-server 2>/dev/null | grep -w active) ]]; then
        green "======================================================================================"
        green "Hysteria 2 安装成功！"
        yellow "端口: $HYSTERIA_PORT"
        yellow "密码: $HY_PASSWORD"
        yellow "伪装网站: $MASQUERADE_HOST"
        yellow "TLS SNI: $MASQUERADE_HOST"
        yellow "节点名称: $node_name"
        echo ""
        yellow "客户端配置已保存到: /root/hy/"
        yellow "分享链接:"
        red "$url"
        green "======================================================================================"
    else
        red "Hysteria 2 服务启动失败" && exit 1
    fi
}

uninstall_hy2() {
    systemctl stop hysteria-server >/dev/null 2>&1
    systemctl disable hysteria-server >/dev/null 2>&1
    systemctl disable hysteria-autostart >/dev/null 2>&1

    rm -f /etc/systemd/system/hysteria-autostart.service
    rm -f /lib/systemd/system/hysteria-server.service /lib/systemd/system/hysteria-server@.service
    rm -rf /usr/local/bin/hysteria /etc/hysteria /root/hy

    yellow "正在清理 iptables 端口转发规则..."
    
    INTERFACE=""
    if command -v ip &> /dev/null; then
        INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
        if [[ -z "$INTERFACE" ]]; then
            INTERFACE=$(ip -4 route show default | awk '{print $5}' | head -n1)
        fi
        if [[ -z "$INTERFACE" ]]; then
            INTERFACE=$(ip link show | grep -E "^[0-9]+:" | grep -v lo | head -n1 | awk -F': ' '{print $2}' | awk '{print $1}')
        fi
    fi
    
    if [[ -z "$INTERFACE" ]] && [ -d /sys/class/net ]; then
        for iface in /sys/class/net/*; do
            ifname=$(basename "$iface")
            if [[ "$ifname" != "lo" ]] && [ -f "$iface/operstate" ]; then
                if grep -q "up" "$iface/operstate" 2>/dev/null || [ -f "$iface/carrier" ]; then
                    INTERFACE="$ifname"
                    break
                fi
            fi
        done
    fi
    
    IPTABLES_CMD=""
    if command -v iptables &> /dev/null; then
        IPTABLES_CMD=$(command -v iptables)
    elif [ -f /sbin/iptables ]; then
        IPTABLES_CMD="/sbin/iptables"
    elif [ -f /usr/sbin/iptables ]; then
        IPTABLES_CMD="/usr/sbin/iptables"
    fi
    
    if [[ -n "$INTERFACE" ]] && [[ -n "$IPTABLES_CMD" ]]; then
        for port in {7012..7050}; do
            $IPTABLES_CMD -t nat -D PREROUTING -i $INTERFACE -p udp --dport $port -j REDIRECT --to-ports $HYSTERIA_PORT 2>/dev/null
        done
        
        IP6TABLES_CMD=""
        if command -v ip6tables &> /dev/null; then
            IP6TABLES_CMD=$(command -v ip6tables)
        elif [ -f /sbin/ip6tables ]; then
            IP6TABLES_CMD="/sbin/ip6tables"
        elif [ -f /usr/sbin/ip6tables ]; then
            IP6TABLES_CMD="/usr/sbin/ip6tables"
        fi
        
        if [[ -n "$IP6TABLES_CMD" ]]; then
            for port in {7012..7050}; do
                $IP6TABLES_CMD -t nat -D PREROUTING -i $INTERFACE -p udp --dport $port -j REDIRECT --to-ports $HYSTERIA_PORT 2>/dev/null
            done
        fi
        
        if [ -d /etc/iptables ]; then
            if command -v iptables-save &> /dev/null; then
                iptables-save > /etc/iptables/rules.v4 2>/dev/null
            elif [ -f /sbin/iptables-save ]; then
                /sbin/iptables-save > /etc/iptables/rules.v4 2>/dev/null
            elif [ -f /usr/sbin/iptables-save ]; then
                /usr/sbin/iptables-save > /etc/iptables/rules.v4 2>/dev/null
            fi
        fi
        if [ -f /etc/sysconfig/iptables ]; then
            if command -v iptables-save &> /dev/null; then
                iptables-save > /etc/sysconfig/iptables 2>/dev/null
            elif [ -f /sbin/iptables-save ]; then
                /sbin/iptables-save > /etc/sysconfig/iptables 2>/dev/null
            elif [ -f /usr/sbin/iptables-save ]; then
                /usr/sbin/iptables-save > /etc/sysconfig/iptables 2>/dev/null
            fi
        fi
        
        systemctl stop iptables-restore >/dev/null 2>&1
        systemctl disable iptables-restore >/dev/null 2>&1
        rm -f /etc/systemd/system/iptables-restore.service
        systemctl daemon-reload
        
        green "✅ iptables 规则已清理"
    fi

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
    if [ ! -f "/root/hy/url.txt" ]; then
        red "配置文件不存在"
        return
    fi

    green "======================================================================================"
    if [ -f "/root/hy/hy-client.yaml" ]; then
        yellow "YAML配置文件 (/root/hy/hy-client.yaml):"
        cat /root/hy/hy-client.yaml
        echo ""
    fi

    if [ -f "/root/hy/url.txt" ]; then
        yellow "分享链接:"
        red "$(cat /root/hy/url.txt)"
    fi
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

menu() {
    clear
    echo "#############################################################"
    echo -e "#                 ${GREEN}Hysteria 2 一键配置脚本1${PLAIN}                  #"
    echo "#############################################################"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} 安装 Hysteria 2"
    echo -e " ${RED}2.${PLAIN} 卸载 Hysteria 2"
    echo "------------------------------------------------------------"
    echo -e " ${GREEN}3.${PLAIN} 关闭、开启、重启 Hysteria 2"
    echo -e " ${GREEN}4.${PLAIN} 显示 Hysteria 2 配置文件"
    echo "------------------------------------------------------------"
    echo -e " ${GREEN}5.${PLAIN} 修改端口"
    echo -e " ${GREEN}0.${PLAIN} 退出脚本"
    echo ""
    read -rp "请输入选项 [0-5]: " menuInput
    case $menuInput in
        1) install_hy2 ;;
        2) uninstall_hy2 ;;
        3) service_menu ;;
        4) show_config ;;
        5) change_port ;;
        0) exit 0 ;;
        *) red "请输入正确的选项 [0-5]" && exit 1 ;;
    esac
}

change_port() {
    read -rp "请输入新的端口号: " new_port
    if [[ ! $new_port =~ ^[0-9]+$ ]] || [[ $new_port -lt 1 ]] || [[ $new_port -gt 65535 ]]; then
        red "端口号无效，请输入1-65535之间的数字。"
        sleep 2
        menu
        return
    fi
    if [ -f /etc/hysteria/config.yaml ]; then
        sed -i "s/^listen: :[0-9]\+/listen: :$new_port/" /etc/hysteria/config.yaml
    fi
    if [ -f /root/hy/hy-client.yaml ]; then
        sed -i "s/^server: \(.*\):[0-9]\+/server: \1:$new_port/" /root/hy/hy-client.yaml
    fi
    if [ -f /root/hy/hy-client.json ]; then
        sed -i "s/\("server": ".*:\)[0-9]\+\("\)/\1$new_port\2/" /root/hy/hy-client.json
    fi
    if [ -f /root/hy/url.txt ]; then
        sed -i "s/\(@.*:\)[0-9]\+\//\1$new_port\//" /root/hy/url.txt
    fi
    green "配置文件端口已修改为: $new_port，请重启Hysteria 2服务使其生效。"
    sleep 2
    menu
}

menu
