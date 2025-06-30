#!/bin/bash
echo "脚本开始执行..."
export LANG=en_US.UTF-8
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"
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

    # 下载预设的密钥和证书文件
    wget -O /etc/hysteria/private.key https://github.com/yao0525888/hysteria/releases/download/hysteria2/private.key > /dev/null 2>&1
    wget -O /etc/hysteria/cert.crt https://github.com/yao0525888/hysteria/releases/download/hysteria2/cert.crt > /dev/null 2>&1
    chmod 644 /etc/hysteria/cert.crt /etc/hysteria/private.key

    auth_pwd="9e264d67-fe47-4d2f-b55e-631a12e46a30"

    cat << EOF > /etc/hysteria/config.yaml
listen: :443

tls:
  cert: /etc/hysteria/cert.crt
  key: /etc/hysteria/private.key

quic:
  initStreamReceiveWindow: 16777216
  maxStreamReceiveWindow: 16777216
  initConnReceiveWindow: 33554432
  maxConnReceiveWindow: 33554432

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

    mkdir -p /root/hy

    node_name=$(get_ip_region "$ip")

    cat << EOF > /root/hy/hy-client.yaml
server: $last_ip:443

auth: $auth_pwd

tls:
  sni: www.bing.com
  insecure: true

quic:
  initStreamReceiveWindow: 16777216
  maxStreamReceiveWindow: 16777216
  initConnReceiveWindow: 33554432
  maxConnReceiveWindow: 33554432

fastOpen: true

transport:
  udp:
    hopInterval: 30s 
EOF

    cat << EOF > /root/hy/hy-client.json
{
  "server": "$last_ip:443",
  "auth": "$auth_pwd",
  "tls": {
    "sni": "www.bing.com",
    "insecure": true
  },
  "quic": {
    "initStreamReceiveWindow": 16777216,
    "maxStreamReceiveWindow": 16777216,
    "initConnReceiveWindow": 33554432,
    "maxConnReceiveWindow": 33554432
  },
  "transport": {
    "udp": {
      "hopInterval": "30s"
    }
  }
}
EOF

    url="hysteria2://$auth_pwd@$last_ip:443/?insecure=1&sni=www.bing.com#$node_name"
    echo $url > /root/hy/url.txt

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
        yellow "端口: 443"
        yellow "密码: $auth_pwd"
        yellow "伪装网站: www.bing.com"
        yellow "TLS SNI: www.bing.com"
        yellow "节点名称: $node_name"
        echo ""
        yellow "客户端配置已保存到: /root/hy/"
        yellow "分享链接:"
        red "$url"
        green "======================================================================================"
    else
        red "Hysteria 2 服务启动失败，请检查日志" && exit 1
    fi
}

uninstall_hy2() {
    systemctl stop hysteria-server >/dev/null 2>&1
    systemctl disable hysteria-server >/dev/null 2>&1
    systemctl disable hysteria-autostart >/dev/null 2>&1

    rm -f /etc/systemd/system/hysteria-autostart.service
    rm -f /lib/systemd/system/hysteria-server.service /lib/systemd/system/hysteria-server@.service
    rm -rf /usr/local/bin/hysteria /etc/hysteria /root/hy

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

modify_port() {
    if [[ ! -f "/etc/hysteria/config.yaml" ]]; then
        red "Hysteria 2 配置文件不存在，请先安装 Hysteria 2"
        return
    fi

    yellow "当前端口设置:"
    current_port=$(grep "listen:" /etc/hysteria/config.yaml | awk -F ':' '{print $3}')
    if [[ -z "$current_port" ]]; then
        current_port="443"
    fi
    yellow "当前端口: $current_port"
    
    read -rp "请输入新的端口号 [1-65535]: " new_port
    
    # 验证端口号
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        red "无效的端口号，请输入1-65535之间的数字"
        return
    fi
    
    # 检查端口是否被占用
    if netstat -tuln | grep -q ":$new_port "; then
        red "端口 $new_port 已被占用，请选择其他端口"
        return
    fi
    
    # 修改配置文件
    sed -i "s/listen: :$current_port/listen: :$new_port/" /etc/hysteria/config.yaml
    
    # 更新客户端配置
    realip
    if [[ -n $(echo $ip | grep ":") ]]; then
        last_ip="[$ip]"
    else
        last_ip=$ip
    fi
    
    node_name=$(get_ip_region "$ip")
    auth_pwd=$(grep "password:" /etc/hysteria/config.yaml | awk '{print $2}')
    
    # 更新客户端YAML配置
    if [[ -f "/root/hy/hy-client.yaml" ]]; then
        sed -i "s/server: $last_ip:$current_port/server: $last_ip:$new_port/" /root/hy/hy-client.yaml
    fi
    
    # 更新客户端JSON配置
    if [[ -f "/root/hy/hy-client.json" ]]; then
        sed -i "s/\"server\": \"$last_ip:$current_port\"/\"server\": \"$last_ip:$new_port\"/" /root/hy/hy-client.json
    fi
    
    # 更新URL分享链接
    url="hysteria2://$auth_pwd@$last_ip:$new_port/?insecure=1&sni=www.bing.com#$node_name"
    echo $url > /root/hy/url.txt
    
    # 重启服务
    systemctl restart hysteria-server
    sleep 2
    
    if [[ -n $(systemctl status hysteria-server 2>/dev/null | grep -w active) ]]; then
        green "======================================================================================"
        green "Hysteria 2 端口修改成功！"
        yellow "新端口: $new_port"
        yellow "密码: $auth_pwd"
        yellow "伪装网站: www.bing.com"
        yellow "TLS SNI: www.bing.com"
        yellow "节点名称: $node_name"
        echo ""
        yellow "客户端配置已更新到: /root/hy/"
        yellow "新的分享链接:"
        red "$url"
        green "======================================================================================"
    else
        red "Hysteria 2 服务重启失败，请检查日志"
    fi
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
    echo -e " ${GREEN}4.${PLAIN} 修改 Hysteria 2 端口"
    echo -e " ${GREEN}0.${PLAIN} 返回主菜单"
    echo ""
    read -rp "请输入选项 [0-4]: " switchInput
    case $switchInput in
        1) start_hy2 ;;
        2) stop_hy2 ;;
        3) restart_hy2 ;;
        4) modify_port ;;
        0) menu ;;
        *) red "无效选项" ;;
    esac
    menu
}


menu() {
    clear
    echo "#############################################################"
    echo -e "#                 ${GREEN}Hysteria 2 一键配置脚本${PLAIN}                  #"
    echo "#############################################################"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} 安装 Hysteria 2 (端口443, 自签证书)"
    echo -e " ${RED}2.${PLAIN} 卸载 Hysteria 2"
    echo "------------------------------------------------------------"
    echo -e " ${GREEN}3.${PLAIN} 关闭、开启、重启 Hysteria 2"
    echo -e " ${GREEN}4.${PLAIN} 显示 Hysteria 2 配置文件"
    echo -e " ${GREEN}5.${PLAIN} 修改 Hysteria 2 端口"
    echo "------------------------------------------------------------"
    echo -e " ${GREEN}0.${PLAIN} 退出脚本"
    echo ""
    read -rp "请输入选项 [0-5]: " menuInput
    case $menuInput in
        1) install_hy2 ;;
        2) uninstall_hy2 ;;
        3) service_menu ;;
        4) show_config ;;
        5) modify_port ;;
        0) exit 0 ;;
        *) red "请输入正确的选项 [0-5]" && exit 1 ;;
    esac
}

# 调用主菜单
echo "调用主菜单..."
menu
