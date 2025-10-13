module.exports = {
    admin_password: process.env.ADMIN_PASSWORD || "Qaz123456!",
    vpn_hub: process.env.VPN_HUB || "DEFAULT",
    vpn_user: process.env.VPN_USER || "pi",
    vpn_password: process.env.VPN_PASSWORD || "8888888888!",
    dhcp: {
        start: process.env.DHCP_START || "192.168.30.10",
        end: process.env.DHCP_END || "192.168.30.20",
        mask: process.env.DHCP_MASK || "255.255.255.0",
        gw: process.env.DHCP_GW || "192.168.30.1",
        dns1: process.env.DHCP_DNS1 || "192.168.30.1",
        dns2: process.env.DHCP_DNS2 || "8.8.8.8"
    },
    frp: {
        version: process.env.FRP_VERSION || "v0.62.1",
        port: process.env.FRPS_PORT || "7007",
        dashboard_port: process.env.FRPS_DASHBOARD_PORT || "31410",
        token: process.env.FRPS_TOKEN || "DFRN2vbG123",
        dashboard_user: process.env.FRPS_DASHBOARD_USER || "admin",
        dashboard_pwd: process.env.FRPS_DASHBOARD_PWD || "yao581581"
    }
};

