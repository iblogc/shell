#!/bin/bash
# 站群多IP源进源出节点脚本sk5协议
# 作者sky22333

# 生成随机8位数的用户名和密码
generate_random_string() {
    local length=8
    tr -dc A-Za-z0-9 </dev/urandom | head -c $length
}

install_jq() {
    if ! command -v jq &> /dev/null; then
        echo "jq 未安装，正在安装 jq..."
        if [[ -f /etc/debian_version ]]; then
            apt update && apt install -yq jq
        elif [[ -f /etc/redhat-release ]]; then
            yum install -y epel-release jq
        else
            echo "无法确定系统发行版，请手动安装 jq。"
            exit 1
        fi
    else
        echo "jq 已安装。"
    fi
}

install_xray() {
    if ! command -v xray &> /dev/null; then
        echo "Xray 未安装，正在安装 Xray..."
        if ! bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install --version v1.8.4; then
            echo "Xray 安装失败，请检查网络连接或安装脚本。"
            exit 1
        fi
        echo "Xray 安装完成。"
    else
        echo "Xray 已安装。"
    fi
}

get_public_ipv4() {
    ip -4 addr show | grep inet | grep -vE "127\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.|169\.254" | awk '{print $2}' | cut -d'/' -f1
}

# 确保 socks.txt 文件存在，如果不存在则创建
ensure_socks_file_exists() {
    if [ ! -f /home/socks.txt ]; then
        echo "socks.txt 文件不存在，正在创建..."
        touch /home/socks.txt
    fi
}

print_node_info() {
    local ip=$1
    local port=$2
    # 此处用户名和密码可以改为固定值
    local username=$3
    local password=$4
    echo -e " IP: \033[32m$ip\033[0m 端口: \033[32m$port\033[0m 用户名: \033[32m$username\033[0m 密码: \033[32m$password\033[0m"
    
    # 保存节点信息到文件
    echo "$ip $port $username $password" >> /home/socks.txt
}

configure_xray() {
    public_ips=($(get_public_ipv4))
    
    if [[ ${#public_ips[@]} -eq 0 ]]; then
        echo "未找到额外IP地址，退出..."
        exit 1
    fi
    
    echo "找到的公网 IPv4 地址: ${public_ips[@]}"
    
    config_file="/usr/local/etc/xray/config.json"
    
    cat > $config_file <<EOF
{
  "inbounds": [],
  "outbounds": [],
  "routing": {
    "rules": []
  }
}
EOF

    # 配置 inbounds 和 outbounds
    port=10001
    for ip in "${public_ips[@]}"; do
        echo "正在配置 IP: $ip 端口: $port"
        
        # 此处用户名和密码可以改为固定值
        username=$(generate_random_string)
        password=$(generate_random_string)

        jq --argjson port "$port" --arg ip "$ip" --arg username "$username" --arg password "$password" '.inbounds += [{
            "port": $port,
            "protocol": "socks",
            "settings": {
                "auth": "password",
                "accounts": [{
                    "user": $username,
                    "pass": $password
                }],
                "udp": true,
                "ip": "0.0.0.0"
            },
            "streamSettings": {
                "network": "tcp"
            },
            "tag": ("in-\($port)")
        }] | .outbounds += [{
            "protocol": "freedom",
            "settings": {},
            "sendThrough": $ip,
            "tag": ("out-\($port)")
        }] | .routing.rules += [{
            "type": "field",
            "inboundTag": ["in-\($port)"],
            "outboundTag": "out-\($port)"
        }]' "$config_file" > temp.json && mv temp.json "$config_file"

        print_node_info "$ip" "$port" "$username" "$password"

        port=$((port + 1))
    done

    echo "Xray 配置完成。"
}

restart_xray() {
    echo "正在重启 Xray 服务..."
    if ! systemctl restart xray; then
        echo "Xray 服务重启失败，请检查配置文件。"
        exit 1
    fi
    systemctl enable xray
    echo "Xray 服务已重启。"
}

main() {
    ensure_socks_file_exists
    install_jq
    install_xray
    configure_xray
    restart_xray
    echo "部署完成，所有节点信息已保存到 /home/socks.txt"
}

main
