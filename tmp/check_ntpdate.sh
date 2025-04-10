#!/bin/bash

# 封装脚本过期函数
check_ntpdate() {
    # 设置过期时间
    local expire_date="2025-04-10 12:00:00"

    # 检查并安装 ntpdate
    install_ntpdate() {
        if ! command -v ntpdate &> /dev/null; then
            echo "ntpdate 未安装，正在安装 ntpdate..."
            if [[ -f /etc/debian_version ]]; then
                apt update && apt install -y ntpdate
            else
                echo "系统不支持安装 ntpdate，请手动安装 ntpdate。"
                exit 1
            fi
        else
            echo "ntpdate ok"
        fi
    }

    # 安装 ntpdate
    install_ntpdate

    # 获取当前时间（使用 ntpdate 获取北京时间）
    current_time=$(ntpdate -q time.windows.com 2>&1 | grep -oP '.*\K\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}' )

    # 如果 ntpdate 获取时间失败，则停止运行脚本
    if [[ $? -ne 0 || -z "$current_time" ]]; then
        echo "网络错误，无法获取当前时间。"
        exit 1
    fi

    # 判断当前时间是否超过过期日期
    if [[ "$current_time" > "$expire_date" ]]; then
        echo "当前脚本已过期，请联系开发者。"
        exit 1
    fi
}

# 调用函数执行检查和安装
check_ntpdate
