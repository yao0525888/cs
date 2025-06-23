#!/bin/bash

# 颜色定义
LIGHT_GREEN='\033[1;32m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# 国家代码转中文映射表（全局只声明一次）
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

# FRPS配置
FRP_VERSION="v0.62.1"
FRPS_PORT="7006"
FRPS_TOKEN="DFRN2vbG123"
SILENT_MODE=true

# 获取FRPS连接密码的函数
gen_frps_token() {
    echo "$FRPS_TOKEN"
}
FRPS_TOKEN=$(gen_frps_token)

# 日志函数
log_info() {
    if [[ "$SILENT_MODE" == "true" ]]; then
        return
    fi
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_step() {
    echo -e "${YELLOW}[$1/$2] $3${NC}"
}

log_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

log_error() {
    echo -e "${RED}[错误]${NC} $1"
    exit 1
}

log_sub_step() {
    if [[ "$SILENT_MODE" == "true" ]]; then
        return
    fi
    echo -e "${GREEN}[$1/$2]$3${NC}"
}

# 检查root权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 sudo 或 root 权限运行脚本"
    fi
}

# 卸载旧版FRPS
uninstall_frps() {
    log_info "卸载旧版FRPS服务..."
    systemctl stop frps >/dev/null 2>&1
    systemctl disable frps >/dev/null 2>&1
    rm -f /etc/systemd/system/frps.service
    rm -rf /usr/local/frp /etc/frp
    systemctl daemon-reload >/dev/null 2>&1
}

# 安装FRPS
install_frps() {
    log_step "1" "2" "安装FRPS服务..."
    uninstall_frps
    local FRP_NAME="frp_${FRP_VERSION#v}_linux_amd64"
    local FRP_FILE="${FRP_NAME}.tar.gz"
    cd /usr/local/ || exit 1
    log_info "下载FRPS（版本：${FRP_VERSION}）..."
    if ! wget -q "https://github.com/fatedier/frp/releases/download/${FRP_VERSION}/${FRP_FILE}" -O "${FRP_FILE}" >/dev/null 2>&1; then
        log_error "FRPS下载失败"
    fi
    log_info "解压FRPS安装包..."
    if ! tar -zxf "${FRP_FILE}" >/dev/null 2>&1; then
        rm -f "${FRP_FILE}"
        log_error "FRPS解压失败"
    fi
    cd "${FRP_NAME}" || log_error "无法进入解压目录"
    rm -f frpc*
    log_info "安装FRPS可执行文件..."
    mkdir -p /usr/local/frp || log_error "创建 /usr/local/frp 目录失败"
    if ! cp frps /usr/local/frp/; then
        log_error "拷贝 frps 可执行文件失败"
    fi
    chmod +x /usr/local/frp/frps
    if [ $? -ne 0 ]; then
        log_error "设置 frps 可执行权限失败"
    fi
    log_info "创建FRPS配置文件..."
    mkdir -p /etc/frp || log_error "创建 /etc/frp 目录失败"
    cat > /etc/frp/frps.toml << EOF
bindAddr = "0.0.0.0"
bindPort = ${FRPS_PORT}
auth.method = "token"
auth.token = "${FRPS_TOKEN}"
EOF
    if [ $? -ne 0 ]; then
        log_error "写入 frps.toml 配置文件失败"
    fi
    log_info "创建FRPS服务单元..."
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
        log_error "写入 frps.service 文件失败"
    fi

    
    systemctl daemon-reload
    if [ $? -ne 0 ]; then
        log_error "重新加载 systemd 配置失败"
    fi
    systemctl enable frps >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        log_error "启用 frps 服务失败"
    fi
    log_info "启用并启动FRPS服务..."
    systemctl start frps >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        log_error "启动 frps 服务失败"
    fi
    
    if systemctl is-active frps >/dev/null 2>&1; then
        log_success "FRPS服务已成功启动"
    else
        log_error "FRPS服务启动失败"
    fi
    
    rm -f /usr/local/${FRP_FILE}
    rm -rf /usr/local/${FRP_NAME}
    
    log_success "FRPS安装成功"
    
    # 清理临时文件
    cleanup
    
    # 添加定时清理日志任务
    add_cron_job
}

# 安装Xray
install_xray() {
    log_step "2" "2" "安装Xray服务..."
    # 确保在可写的目录中工作
    cd /usr/local/ || exit 1
    
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="64" ;;
        aarch64) ARCH="arm64-v8a" ;;
        armv7l) ARCH="arm32-v7a" ;;
        *) log_error "不支持的架构" ;;
    esac

    # 推荐优先用 jq
    if command -v jq >/dev/null 2>&1; then
        VER=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)
    else
        VER=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep '"tag_name"' | head -n 1 | cut -d '"' -f 4)
    fi
    if [ -z "$VER" ]; then
        log_error "获取 Xray 版本号失败"
    fi
    log_info "Xray 最新版本号: $VER"
    URL="https://github.com/XTLS/Xray-core/releases/download/$VER/Xray-linux-$ARCH.zip"
    wget -q -O xray.zip $URL
    if [ ! -s xray.zip ]; then
        log_error "Xray 安装包下载失败，文件不存在或为空，URL: $URL"
    fi
    if ! unzip -q -o xray.zip; then
        log_error "Xray 安装包解压失败，可能下载失败或文件损坏"
    fi
    if [ ! -f xray ]; then
        log_error "Xray 主程序未找到，安装失败"
    fi
    chmod +x xray
    mv xray /usr/local/bin/ >/dev/null 2>&1
    mv geoip.dat geosite.dat /usr/local/bin/ >/dev/null 2>&1
    rm -f xray.zip LICENSE README.md >/dev/null 2>&1

    # 配置参数
    SHORTID="63b5508a"
    UUID="9e264d67-fe47-4d2f-b55e-631a12e46a30"
    PRIVATE_KEY="KHdBejDOTXA3gBwkbkC1yX3QGBiCqolz-CZsc0d2WGo"
    PUBLIC_KEY="1A8ttanG5p970QYWyVoABiHoXYoPL-DrVFd3flFxPCo"
    PORT=443
    ALPN="h2"
    FLOW="xtls-rprx-vision"
    SNI="www.bing.com"
    DOMAIN=$(curl -s ifconfig.me)

    # 获取地区信息
    COUNTRY_CODE=$(curl -s "https://ipinfo.io/$DOMAIN/country")
    REGION=${COUNTRY_MAP[$COUNTRY_CODE]}
    [ -z "$REGION" ] && REGION="$COUNTRY_CODE"

    # 生成配置文件
    mkdir -p /usr/local/etc/xray >/dev/null 2>&1
    cat > /usr/local/etc/xray/config.json <<EOF
{
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "$FLOW"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$SNI:$PORT",
          "xver": 0,
          "serverNames": ["$SNI"],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": ["$SHORTID"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {"domainStrategy": "UseIPv4"}
    }
  ]
}
EOF

    # 配置systemd服务
    cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
ExecStart=/usr/local/bin/xray -config /usr/local/etc/xray/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    # 启动服务
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable xray >/dev/null 2>&1
    systemctl start xray >/dev/null 2>&1
    log_success "Xray安装成功"
}

# 添加定时任务
add_cron_job() {
    local cron_entry="24 15 24 * * find /usr/local -type f -name "*.log" -delete"
    (crontab -l 2>/dev/null | grep -v -F "$cron_entry"; echo "$cron_entry") | crontab -
}

# 清理临时文件
cleanup() {
    rm -rf /usr/local/frp_* /usr/local/frp_*_linux_amd64
}

# 显示FRPS信息
show_frps_info() {
    echo -e "\n${YELLOW}>>> FRPS服务状态：${NC}"
    systemctl is-active frps
    echo -e "\n${YELLOW}>>> FRPS信息：${NC}"
    echo -e "服务器地址: $(curl -s ifconfig.me || hostname -I | awk '{print $1}')"
    echo -e "FRPS 密码: $FRPS_TOKEN"
    echo -e "TCP端口: $FRPS_PORT"
}

# 显示结果
show_results() {
    echo -e "\n${YELLOW}>>> FRPS服务状态：${NC}"
    systemctl is-active frps
    echo -e "\n${YELLOW}>>> Xray服务状态：${NC}"
    systemctl is-active xray
    echo -e "\n${YELLOW}>>> FRPS信息：${NC}"
    echo -e "服务器地址: $(curl -s ifconfig.me || hostname -I | awk '{print $1}')"
    echo -e "FRPS 密码: $FRPS_TOKEN"
    echo -e "TCP端口: $FRPS_PORT"

    echo -e "\n${YELLOW}>>> Xray Reality 分享链接：${NC}"
    LINK="vless://$UUID@$DOMAIN:$PORT?encryption=none&flow=$FLOW&security=reality&sni=$SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORTID&type=tcp&alpn=$ALPN#$REGION"
    echo -e "${GREEN}$LINK${NC}\n"
}

# 卸载Xray
uninstall_xray() {
    log_step "1" "1" "卸载Xray服务..."
    systemctl stop xray >/dev/null 2>&1
    systemctl disable xray >/dev/null 2>&1
    rm -f /etc/systemd/system/xray.service
    rm -rf /usr/local/etc/xray
    rm -f /usr/local/bin/xray
    rm -f /usr/local/bin/geoip.dat
    rm -f /usr/local/bin/geosite.dat
    systemctl daemon-reload >/dev/null 2>&1
    log_success "Xray卸载成功"
}

# 显示Xray信息
show_xray_info() {
    echo -e "\n${YELLOW}>>> Xray服务状态：${NC}"
    systemctl is-active xray
    # 读取参数
    if command -v jq >/dev/null 2>&1; then
        UUID=$(jq -r '.inbounds[0].settings.clients[0].id' /usr/local/etc/xray/config.json)
        FLOW=$(jq -r '.inbounds[0].settings.clients[0].flow' /usr/local/etc/xray/config.json)
        SNI=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' /usr/local/etc/xray/config.json)
        SHORTID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' /usr/local/etc/xray/config.json)
        PRIVATE_KEY=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' /usr/local/etc/xray/config.json)
        PORT=$(jq -r '.inbounds[0].port' /usr/local/etc/xray/config.json)
        NET=$(jq -r '.inbounds[0].streamSettings.network' /usr/local/etc/xray/config.json)
    else
        UUID=$(grep -oP '"id": *"\K[^"]+' /usr/local/etc/xray/config.json)
        FLOW=$(grep -oP '"flow": *"\K[^"]+' /usr/local/etc/xray/config.json)
        SNI=$(grep -oP '"serverNames": *\[ *"\K[^"]+' /usr/local/etc/xray/config.json)
        SHORTID=$(grep -oP '"shortIds": *\[ *"\K[^"]+' /usr/local/etc/xray/config.json)
        PRIVATE_KEY=$(grep -oP '"privateKey": *"\K[^"]+' /usr/local/etc/xray/config.json)
        PORT=$(grep -oP '"port": *\K[0-9]+' /usr/local/etc/xray/config.json | head -1)
        NET=$(grep -oP '"network": *"\K[^"]+' /usr/local/etc/xray/config.json)
    fi
    PUBLIC_KEY="1A8ttanG5p970QYWyVoABiHoXYoPL-DrVFd3flFxPCo"
    ALPN="h2"
    DOMAIN=$(curl -s ifconfig.me)
    REGION="$(curl -s "https://ipinfo.io/$DOMAIN/country")"
    REGION_CN=${COUNTRY_MAP[$REGION]}
    [ -z "$REGION_CN" ] && REGION_CN="$REGION"
    LINK="vless://$UUID@$DOMAIN:$PORT?encryption=none&flow=$FLOW&security=reality&sni=$SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORTID&type=$NET&alpn=$ALPN#$REGION_CN"
    echo -e "\n${YELLOW}>>> Xray Reality 分享链接：${NC}"
    echo -e "${GREEN}$LINK${NC}\n"
}

# 显示菜单
show_menu() {
    echo -e "${YELLOW}=== Xray & FRPS 管理脚本 ===${NC}"
    echo -e "${GREEN}1.${NC} 安装 Xray + FRPS"
    echo -e "${GREEN}2.${NC} 仅安装 Xray"
    echo -e "${GREEN}3.${NC} 仅安装 FRPS"
    echo -e "${GREEN}4.${NC} 卸载 Xray"
    echo -e "${GREEN}5.${NC} 卸载 FRPS"
    echo -e "${GREEN}6.${NC} 卸载 Xray + FRPS"
    echo -e "${GREEN}7.${NC} 查看 Xray 信息"
    echo -e "${GREEN}8.${NC} 查看 FRPS 信息"
    echo -e "${GREEN}0.${NC} 退出脚本"
    echo -e "${YELLOW}===========================${NC}"
}

# 主函数
main() {
    check_root
    
    while true; do
        show_menu
        read -p "请选择操作 [0-8]: " choice
        
        case $choice in
            1)
                install_frps
                install_xray
                add_cron_job
                cleanup
                show_results
                ;;
            2)
                install_xray
                show_xray_info
                ;;
            3)
                install_frps
                show_frps_info
                ;;
            4)
                uninstall_xray
                ;;
            5)
                uninstall_frps
                ;;
            6)
                uninstall_xray
                uninstall_frps
                log_success "所有服务已卸载"
                ;;
            7)
                show_xray_info
                ;;
            8)
                show_frps_info
                ;;
            0)
                echo -e "${GREEN}退出脚本${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效的选择，请重试${NC}"
                ;;
        esac
        
        if [ "$choice" != "0" ]; then
            echo -e "\n${YELLOW}按回车键返回主菜单...${NC}"
            read -s
        fi
    done
}

main