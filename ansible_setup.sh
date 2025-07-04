#!/bin/bash

# Ansible一键安装配置脚本
# 支持多种Linux发行版

# 设置颜色
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # 无颜色

# 检查是否以root用户运行
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}请以root用户运行此脚本！${NC}"
  echo "使用 sudo su 或 sudo 运行此脚本"
  exit 1
fi

# 创建日志文件
LOG_FILE="/tmp/ansible_setup_$(date +%Y%m%d%H%M%S).log"
touch $LOG_FILE
exec &> >(tee -a "$LOG_FILE")

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}     Ansible 服务端一键安装配置脚本       ${NC}"
echo -e "${GREEN}============================================${NC}"
echo -e "${YELLOW}开始时间: $(date)${NC}"
echo ""

# 函数: 检查命令执行状态
check_status() {
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}[✓] $1 成功${NC}"
  else
    echo -e "${RED}[✗] $1 失败${NC}"
    echo -e "${RED}请查看日志文件: $LOG_FILE${NC}"
    exit 1
  fi
}

# 函数: 检测Linux发行版
detect_distro() {
  echo -e "${YELLOW}检测Linux发行版...${NC}"
  
  # 检查是否存在lsb_release命令
  if command -v lsb_release &> /dev/null; then
    DISTRO=$(lsb_release -si)
    VERSION=$(lsb_release -sr)
  # 检查是否存在/etc/os-release文件
  elif [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
    VERSION=$VERSION_ID
  # 检查是否存在/etc/redhat-release文件
  elif [ -f /etc/redhat-release ]; then
    DISTRO="rhel"
    VERSION=$(cat /etc/redhat-release | sed 's/.*release \([0-9]\).*/\1/')
  else
    DISTRO="unknown"
    VERSION="unknown"
  fi
  
  # 转换为小写
  DISTRO=$(echo "$DISTRO" | tr '[:upper:]' '[:lower:]')
  
  echo -e "检测到系统: ${GREEN}$DISTRO $VERSION${NC}"
  return 0
}

# 函数: 安装Ansible (Debian/Ubuntu)
install_ansible_debian() {
  echo -e "${YELLOW}使用APT安装Ansible...${NC}"
  
  # 更新软件包列表
  echo "正在更新软件包列表..."
  apt-get update -y
  check_status "更新软件包列表"
  
  # 安装必要的依赖
  echo "正在安装依赖..."
  apt-get install -y software-properties-common curl gnupg lsb-release python3 python3-pip
  check_status "安装依赖"
  
  # 尝试添加PPA仓库，如果失败则使用标准仓库
  echo "添加Ansible仓库..."
  if apt-add-repository --yes --update ppa:ansible/ansible; then
    check_status "添加Ansible PPA仓库"
  else
    echo -e "${YELLOW}PPA添加失败，使用标准仓库安装${NC}"
    # 直接安装ansible
    apt-get install -y ansible
    check_status "安装Ansible(标准仓库)"
  fi
  
  # 如果上面的PPA添加成功，安装ansible
  if [ $? -eq 0 ]; then
    echo "安装Ansible..."
    apt-get install -y ansible
    check_status "安装Ansible"
  fi
}

# 函数: 安装Ansible (RHEL/CentOS)
install_ansible_rhel() {
  echo -e "${YELLOW}使用YUM/DNF安装Ansible...${NC}"
  
  # 检查版本
  if [[ "$VERSION" == "7" ]]; then
    # RHEL/CentOS 7 使用EPEL和yum
    echo "安装EPEL仓库..."
    yum install -y epel-release
    check_status "安装EPEL仓库"
    
    echo "安装依赖..."
    yum install -y python3 python3-pip
    check_status "安装依赖"
    
    echo "安装Ansible..."
    yum install -y ansible
    check_status "安装Ansible"
  else
    # RHEL/CentOS 8+ 使用dnf
    echo "安装依赖..."
    dnf install -y python3 python3-pip
    check_status "安装依赖"
    
    echo "启用EPEL仓库..."
    dnf install -y epel-release
    check_status "启用EPEL仓库"
    
    echo "安装Ansible..."
    dnf install -y ansible
    check_status "安装Ansible"
  fi
}

# 函数: 通过pip安装Ansible
install_ansible_pip() {
  echo -e "${YELLOW}使用pip安装Ansible...${NC}"
  
  # 安装python3和pip
  if [[ "$DISTRO" == "debian" || "$DISTRO" == "ubuntu" ]]; then
    apt-get update -y
    apt-get install -y python3 python3-pip
  elif [[ "$DISTRO" == "rhel" || "$DISTRO" == "centos" || "$DISTRO" == "fedora" ]]; then
    if [[ "$VERSION" == "7" ]]; then
      yum install -y python3 python3-pip
    else
      dnf install -y python3 python3-pip
    fi
  else
    echo -e "${YELLOW}未知发行版，尝试通用方法安装Python...${NC}"
    # 尝试通用方法
    if command -v apt-get &> /dev/null; then
      apt-get update -y
      apt-get install -y python3 python3-pip
    elif command -v yum &> /dev/null; then
      yum install -y python3 python3-pip
    elif command -v dnf &> /dev/null; then
      dnf install -y python3 python3-pip
    else
      echo -e "${RED}无法安装Python和pip，请手动安装后重试${NC}"
      exit 1
    fi
  fi
  check_status "安装Python和pip"
  
  # 升级pip
  python3 -m pip install --upgrade pip
  check_status "升级pip"
  
  # 安装ansible
  python3 -m pip install ansible
  check_status "通过pip安装Ansible"
}

# 函数: 安装Ansible
install_ansible() {
  echo -e "${YELLOW}[1/6] 正在安装Ansible...${NC}"
  
  # 检测发行版
  detect_distro
  
  # 根据发行版选择安装方法
  if [[ "$DISTRO" == "debian" || "$DISTRO" == "ubuntu" ]]; then
    install_ansible_debian
  elif [[ "$DISTRO" == "rhel" || "$DISTRO" == "centos" || "$DISTRO" == "fedora" || "$DISTRO" == "rocky" || "$DISTRO" == "almalinux" ]]; then
    install_ansible_rhel
  else
    echo -e "${YELLOW}未知发行版，尝试使用pip安装...${NC}"
    install_ansible_pip
  fi
  
  # 验证安装
  if command -v ansible &> /dev/null; then
    ANSIBLE_VERSION=$(ansible --version | head -n1)
    echo -e "${GREEN}Ansible安装完成! 版本: $ANSIBLE_VERSION${NC}"
  else
    echo -e "${RED}Ansible安装失败！尝试使用pip安装...${NC}"
    install_ansible_pip
    if command -v ansible &> /dev/null; then
      ANSIBLE_VERSION=$(ansible --version | head -n1)
      echo -e "${GREEN}Ansible通过pip安装完成! 版本: $ANSIBLE_VERSION${NC}"
    else
      echo -e "${RED}Ansible安装失败！请手动安装${NC}"
      exit 1
    fi
  fi
}

# 函数: 创建项目目录结构
create_directory_structure() {
  echo -e "${YELLOW}[2/6] 创建项目目录结构...${NC}"
  
  # 创建项目目录
  PROJECT_DIR="/etc/ansible/projects/ansible-deploy"
  mkdir -p $PROJECT_DIR/{inventory,group_vars,host_vars,roles,templates,files,playbooks}
  check_status "创建项目目录"
  
  # 创建角色目录结构
  mkdir -p $PROJECT_DIR/roles/common/{tasks,handlers,templates,files,vars,defaults,meta}
  check_status "创建角色目录"
  
  # 设置权限
  chown -R root:root $PROJECT_DIR
  chmod -R 755 $PROJECT_DIR
  check_status "设置目录权限"
  
  echo "项目目录创建完成: $PROJECT_DIR"
}

# 函数: 创建配置文件
create_config_files() {
  echo -e "${YELLOW}[3/6] 创建配置文件...${NC}"
  
  # 创建ansible.cfg
  cat > $PROJECT_DIR/ansible.cfg << EOF
[defaults]
inventory = ./inventory/hosts
remote_user = root
host_key_checking = False
forks = 20
timeout = 30
log_path = /var/log/ansible.log
roles_path = ./roles
deprecation_warnings = False
gathering = smart
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts_cache
fact_caching_timeout = 86400

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False

[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=60s
pipelining = True
transfer_method = smart
retries = 3
EOF
  check_status "创建ansible.cfg"
  
  # 创建hosts文件
  cat > $PROJECT_DIR/inventory/hosts << EOF
# Ansible主机清单文件

[webservers]
# web1 ansible_host=192.168.1.101
# web2 ansible_host=192.168.1.102

[dbservers]
# db1 ansible_host=192.168.1.201
# db2 ansible_host=192.168.1.202

[windows]
# win1 ansible_host=192.168.1.150 ansible_user=Administrator ansible_password=Password
# win2 ansible_host=192.168.1.151 ansible_user=Administrator ansible_password=Password

[windows:vars]
ansible_connection=winrm
ansible_winrm_server_cert_validation=ignore
ansible_port=5985

[all:vars]
ansible_ssh_user=root
# ansible_ssh_private_key_file=~/.ssh/id_rsa
# ansible_python_interpreter=/usr/bin/python3
EOF
  check_status "创建hosts文件"
  
  # 创建group_vars
  cat > $PROJECT_DIR/group_vars/all.yml << EOF
---
# 所有主机的共享变量
timezone: Asia/Shanghai
ntp_server: ntp.aliyun.com
EOF
  check_status "创建group_vars"
  
  # 创建通用角色任务
  cat > $PROJECT_DIR/roles/common/tasks/main.yml << EOF
---
# 通用角色的主要任务

- name: 确保系统已更新
  apt:
    update_cache: yes
    cache_valid_time: 3600
  when: ansible_os_family == "Debian"

- name: 确保系统已更新(RedHat系列)
  yum:
    name: '*'
    state: latest
    update_cache: yes
  when: ansible_os_family == "RedHat"

- name: 安装基础软件包
  package:
    name:
      - vim
      - curl
      - wget
      - htop
      - git
      - zip
      - unzip
      - ntp
    state: present

- name: 设置时区
  timezone:
    name: "{{ timezone }}"
EOF
  check_status "创建通用角色"
  
  # 创建示例playbook
  cat > $PROJECT_DIR/playbooks/site.yml << EOF
---
# 主playbook

- name: 应用通用配置
  hosts: all
  roles:
    - common
EOF
  check_status "创建示例playbook"
  
  # 创建ping测试脚本
  cat > $PROJECT_DIR/playbooks/ping.yml << EOF
---
# 简单的ping测试playbook
- name: 测试与所有主机的连接
  hosts: all
  gather_facts: no
  
  tasks:
    - name: Ping测试
      ping:
      
    - name: 显示成功消息
      debug:
        msg: "成功连接到 {{ inventory_hostname }}"
EOF
  check_status "创建ping测试脚本"

  # 创建Windows测试脚本
  cat > $PROJECT_DIR/playbooks/win_test.yml << EOF
---
# Windows连接测试playbook
- name: Windows连接测试
  hosts: windows
  gather_facts: no
  
  tasks:
    - name: 运行PowerShell命令
      win_shell: Get-ComputerInfo | Select-Object WindowsProductName, OsVersion, OsArchitecture
      register: computer_info
      
    - name: 显示Windows信息
      debug:
        var: computer_info.stdout_lines
EOF
  check_status "创建Windows测试脚本"
}

# 函数: 创建便捷脚本
create_utility_scripts() {
  echo -e "${YELLOW}[4/6] 创建便捷脚本...${NC}"
  
  # 创建运行脚本
  cat > $PROJECT_DIR/run.sh << EOF
#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# 检查参数
if [ \$# -lt 1 ]; then
  echo -e "\${RED}用法: \$0 <playbook> [额外参数]${NC}"
  echo -e "例如: \$0 ping.yml"
  echo -e "或: \$0 site.yml -l webservers"
  exit 1
fi

PLAYBOOK=\$1
shift

# 检查playbook是否存在
if [[ \$PLAYBOOK != /* && \$PLAYBOOK != ~/* ]]; then
  if [ -f "./playbooks/\$PLAYBOOK" ]; then
    PLAYBOOK="./playbooks/\$PLAYBOOK"
  elif [ ! -f "\$PLAYBOOK" ]; then
    echo -e "\${RED}错误: Playbook文件 '\$PLAYBOOK' 不存在${NC}"
    exit 1
  fi
fi

# 运行playbook
echo -e "\${YELLOW}运行Playbook: \$PLAYBOOK${NC}"
ansible-playbook \$PLAYBOOK \$@

exit_code=\$?
if [ \$exit_code -eq 0 ]; then
  echo -e "\${GREEN}Playbook执行成功!${NC}"
else
  echo -e "\${RED}Playbook执行失败. 错误代码: \$exit_code${NC}"
fi
EOF
  chmod +x $PROJECT_DIR/run.sh
  check_status "创建运行脚本"
  
  # 创建主机添加脚本
  cat > $PROJECT_DIR/add_host.sh << EOF
#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# 检查参数
if [ \$# -lt 3 ]; then
  echo -e "\${RED}用法: \$0 <主机组> <主机名> <IP地址> [SSH用户名] [SSH密码]${NC}"
  echo -e "例如: \$0 webservers web1 192.168.1.101 root password"
  exit 1
fi

GROUP=\$1
HOST=\$2
IP=\$3
USER=\${4:-root}
PASS=\$5

HOSTS_FILE="./inventory/hosts"

# 检查主机组是否存在
if ! grep -q "^\[\$GROUP\]" \$HOSTS_FILE; then
  echo -e "\${YELLOW}主机组 '\$GROUP' 不存在, 创建新组...${NC}"
  echo "" >> \$HOSTS_FILE
  echo "[\$GROUP]" >> \$HOSTS_FILE
fi

# 添加主机
HOST_LINE="\$HOST ansible_host=\$IP"
if [ ! -z "\$PASS" ]; then
  HOST_LINE="\$HOST_LINE ansible_user=\$USER ansible_ssh_pass=\$PASS"
elif [ "\$USER" != "root" ]; then
  HOST_LINE="\$HOST_LINE ansible_user=\$USER"
fi

# 检查主机是否已存在
if grep -q "^\$HOST " \$HOSTS_FILE; then
  echo -e "\${YELLOW}更新现有主机 '\$HOST'${NC}"
  sed -i "/^\$HOST /c\\\$HOST_LINE" \$HOSTS_FILE
else
  # 在组下添加主机
  sed -i "/^\[\$GROUP\]/a\\\$HOST_LINE" \$HOSTS_FILE
fi

echo -e "\${GREEN}主机 '\$HOST' 添加/更新成功!${NC}"
echo "配置: \$HOST_LINE"
EOF
  chmod +x $PROJECT_DIR/add_host.sh
  check_status "创建主机添加脚本"
  
  # 创建Windows主机添加脚本
  cat > $PROJECT_DIR/add_win_host.sh << EOF
#!/bin/bash

# Ansible添加Windows主机脚本

# 设置颜色
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # 无颜色

# 检查参数
if [ \$# -lt 4 ]; then
  echo -e "\${RED}用法: \$0 <主机组> <主机名> <IP地址> <用户名> [密码]${NC}"
  echo -e "例如: \$0 windows win-server1 192.168.1.100 Administrator Password123"
  exit 1
fi

GROUP=\$1
HOST=\$2
IP=\$3
USER=\$4
PASS=\$5

HOSTS_FILE="./inventory/hosts"

# 检查pywinrm是否安装
if ! pip3 list | grep -q pywinrm; then
  echo -e "\${YELLOW}安装pywinrm模块...${NC}"
  pip3 install pywinrm
  if [ \$? -ne 0 ]; then
    echo -e "\${RED}错误: 无法安装pywinrm模块${NC}"
    echo -e "请手动安装: pip3 install pywinrm"
    exit 1
  fi
  echo -e "\${GREEN}pywinrm模块安装成功${NC}"
fi

# 检查Windows组是否存在
if ! grep -q "^\[\$GROUP\]" \$HOSTS_FILE; then
  echo -e "\${YELLOW}创建Windows主机组: \$GROUP${NC}"
  echo "" >> \$HOSTS_FILE
  echo "[\$GROUP]" >> \$HOSTS_FILE
  echo "# Windows主机配置" >> \$HOSTS_FILE
  
  # 添加组变量
  echo "" >> \$HOSTS_FILE
  echo "[\$GROUP:vars]" >> \$HOSTS_FILE
  echo "ansible_connection=winrm" >> \$HOSTS_FILE
  echo "ansible_winrm_server_cert_validation=ignore" >> \$HOSTS_FILE
  echo "ansible_port=5985" >> \$HOSTS_FILE
  echo "# ansible_winrm_transport=ssl" >> \$HOSTS_FILE
  echo "# ansible_port=5986" >> \$HOSTS_FILE
fi

# 构建主机配置行
HOST_LINE="\$HOST ansible_host=\$IP ansible_user=\$USER"
if [ ! -z "\$PASS" ]; then
  HOST_LINE="\$HOST_LINE ansible_password=\$PASS"
fi

# 检查主机是否已存在
if grep -q "^\$HOST " \$HOSTS_FILE; then
  echo -e "\${YELLOW}更新现有Windows主机: \$HOST${NC}"
  sed -i "/^\$HOST /c\\\$HOST_LINE" \$HOSTS_FILE
else
  # 在组下添加主机
  sed -i "/^\[\$GROUP\]/a\\\$HOST_LINE" \$HOSTS_FILE
fi

echo -e "\${GREEN}Windows主机 '\$HOST' 添加/更新成功!${NC}"
echo -e "配置: \$HOST_LINE"

echo ""
echo -e "\${YELLOW}Windows主机管理提示:${NC}"
echo -e "1. 确保Windows主机已配置WinRM (可使用ConfigureRemotingForAnsible.ps1脚本)"
echo -e "2. 测试连接: ./run.sh win_test.yml"
EOF
  chmod +x $PROJECT_DIR/add_win_host.sh
  check_status "创建Windows主机添加脚本"
}

# 函数: 创建README文件
create_readme() {
  echo -e "${YELLOW}[5/6] 创建文档...${NC}"
  
  # 创建README.md
  cat > $PROJECT_DIR/README.md << EOF
# Ansible部署管理项目

此项目提供了一个完整的Ansible环境，用于自动化服务器配置和应用部署。

## 目录结构

\`\`\`
.
├── ansible.cfg            # Ansible配置文件
├── inventory/             # 主机清单目录
│   └── hosts              # 主机清单文件
├── group_vars/            # 组变量目录
│   └── all.yml            # 适用于所有主机的变量
├── host_vars/             # 主机变量目录
├── roles/                 # 角色目录
│   └── common/            # 通用角色
│       ├── tasks/         # 任务
│       ├── handlers/      # 处理程序
│       ├── templates/     # 模板
│       ├── files/         # 文件
│       ├── vars/          # 变量
│       ├── defaults/      # 默认变量
│       └── meta/          # 元数据
├── templates/             # 全局模板目录
├── files/                 # 全局文件目录
├── playbooks/             # Playbook目录
│   ├── site.yml           # 主playbook
│   ├── ping.yml           # Ping测试playbook
│   └── win_test.yml       # Windows测试playbook
├── run.sh                 # 运行脚本
├── add_host.sh            # 主机添加脚本
└── add_win_host.sh        # Windows主机添加脚本
\`\`\`

## 使用方法

### 1. 添加Linux/Unix主机

使用\`add_host.sh\`脚本添加主机:

\`\`\`bash
./add_host.sh <主机组> <主机名> <IP地址> [SSH用户名] [SSH密码]
\`\`\`

例如:

\`\`\`bash
./add_host.sh webservers web1 192.168.1.101 root password
\`\`\`

### 2. 添加Windows主机

使用\`add_win_host.sh\`脚本添加Windows主机:

\`\`\`bash
./add_win_host.sh <主机组> <主机名> <IP地址> <用户名> [密码]
\`\`\`

例如:

\`\`\`bash
./add_win_host.sh windows win1 192.168.1.150 Administrator Password123
\`\`\`

### 3. 测试主机连接

\`\`\`bash
./run.sh ping.yml         # 测试Linux/Unix主机
./run.sh win_test.yml     # 测试Windows主机
\`\`\`

### 4. 运行Playbook

\`\`\`bash
./run.sh site.yml
\`\`\`

### 5. 限制主机或组

\`\`\`bash
./run.sh site.yml -l webservers
\`\`\`

## 自定义

### 添加新角色

\`\`\`bash
ansible-galaxy init roles/新角色名
\`\`\`

### 创建新的Playbook

在\`playbooks\`目录下创建新的YAML文件。

## 常见问题

### SSH连接问题

确保目标服务器允许SSH连接，并且配置了正确的认证方式。

### Windows连接问题

确保Windows主机已配置WinRM服务。可以在Windows主机上以管理员身份运行以下PowerShell命令:

\`\`\`powershell
\$url = "https://raw.githubusercontent.com/ansible/ansible/devel/examples/scripts/ConfigureRemotingForAnsible.ps1"
\$file = "\$env:temp\ConfigureRemotingForAnsible.ps1"
(New-Object -TypeName System.Net.WebClient).DownloadFile(\$url, \$file)
powershell.exe -ExecutionPolicy ByPass -File \$file
\`\`\`

### 权限问题

确保使用\`become: yes\`获取提升权限，或在命令行使用\`-b\`参数:

\`\`\`bash
./run.sh site.yml -b
\`\`\`
EOF
  check_status "创建README.md"
  
  # 创建Windows主机配置指南
  cat > $PROJECT_DIR/windows_setup.md << EOF
# Ansible连接Windows主机配置指南

Ansible默认通过SSH连接Linux/Unix主机，但对于Windows主机，Ansible使用WinRM (Windows Remote Management)协议进行连接。以下是详细的配置步骤：

## 1. 安装必要的Python包

在Ansible控制节点上，安装以下Python包：

\`\`\`bash
pip3 install pywinrm
\`\`\`

## 2. 配置Windows主机

Windows主机需要启用并配置WinRM服务。在Windows主机上以管理员身份运行PowerShell，执行以下命令：

\`\`\`powershell
# 配置WinRM
winrm quickconfig -q
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="1024"}'

# 设置WinRM监听器
New-NetFirewallRule -DisplayName "Windows Remote Management (HTTP-In)" -Name "Windows Remote Management (HTTP-In)" -Profile Any -LocalPort 5985 -Protocol TCP
\`\`\`

更安全的方式是使用HTTPS连接，需要配置SSL证书：

\`\`\`powershell
# 创建自签名证书
\$cert = New-SelfSignedCertificate -DnsName \$env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My

# 创建HTTPS监听器
winrm create winrm/config/Listener?Address=*+Transport=HTTPS "@{Hostname=\`"\$(\$env:COMPUTERNAME)\`";CertificateThumbprint=\`"\$(\$cert.Thumbprint)\`"}"

# 开放5986端口(HTTPS)
New-NetFirewallRule -DisplayName "Windows Remote Management (HTTPS-In)" -Name "Windows Remote Management (HTTPS-In)" -Profile Any -LocalPort 5986 -Protocol TCP
\`\`\`

## 3. 一键配置脚本

可以使用Microsoft提供的ConfigureRemotingForAnsible.ps1脚本进行自动配置。在Windows主机上以管理员身份运行PowerShell：

\`\`\`powershell
\$url = "https://raw.githubusercontent.com/ansible/ansible/devel/examples/scripts/ConfigureRemotingForAnsible.ps1"
\$file = "\$env:temp\ConfigureRemotingForAnsible.ps1"
(New-Object -TypeName System.Net.WebClient).DownloadFile(\$url, \$file)
powershell.exe -ExecutionPolicy ByPass -File \$file
\`\`\`

## 4. 测试连接

添加Windows主机后，可以使用以下命令测试连接：

\`\`\`bash
./run.sh win_test.yml
\`\`\`

## 5. 常见问题排查

如果连接失败，请检查：

1. Windows防火墙是否允许5985(HTTP)或5986(HTTPS)端口
2. WinRM服务是否运行 (\`Get-Service winrm\`)
3. WinRM配置是否正确 (\`winrm get winrm/config\`)
4. 检查凭据是否正确
5. 如果使用域账户，确保Kerberos配置正确
EOF
  check_status "创建Windows配置指南"
}

# 函数: 创建符号链接
create_symlinks() {
  echo -e "${YELLOW}[6/6] 创建便捷命令...${NC}"
  
  # 创建bin目录下的便捷命令
  ln -sf $PROJECT_DIR/run.sh /usr/local/bin/ansible-run
  ln -sf $PROJECT_DIR/add_host.sh /usr/local/bin/ansible-add-host
  ln -sf $PROJECT_DIR/add_win_host.sh /usr/local/bin/ansible-add-win-host
  check_status "创建符号链接"
  
  echo "现在您可以在任何目录使用以下命令:"
  echo "  ansible-run <playbook> [参数]"
  echo "  ansible-add-host <主机组> <主机名> <IP地址> [用户名] [密码]"
  echo "  ansible-add-win-host <主机组> <主机名> <IP地址> <用户名> [密码]"
}

# 主函数
main() {
  install_ansible
  create_directory_structure
  create_config_files
  create_utility_scripts
  create_readme
  create_symlinks
  
  echo ""
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}     Ansible 服务端安装配置已完成!        ${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo ""
  echo -e "${YELLOW}项目目录: ${GREEN}$PROJECT_DIR${NC}"
  echo -e "${YELLOW}日志文件: ${GREEN}$LOG_FILE${NC}"
  echo ""
  echo -e "${GREEN}使用方法:${NC}"
  echo -e "  ${YELLOW}1. 添加Linux主机:${NC} ansible-add-host webservers web1 192.168.1.101"
  echo -e "  ${YELLOW}2. 添加Windows主机:${NC} ansible-add-win-host windows win1 192.168.1.150 Administrator Password"
  echo -e "  ${YELLOW}3. 测试连接:${NC} ansible-run ping.yml"
  echo -e "  ${YELLOW}4. 运行主配置:${NC} ansible-run site.yml"
  echo ""
  echo -e "${YELLOW}结束时间: $(date)${NC}"
}

# 执行主函数
main 