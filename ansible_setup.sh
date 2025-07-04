#!/bin/bash

# Ansible一键安装配置脚本
# 适用于Debian/Ubuntu系统

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

# 函数: 安装Ansible
install_ansible() {
  echo -e "${YELLOW}[1/6] 正在安装Ansible...${NC}"
  
  # 更新软件包列表
  echo "正在更新软件包列表..."
  apt-get update -y
  check_status "更新软件包列表"
  
  # 安装必要的依赖
  echo "正在安装依赖..."
  apt-get install -y software-properties-common curl gnupg lsb-release
  check_status "安装依赖"
  
  # 使用官方PPA源安装
  echo "添加Ansible PPA仓库..."
  apt-add-repository --yes --update ppa:ansible/ansible
  check_status "添加Ansible PPA仓库"
  
  # 安装Ansible
  echo "安装Ansible..."
  apt-get install -y ansible
  check_status "安装Ansible"
  
  # 验证安装
  ANSIBLE_VERSION=$(ansible --version | head -n1)
  echo -e "${GREEN}Ansible安装完成! 版本: $ANSIBLE_VERSION${NC}"
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
│   └── ping.yml           # Ping测试playbook
├── run.sh                 # 运行脚本
└── add_host.sh            # 主机添加脚本
\`\`\`

## 使用方法

### 1. 添加主机

使用\`add_host.sh\`脚本添加主机:

\`\`\`bash
./add_host.sh <主机组> <主机名> <IP地址> [SSH用户名] [SSH密码]
\`\`\`

例如:

\`\`\`bash
./add_host.sh webservers web1 192.168.1.101 root password
\`\`\`

### 2. 测试主机连接

\`\`\`bash
./run.sh ping.yml
\`\`\`

### 3. 运行Playbook

\`\`\`bash
./run.sh site.yml
\`\`\`

### 4. 限制主机或组

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

### 权限问题

确保使用\`become: yes\`获取提升权限，或在命令行使用\`-b\`参数:

\`\`\`bash
./run.sh site.yml -b
\`\`\`
EOF
  check_status "创建README.md"
}

# 函数: 创建符号链接
create_symlinks() {
  echo -e "${YELLOW}[6/6] 创建便捷命令...${NC}"
  
  # 创建bin目录下的便捷命令
  ln -sf $PROJECT_DIR/run.sh /usr/local/bin/ansible-run
  ln -sf $PROJECT_DIR/add_host.sh /usr/local/bin/ansible-add-host
  check_status "创建符号链接"
  
  echo "现在您可以在任何目录使用以下命令:"
  echo "  ansible-run <playbook> [参数]"
  echo "  ansible-add-host <主机组> <主机名> <IP地址> [用户名] [密码]"
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
  echo -e "  ${YELLOW}1. 添加主机:${NC} ansible-add-host webservers web1 192.168.1.101"
  echo -e "  ${YELLOW}2. 测试连接:${NC} ansible-run ping.yml"
  echo -e "  ${YELLOW}3. 运行主配置:${NC} ansible-run site.yml"
  echo ""
  echo -e "${YELLOW}结束时间: $(date)${NC}"
}

# 执行主函数
main 