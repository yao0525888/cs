#!/bin/bash

# 颜色定义
LIGHT_GREEN='\033[1;32m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

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
    log_step "2" "2" "安装FRPS服务..."
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
    mkdir -p /etc/frp || exit 1
    cat > /etc/frp/frps.toml << EOF
bindAddr = "0.0.0.0"
bindPort = ${FRPS_PORT}
auth.method = "token"
auth.token = "${FRPS_TOKEN}"
EOF
    if [ $? -ne 0 ]; then
        log_error "写入 frps.toml 配置文件失败"
    fi
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
}

# 安装Xray
install_xray() {
    log_step "1" "2" "安装Xray服务..."
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

# 主函数
main() {
    check_root
    install_xray
    install_frps
    add_cron_job
    cleanup
    show_results
}

main