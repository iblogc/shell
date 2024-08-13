#!/bin/bash

# 更新系统包索引
sudo apt update

# 安装 Ansible
sudo apt install ansible -y

# 创建 Ansible 配置文件和目录
mkdir -p /etc/ansible
cd /etc/ansible || exit

# 创建 ansible.cfg 文件并添加配置
cat <<EOL > ansible.cfg
[defaults]
host_key_checking = False
ansible_ssh_common_args = '-o StrictHostKeyChecking=no'
EOL

# 创建 hosts 文件并添加被控主机
cat <<EOL > hosts
[myservers]
1 ansible_host=192.168.1.1 ansible_user=root ansible_port=22 ansible_ssh_pass=password1
2 ansible_host=192.168.1.2 ansible_user=root ansible_port=22 ansible_ssh_pass=password2
3 ansible_host=192.168.1.3 ansible_user=root ansible_port=22 ansible_ssh_pass=password3
4 ansible_host=192.168.1.4 ansible_user=root ansible_port=22 ansible_ssh_pass=password4
5 ansible_host=192.168.1.5 ansible_user=root ansible_port=22 ansible_ssh_pass=password5
EOL

# 创建 renwu.yml 文件并添加任务
cat <<EOL > renwu.yml
---
# 定义要执行任务的主机组
- hosts: myservers
  become: yes  # 以管理员权限运行命令
  tasks:
    - name: 将Shell脚本复制到远程主机
      copy:
        # 本地脚本路径
        src: /etc/ansible/script.sh  
        # 远程主机上的目标路径
        dest: /tmp/script.sh  
        # 设置脚本权限为可执行
        mode: '0755'  

    - name: 在远程主机上执行Shell脚本
      shell: /tmp/script.sh  # 在远程主机上执行脚本
EOL

# 输出成功信息
echo "Ansible 配置文件和任务文件已成功创建并配置完成。"
