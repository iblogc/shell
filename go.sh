#!/bin/bash

# Go 自动安装配置脚本 (适用于Debian/Ubuntu)
# 使用方法: sudo bash install_go.sh [版本号]

set -e

# 检查系统类型
if ! grep -qiE 'debian|ubuntu' /etc/os-release; then
    echo "错误：本脚本仅适用于Debian/Ubuntu系统"
    exit 1
fi

# 检查是否以root运行
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用sudo或以root用户运行此脚本"
    exit 1
fi

# 获取用户输入的版本或使用默认值
DEFAULT_VERSION="1.24.0"
GO_VERSION=${1:-$DEFAULT_VERSION}

# 验证版本号格式
if ! [[ "$GO_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "错误：版本号格式不正确，请使用类似 1.24.0 的格式"
    exit 1
fi

GO_TAR="go${GO_VERSION}.linux-amd64.tar.gz"
GO_URL="https://dl.google.com/go/${GO_TAR}"

# 检查是否已安装旧版Go
if command -v go &>/dev/null; then
    echo "检测到已安装Go，当前版本: $(go version)"
    read -p "是否要卸载当前版本? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "卸载旧版Go..."
        rm -rf /usr/local/go
        sed -i '/# GoLang/d' /etc/profile
        sed -i '/export GOROOT/d' /etc/profile
        sed -i '/export GOPATH/d' /etc/profile
        sed -i '/export PATH=\$GOROOT/d' /etc/profile
    else
        echo "保留现有安装，退出脚本"
        exit 0
    fi
fi

# 下载Go
echo "下载Go ${GO_VERSION}..."
cd /tmp
if [ -f "${GO_TAR}" ]; then
    echo "发现已下载的Go安装包，跳过下载"
else
    wget --progress=bar:force "${GO_URL}"
    if [ $? -ne 0 ]; then
        echo "下载失败，请检查网络连接和版本号是否正确"
        echo "可用的Go版本可以在 https://golang.org/dl/ 查看"
        exit 1
    fi
fi

# 安装Go
echo "安装Go到/usr/local..."
rm -rf /usr/local/go
tar -C /usr/local -xzf "${GO_TAR}"

# 配置环境变量
echo "配置环境变量..."

# 系统级配置
cat >> /etc/profile <<EOF

# GoLang Environment
export GOROOT=/usr/local/go
export GOPATH=\$HOME/go
export PATH=\$GOROOT/bin:\$GOPATH/bin:\$PATH
EOF

# 用户级配置 (为当前用户和可能的sudo用户)
for USER_HOME in /home/* /root; do
    USER=$(basename "${USER_HOME}")
    if [ -d "${USER_HOME}" ]; then
        cat >> "${USER_HOME}/.profile" <<EOF

# GoLang Environment
export GOROOT=/usr/local/go
export GOPATH=\$HOME/go
export PATH=\$GOROOT/bin:\$GOPATH/bin:\$PATH
EOF
        chown "${USER}:${USER}" "${USER_HOME}/.profile"
    fi
done

# 创建GOPATH目录
echo "创建GOPATH目录..."
for USER_HOME in /home/* /root; do
    if [ -d "${USER_HOME}" ]; then
        mkdir -p "${USER_HOME}/go"{,/bin,/pkg,/src}
        chown -R "$(basename "${USER_HOME}"):$(basename "${USER_HOME}")" "${USER_HOME}/go"
    fi
done

# 立即生效环境变量
source /etc/profile

# 验证安装
echo "验证安装..."
if ! command -v go &>/dev/null; then
    echo "Go安装失败，请检查错误信息"
    exit 1
fi

echo "Go安装成功！版本信息:"
go version

echo "
安装完成！Go ${GO_VERSION}已成功安装并配置。

提示:
1. 新终端会话会自动加载Go环境变量
2. 当前会话可以运行 'source ~/.profile' 立即生效
3. Go工作目录(GOPATH)已创建在 ~/go

如需卸载，请删除/usr/local/go目录并移除/etc/profile和~/.profile中的Go环境变量
"
