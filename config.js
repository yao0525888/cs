module.exports = {
    admin_password: "Qaz123456!",
    vpn_hub: "DEFAULT",
    vpn_user: "pi",
    vpn_password: "8888888888!",
    enableLimit: true,
    configDownloadUrl: "https://raw.githubusercontent.com/your-repo/config/main/config.json",
    dhcp: {
        start: "192.168.30.10",
        end: "192.168.30.20",
        mask: "255.255.255.0",
        gw: "192.168.30.1",
        dns1: "192.168.30.1",
        dns2: "8.8.8.8"
    },
    frp: {
        version: "v0.62.1",
        port: "7007",
        dashboard_port: "31410",
        token: "DFRN2vbG123",
        dashboard_user: "admin",
        dashboard_pwd: "yao581581"
    }
};

