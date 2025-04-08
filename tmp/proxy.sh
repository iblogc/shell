#!/bin/bash
# 变量定义
REMOTE_USER="root"                         # 目标主机的 SSH 用户名
REMOTE_HOST="192.168.0.2"                  # 目标主机的 IP 地址或域名
REMOTE_PORT="2222"                         # 目标主机的 SSH 端口，默认是 22，如果是其他端口可以修改
REMOTE_PASS="your_ssh_password"            # 目标主机的 SSH 密码
REMOTE_FILE="/home/proxy.txt"              # 远程主机上存储节点链接的文件路径

ADD_NODE_CMD="VLESS-REALITY"               # 添加节点的命令（VLESS-REALITY）
NODE_PREFIX="vless://"                     # 提取节点链接的前缀

# 运行节点脚本
bash <(wget -qO- -o- https://github.com/admin8800/sing-box/raw/main/install.sh)

# 添加节点
sb a $ADD_NODE_CMD

# 提取节点链接
NODE_URL=$(sb i | grep "$NODE_PREFIX" | awk '{print $1}')

# 使用 sshpass 将节点链接传输到远程主机的指定文件
echo "$NODE_URL" | sshpass -p "$REMOTE_PASS" ssh -p "$REMOTE_PORT" -o StrictHostKeyChecking=no ${REMOTE_USER}@${REMOTE_HOST} "tee -a $REMOTE_FILE"

echo "节点链接已成功追加到 ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_FILE}"
