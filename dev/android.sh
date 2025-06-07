#!/bin/bash

# Android开发环境一键安装/卸载脚本 (仅支持root用户)
# 支持 Flutter 和 Kotlin+Gradle 两种开发环境
# 支持 Ubuntu/Debian/CentOS/RHEL/Fedora/Arch

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 全局变量
INSTALL_ROOT="/opt"
FLUTTER_ROOT="$INSTALL_ROOT/flutter"
ANDROID_ROOT="$INSTALL_ROOT/android-sdk"
KOTLIN_ROOT="$INSTALL_ROOT/kotlin"
GRADLE_ROOT="$INSTALL_ROOT/gradle"
USER_HOME="/root"
CONFIG_FILE="/etc/android-dev-env.conf"

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${PURPLE}[DEBUG]${NC} $1"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本必须以root用户身份运行"
        log_info "请使用: sudo $0"
        exit 1
    fi
    log_success "Root权限检查通过"
}

# 检测系统类型
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        log_error "无法检测操作系统类型"
        exit 1
    fi
    
    log_info "检测到操作系统: $OS $VER"
}

# 显示主菜单
show_main_menu() {
    clear
    echo -e "${CYAN}"
    echo "========================================"
    echo "    Android开发环境管理脚本"
    echo "========================================"
    echo -e "${NC}"
    echo "1. 安装Flutter开发环境"
    echo "2. 安装Kotlin+Gradle开发环境"
    echo "3. 卸载所有开发环境"
    echo "4. 查看已安装环境状态"
    echo "5. 退出"
    echo
    echo -n "请选择操作 [1-5]: "
}

# 获取用户选择
get_user_choice() {
    while true; do
        show_main_menu
        read -r choice
        case $choice in
            1)
                install_flutter_env
                break
                ;;
            2)
                install_kotlin_env
                break
                ;;
            3)
                uninstall_all_env
                break
                ;;
            4)
                show_env_status
                ;;
            5)
                log_info "感谢使用！"
                exit 0
                ;;
            *)
                log_error "无效选择，请重试"
                sleep 2
                ;;
        esac
    done
}

# 保存环境配置
save_config() {
    local env_type=$1
    echo "INSTALLED_ENV=$env_type" > "$CONFIG_FILE"
    echo "INSTALL_DATE=$(date '+%Y-%m-%d %H:%M:%S')" >> "$CONFIG_FILE"
    echo "FLUTTER_ROOT=$FLUTTER_ROOT" >> "$CONFIG_FILE"
    echo "ANDROID_ROOT=$ANDROID_ROOT" >> "$CONFIG_FILE"
    echo "KOTLIN_ROOT=$KOTLIN_ROOT" >> "$CONFIG_FILE"
    echo "GRADLE_ROOT=$GRADLE_ROOT" >> "$CONFIG_FILE"
}

# 加载环境配置
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        return 0
    fi
    return 1
}

# 显示环境状态
show_env_status() {
    clear
    echo -e "${CYAN}========================================"
    echo "      当前环境状态"
    echo -e "========================================${NC}"
    
    if load_config; then
        echo -e "${GREEN}已安装环境:${NC} $INSTALLED_ENV"
        echo -e "${GREEN}安装时间:${NC} $INSTALL_DATE"
        echo
        
        # 检查各组件状态
        echo -e "${BLUE}组件状态检查:${NC}"
        
        # Java
        if command -v java &> /dev/null; then
            JAVA_VERSION=$(java -version 2>&1 | head -n1 | cut -d'"' -f2)
            echo -e "  Java: ${GREEN}已安装 ($JAVA_VERSION)${NC}"
        else
            echo -e "  Java: ${RED}未安装${NC}"
        fi
        
        # Android SDK
        if [[ -d "$ANDROID_ROOT" ]]; then
            echo -e "  Android SDK: ${GREEN}已安装${NC}"
        else
            echo -e "  Android SDK: ${RED}未安装${NC}"
        fi
        
        # Flutter (如果是Flutter环境)
        if [[ "$INSTALLED_ENV" == "flutter" ]]; then
            if [[ -f "$FLUTTER_ROOT/bin/flutter" ]]; then
                FLUTTER_VERSION=$("$FLUTTER_ROOT/bin/flutter" --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "未知")
                echo -e "  Flutter: ${GREEN}已安装 ($FLUTTER_VERSION)${NC}"
            else
                echo -e "  Flutter: ${RED}未安装${NC}"
            fi
        fi
        
        # Kotlin (如果是Kotlin环境)
        if [[ "$INSTALLED_ENV" == "kotlin" ]]; then
            if command -v kotlin &> /dev/null; then
                KOTLIN_VERSION=$(kotlin -version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "未知")
                echo -e "  Kotlin: ${GREEN}已安装 ($KOTLIN_VERSION)${NC}"
            else
                echo -e "  Kotlin: ${RED}未安装${NC}"
            fi
            
            if command -v gradle &> /dev/null; then
                GRADLE_VERSION=$(gradle --version | grep -oE 'Gradle [0-9]+\.[0-9]+' | cut -d' ' -f2 || echo "未知")
                echo -e "  Gradle: ${GREEN}已安装 ($GRADLE_VERSION)${NC}"
            else
                echo -e "  Gradle: ${RED}未安装${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}未检测到已安装的开发环境${NC}"
    fi
    
    echo
    echo "按回车键返回主菜单..."
    read -r
}

# 安装系统依赖
install_dependencies() {
    log_step "安装系统依赖..."
    
    case $OS in
        ubuntu|debian)
            apt update
            apt install -y curl git unzip xz-utils zip libglu1-mesa build-essential \
                libgtk-3-dev pkg-config cmake ninja-build libblkid-dev liblzma-dev \
                clang libstdc++-12-dev wget file iputils-ping
            ;;
        centos|rhel)
            yum update -y
            yum groupinstall -y "Development Tools"
            yum install -y curl git unzip xz zip mesa-libGLU-devel gtk3-devel \
                pkgconfig cmake ninja-build libblkid-devel xz-devel clang \
                libstdc++-devel wget file iputils
            ;;
        fedora)
            dnf update -y
            dnf groupinstall -y "Development Tools"
            dnf install -y curl git unzip xz zip mesa-libGLU-devel gtk3-devel \
                pkgconfig cmake ninja-build libblkid-devel xz-devel clang \
                libstdc++-devel wget file iputils
            ;;
        arch|manjaro)
            pacman -Sy --noconfirm
            pacman -S --noconfirm curl git unzip xz zip glu gtk3 pkgconf cmake \
                ninja util-linux xz clang wget file iputils
            ;;
        *)
            log_error "不支持的操作系统: $OS"
            exit 1
            ;;
    esac
    
    log_success "系统依赖安装完成"
}

# 安装Java
install_java() {
    log_step "检查Java环境..."
    
    if command -v java &> /dev/null; then
        JAVA_VERSION=$(java -version 2>&1 | head -n1 | cut -d'"' -f2 | cut -d'.' -f1)
        if [[ $JAVA_VERSION -ge 17 ]]; then
            log_success "Java已安装 (版本: $JAVA_VERSION)"
            return
        fi
    fi
    
    log_info "安装OpenJDK 17..."
    
    case $OS in
        ubuntu|debian)
            apt install -y openjdk-17-jdk
            ;;
        centos|rhel)
            yum install -y java-17-openjdk-devel
            ;;
        fedora)
            dnf install -y java-17-openjdk-devel
            ;;
        arch|manjaro)
            pacman -S --noconfirm jdk17-openjdk
            ;;
    esac
    
    log_success "Java安装完成"
}

# 安装Android SDK
install_android_sdk() {
    log_step "安装Android SDK..."
    
    CMDLINE_TOOLS_DIR="$ANDROID_ROOT/cmdline-tools"
    
    if [[ -d "$CMDLINE_TOOLS_DIR/latest" ]] && [[ -f "$CMDLINE_TOOLS_DIR/latest/bin/sdkmanager" ]]; then
        log_success "Android SDK已安装"
        return
    fi
    
    mkdir -p "$ANDROID_ROOT"
    mkdir -p "$CMDLINE_TOOLS_DIR"
    
    cd /tmp
    log_info "下载Android Command Line Tools..."
    CMDTOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
    
    # 添加下载错误检查
    if ! curl -f -L -o commandlinetools.zip "$CMDTOOLS_URL"; then
        log_error "Android Command Line Tools下载失败，请检查网络连接"
        return 1
    fi
    
    # 验证下载文件
    if ! file commandlinetools.zip | grep -q "Zip archive"; then
        log_error "下载的Android工具文件格式不正确"
        rm -f commandlinetools.zip
        return 1
    fi
    
    log_info "解压Android Command Line Tools..."
    if ! unzip -q commandlinetools.zip; then
        log_error "Android工具解压失败"
        rm -f commandlinetools.zip
        return 1
    fi
    
    if [[ ! -d "cmdline-tools" ]]; then
        log_error "Android工具解压后目录结构异常"
        rm -f commandlinetools.zip
        return 1
    fi
    
    mv cmdline-tools "$CMDLINE_TOOLS_DIR/latest"
    rm commandlinetools.zip
    
    chmod -R 755 "$ANDROID_ROOT"
    
    export PATH="$CMDLINE_TOOLS_DIR/latest/bin:$ANDROID_ROOT/platform-tools:$PATH"
    export ANDROID_HOME="$ANDROID_ROOT"
    
    log_info "安装Android SDK组件..."
    yes | "$CMDLINE_TOOLS_DIR/latest/bin/sdkmanager" --licenses
    "$CMDLINE_TOOLS_DIR/latest/bin/sdkmanager" "platform-tools" "platforms;android-34" "build-tools;34.0.0" "sources;android-34"
    
    log_success "Android SDK安装完成"
}

# 安装Flutter环境
install_flutter_env() {
    log_info "开始安装Flutter开发环境..."
    
    # 检查网络连接
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        log_error "网络连接异常，请检查网络设置"
        echo "按回车键返回主菜单..."
        read -r
        return 1
    fi
    
    detect_os || { log_error "系统检测失败"; return 1; }
    install_dependencies || { log_error "依赖安装失败"; return 1; }
    install_java || { log_error "Java安装失败"; return 1; }
    install_android_sdk || { log_error "Android SDK安装失败"; return 1; }
    install_flutter || { log_error "Flutter安装失败"; return 1; }
    configure_flutter_environment || { log_error "环境变量配置失败"; return 1; }
    run_flutter_doctor || { log_warning "Flutter doctor检查有警告，但可以继续使用"; }
    create_flutter_test_project || { log_warning "测试项目创建失败，但环境安装成功"; }
    
    save_config "flutter"
    log_success "Flutter开发环境安装完成！"
    
    show_flutter_info
    echo "按回车键返回主菜单..."
    read -r
}

# 安装Flutter
install_flutter() {
    log_step "安装Flutter SDK..."
    
    if [[ -d "$FLUTTER_ROOT" ]] && [[ -f "$FLUTTER_ROOT/bin/flutter" ]]; then
        log_success "Flutter已安装"
        return
    fi
    
    if [[ -d "$FLUTTER_ROOT" ]]; then
        log_warning "检测到不完整的Flutter安装，备份中..."
        mv "$FLUTTER_ROOT" "$FLUTTER_ROOT.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # 使用固定的最新稳定版本，避免API问题
    log_info "使用Flutter最新稳定版本..."
    FLUTTER_VERSION="3.24.5"
    DOWNLOAD_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
    
    cd /tmp
    log_info "下载Flutter稳定版 ${FLUTTER_VERSION}..."
    
    # 添加下载错误检查
    if ! curl -f -L -o flutter.tar.xz "$DOWNLOAD_URL"; then
        log_error "Flutter下载失败，尝试备用下载源..."
        # 备用下载链接
        BACKUP_URL="https://github.com/flutter/flutter/archive/refs/tags/${FLUTTER_VERSION}.tar.gz"
        if curl -f -L -o flutter.tar.gz "$BACKUP_URL"; then
            log_info "使用备用源解压Flutter..."
            tar xzf flutter.tar.gz
            mv "flutter-${FLUTTER_VERSION}" "$FLUTTER_ROOT"
            rm flutter.tar.gz
        else
            log_error "所有下载源均失败，请检查网络连接"
            return 1
        fi
    else
        # 验证下载文件
        if ! file flutter.tar.xz | grep -q "XZ compressed"; then
            log_error "下载的文件格式不正确，请重试"
            rm -f flutter.tar.xz
            return 1
        fi
        
        log_info "解压Flutter..."
        if ! tar xf flutter.tar.xz; then
            log_error "Flutter解压失败"
            rm -f flutter.tar.xz
            return 1
        fi
        
        mv flutter "$FLUTTER_ROOT"
        rm flutter.tar.xz
    fi
    
    chmod -R 755 "$FLUTTER_ROOT"
    git config --global --add safe.directory "$FLUTTER_ROOT"
    log_success "Flutter安装完成"
}

# 安装Kotlin环境
install_kotlin_env() {
    log_info "开始安装Kotlin+Gradle开发环境..."
    
    # 检查网络连接
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        log_error "网络连接异常，请检查网络设置"
        echo "按回车键返回主菜单..."
        read -r
        return 1
    fi
    
    detect_os || { log_error "系统检测失败"; return 1; }
    install_dependencies || { log_error "依赖安装失败"; return 1; }
    install_java || { log_error "Java安装失败"; return 1; }
    install_android_sdk || { log_error "Android SDK安装失败"; return 1; }
    install_kotlin || { log_error "Kotlin安装失败"; return 1; }
    install_gradle || { log_error "Gradle安装失败"; return 1; }
    configure_kotlin_environment || { log_error "环境变量配置失败"; return 1; }
    create_kotlin_test_project || { log_warning "测试项目创建失败，但环境安装成功"; }
    
    save_config "kotlin"
    log_success "Kotlin+Gradle开发环境安装完成！"
    
    show_kotlin_info
    echo "按回车键返回主菜单..."
    read -r
}

# 安装Kotlin
install_kotlin() {
    log_step "安装Kotlin编译器..."
    
    if command -v kotlin &> /dev/null; then
        log_success "Kotlin已安装"
        return
    fi
    
    # 使用固定版本，避免API不稳定
    KOTLIN_VERSION="1.9.21"
    log_info "安装Kotlin版本: $KOTLIN_VERSION"
    
    cd /tmp
    log_info "下载Kotlin编译器..."
    KOTLIN_URL="https://github.com/JetBrains/kotlin/releases/download/v${KOTLIN_VERSION}/kotlin-compiler-${KOTLIN_VERSION}.zip"
    
    # 添加下载错误检查
    if ! curl -f -L -o "kotlin-compiler-${KOTLIN_VERSION}.zip" "$KOTLIN_URL"; then
        log_error "Kotlin下载失败，请检查网络连接"
        return 1
    fi
    
    # 验证下载文件
    if ! file "kotlin-compiler-${KOTLIN_VERSION}.zip" | grep -q "Zip archive"; then
        log_error "下载的Kotlin文件格式不正确"
        rm -f "kotlin-compiler-${KOTLIN_VERSION}.zip"
        return 1
    fi
    
    log_info "解压Kotlin编译器..."
    if ! unzip -q "kotlin-compiler-${KOTLIN_VERSION}.zip"; then
        log_error "Kotlin解压失败"
        rm -f "kotlin-compiler-${KOTLIN_VERSION}.zip"
        return 1
    fi
    
    if [[ ! -d "kotlinc" ]]; then
        log_error "Kotlin解压后目录结构异常"
        rm -f "kotlin-compiler-${KOTLIN_VERSION}.zip"
        return 1
    fi
    
    mv kotlinc "$KOTLIN_ROOT"
    chmod -R 755 "$KOTLIN_ROOT"
    rm "kotlin-compiler-${KOTLIN_VERSION}.zip"
    
    log_success "Kotlin安装完成"
}

# 安装Gradle
install_gradle() {
    log_step "安装Gradle构建工具..."
    
    if command -v gradle &> /dev/null; then
        log_success "Gradle已安装"
        return
    fi
    
    # 使用固定版本，确保稳定性
    GRADLE_VERSION="8.5"
    log_info "安装Gradle版本: $GRADLE_VERSION"
    
    cd /tmp
    log_info "下载Gradle..."
    GRADLE_URL="https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip"
    
    # 添加下载错误检查
    if ! curl -f -L -o "gradle-${GRADLE_VERSION}-bin.zip" "$GRADLE_URL"; then
        log_error "Gradle下载失败，请检查网络连接"
        return 1
    fi
    
    # 验证下载文件
    if ! file "gradle-${GRADLE_VERSION}-bin.zip" | grep -q "Zip archive"; then
        log_error "下载的Gradle文件格式不正确"
        rm -f "gradle-${GRADLE_VERSION}-bin.zip"
        return 1
    fi
    
    log_info "解压Gradle..."
    if ! unzip -q "gradle-${GRADLE_VERSION}-bin.zip"; then
        log_error "Gradle解压失败"
        rm -f "gradle-${GRADLE_VERSION}-bin.zip"
        return 1
    fi
    
    if [[ ! -d "gradle-${GRADLE_VERSION}" ]]; then
        log_error "Gradle解压后目录结构异常"
        rm -f "gradle-${GRADLE_VERSION}-bin.zip"
        return 1
    fi
    
    mv "gradle-${GRADLE_VERSION}" "$GRADLE_ROOT"
    chmod -R 755 "$GRADLE_ROOT"
    rm "gradle-${GRADLE_VERSION}-bin.zip"
    
    log_success "Gradle安装完成"
}

# 配置Flutter环境变量
configure_flutter_environment() {
    log_step "配置Flutter环境变量..."
    
    SHELL_RC="/root/.bashrc"
    if [[ ! -f "$SHELL_RC" ]]; then
        touch "$SHELL_RC"
    fi
    
    # 删除旧配置
    sed -i '/# Flutter开发环境变量/,/^$/d' "$SHELL_RC"
    
    cat >> "$SHELL_RC" << EOF

# Flutter开发环境变量
export FLUTTER_HOME="$FLUTTER_ROOT"
export ANDROID_HOME="$ANDROID_ROOT"
export PATH="\$FLUTTER_HOME/bin:\$ANDROID_HOME/cmdline-tools/latest/bin:\$ANDROID_HOME/platform-tools:\$PATH"

EOF
    
    export FLUTTER_HOME="$FLUTTER_ROOT"
    export ANDROID_HOME="$ANDROID_ROOT"
    export PATH="$FLUTTER_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
    
    log_success "Flutter环境变量配置完成"
}

# 配置Kotlin环境变量
configure_kotlin_environment() {
    log_step "配置Kotlin+Gradle环境变量..."
    
    SHELL_RC="/root/.bashrc"
    if [[ ! -f "$SHELL_RC" ]]; then
        touch "$SHELL_RC"
    fi
    
    # 删除旧配置
    sed -i '/# Kotlin开发环境变量/,/^$/d' "$SHELL_RC"
    
    cat >> "$SHELL_RC" << EOF

# Kotlin开发环境变量
export KOTLIN_HOME="$KOTLIN_ROOT"
export GRADLE_HOME="$GRADLE_ROOT"
export ANDROID_HOME="$ANDROID_ROOT"
export PATH="\$KOTLIN_HOME/bin:\$GRADLE_HOME/bin:\$ANDROID_HOME/cmdline-tools/latest/bin:\$ANDROID_HOME/platform-tools:\$PATH"

EOF
    
    export KOTLIN_HOME="$KOTLIN_ROOT"
    export GRADLE_HOME="$GRADLE_ROOT"
    export ANDROID_HOME="$ANDROID_ROOT"
    export PATH="$KOTLIN_HOME/bin:$GRADLE_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
    
    log_success "Kotlin+Gradle环境变量配置完成"
}

# 运行Flutter doctor
run_flutter_doctor() {
    log_step "运行Flutter环境检查..."
    
    export FLUTTER_HOME="$FLUTTER_ROOT"
    export ANDROID_HOME="$ANDROID_ROOT"
    export PATH="$FLUTTER_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
    
    git config --global --add safe.directory "$FLUTTER_ROOT" 2>/dev/null || true
    
    log_info "更新Flutter到最新稳定版..."
    "$FLUTTER_ROOT/bin/flutter" upgrade --force
    
    log_info "接受Android许可证..."
    yes | "$FLUTTER_ROOT/bin/flutter" doctor --android-licenses
    
    "$FLUTTER_ROOT/bin/flutter" doctor -v
    
    log_success "Flutter环境检查完成"
}

# 创建Flutter测试项目
create_flutter_test_project() {
    log_step "创建Flutter测试项目..."
    
    cd "$USER_HOME"
    
    if [[ -d "flutter_test_app" ]]; then
        log_warning "测试项目已存在，删除后重新创建"
        rm -rf flutter_test_app
    fi
    
    export FLUTTER_HOME="$FLUTTER_ROOT"
    export PATH="$FLUTTER_HOME/bin:$PATH"
    
    "$FLUTTER_ROOT/bin/flutter" create flutter_test_app
    cd flutter_test_app
    
    log_info "获取项目依赖..."
    "$FLUTTER_ROOT/bin/flutter" pub get
    
    log_success "Flutter测试项目创建完成"
}

# 创建Kotlin测试项目
create_kotlin_test_project() {
    log_step "创建Kotlin Android测试项目..."
    
    cd "$USER_HOME"
    
    if [[ -d "kotlin_android_app" ]]; then
        log_warning "测试项目已存在，删除后重新创建"
        rm -rf kotlin_android_app
    fi
    
    mkdir -p kotlin_android_app
    cd kotlin_android_app
    
    # 创建基本的Android项目结构
    mkdir -p app/src/main/{java/com/example/app,res/layout,res/values}
    mkdir -p app/src/test/java/com/example/app
    
    # 创建build.gradle文件
    cat > build.gradle << 'EOF'
buildscript {
    ext.kotlin_version = '1.9.21'
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath 'com.android.tools.build:gradle:8.2.0'
        classpath "org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlin_version"
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}
EOF
    
    # 创建app/build.gradle文件
    cat > app/build.gradle << 'EOF'
plugins {
    id 'com.android.application'
    id 'kotlin-android'
}

android {
    namespace 'com.example.app'
    compileSdk 34

    defaultConfig {
        applicationId "com.example.app"
        minSdk 24
        targetSdk 34
        versionCode 1
        versionName "1.0"

        testInstrumentationRunner "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            minifyEnabled false
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }
    kotlinOptions {
        jvmTarget = '1.8'
    }
}

dependencies {
    implementation 'androidx.core:core-ktx:1.12.0'
    implementation 'androidx.appcompat:appcompat:1.6.1'
    implementation 'com.google.android.material:material:1.11.0'
    implementation 'androidx.constraintlayout:constraintlayout:2.1.4'
    testImplementation 'junit:junit:4.13.2'
    androidTestImplementation 'androidx.test.ext:junit:1.1.5'
    androidTestImplementation 'androidx.test.espresso:espresso-core:3.5.1'
}
EOF
    
    # 创建MainActivity.kt
    cat > app/src/main/java/com/example/app/MainActivity.kt << 'EOF'
package com.example.app

import androidx.appcompat.app.AppCompatActivity
import android.os.Bundle

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
    }
}
EOF
    
    # 创建布局文件
    cat > app/src/main/res/layout/activity_main.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout 
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://schemas.android.com/tools"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    tools:context=".MainActivity">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="Hello Kotlin Android!"
        android:textSize="24sp"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintTop_toTopOf="parent" />

</androidx.constraintlayout.widget.ConstraintLayout>
EOF
    
    # 创建AndroidManifest.xml
    cat > app/src/main/AndroidManifest.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:theme="@style/Theme.AppCompat.Light.DarkActionBar">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>

</manifest>
EOF
    
    # 创建strings.xml
    cat > app/src/main/res/values/strings.xml << 'EOF'
<resources>
    <string name="app_name">Kotlin Android App</string>
</resources>
EOF
    
    # 创建gradle.properties
    cat > gradle.properties << 'EOF'
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
android.enableJetifier=true
kotlin.code.style=official
EOF
    
    # 创建settings.gradle
    cat > settings.gradle << 'EOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "Kotlin Android App"
include ':app'
EOF
    
    # 创建gradlew
    log_info "生成Gradle Wrapper..."
    export GRADLE_HOME="$GRADLE_ROOT"
    export PATH="$GRADLE_HOME/bin:$PATH"
    
    # 确保gradle命令可用
    if ! command -v gradle &> /dev/null; then
        log_error "Gradle命令不可用，请检查安装"
        return 1
    fi
    
    if ! gradle wrapper; then
        log_warning "Gradle Wrapper生成失败，但项目结构已创建"
    fi
    
    log_success "Kotlin Android测试项目创建完成"
}

# 显示Flutter安装信息
show_flutter_info() {
    echo
    log_success "=============================="
    log_success "Flutter开发环境安装完成!"
    log_success "=============================="
    echo
    log_info "安装位置:"
    log_info "  Flutter SDK: $FLUTTER_ROOT"
    log_info "  Android SDK: $ANDROID_ROOT"
    log_info "  测试项目: $USER_HOME/flutter_test_app"
    echo
    log_info "常用命令:"
    log_info "  flutter --version       # 查看Flutter版本"
    log_info "  flutter doctor          # 检查环境"
    log_info "  flutter create myapp    # 创建新项目"
    log_info "  flutter pub get         # 获取依赖"
    log_info "  flutter test            # 运行测试"
    echo
    log_info "重要提示:"
    log_info "  重新登录或运行 'source /root/.bashrc' 来加载环境变量"
}

# 显示Kotlin安装信息
show_kotlin_info() {
    echo
    log_success "=============================="
    log_success "Kotlin+Gradle开发环境安装完成!"
    log_success "=============================="
    echo
    log_info "安装位置:"
    log_info "  Kotlin编译器: $KOTLIN_ROOT"
    log_info "  Gradle构建工具: $GRADLE_ROOT"
    log_info "  Android SDK: $ANDROID_ROOT"
    log_info "  测试项目: $USER_HOME/kotlin_android_app"
    echo
    log_info "常用命令:"
    log_info "  kotlin -version         # 查看Kotlin版本"
    log_info "  gradle --version        # 查看Gradle版本"
    log_info "  ./gradlew build         # 构建项目"
    log_info "  ./gradlew assembleDebug # 构建调试版本"
    log_info "  adb install app.apk     # 安装APK到设备"
    echo
    log_info "重要提示:"
    log_info "  重新登录或运行 'source /root/.bashrc' 来加载环境变量"
}

# 卸载所有环境
uninstall_all_env() {
    clear
    log_warning "=============================="
    log_warning "  警告：即将卸载所有开发环境"
    log_warning "=============================="
    echo
    log_info "将要删除以下内容："
    echo "  - Flutter SDK ($FLUTTER_ROOT)"
    echo "  - Kotlin编译器 ($KOTLIN_ROOT)"
    echo "  - Gradle构建工具 ($GRADLE_ROOT)"
    echo "  - Android SDK ($ANDROID_ROOT)"
    echo "  - 测试项目 ($USER_HOME/flutter_test_app, $USER_HOME/kotlin_android_app)"
    echo "  - 环境变量配置"
    echo "  - 配置文件 ($CONFIG_FILE)"
    echo
    log_warning "注意：Java环境将保留，因为可能被其他程序使用"
    echo
    
    while true; do
        echo -n "确定要继续吗？ [y/N]: "
        read -r confirm
        case $confirm in
            [Yy]|[Yy][Ee][Ss])
                perform_uninstall
                break
                ;;
            [Nn]|[Nn][Oo]|"")
                log_info "取消卸载操作"
                return
                ;;
            *)
                log_error "请输入 y 或 n"
                ;;
        esac
    done
}

# 执行卸载操作
perform_uninstall() {
    log_step "开始卸载开发环境..."
    
    # 删除安装目录
    log_info "删除SDK和工具目录..."
    [[ -d "$FLUTTER_ROOT" ]] && rm -rf "$FLUTTER_ROOT" && log_success "Flutter SDK已删除"
    [[ -d "$KOTLIN_ROOT" ]] && rm -rf "$KOTLIN_ROOT" && log_success "Kotlin编译器已删除"
    [[ -d "$GRADLE_ROOT" ]] && rm -rf "$GRADLE_ROOT" && log_success "Gradle构建工具已删除"
    [[ -d "$ANDROID_ROOT" ]] && rm -rf "$ANDROID_ROOT" && log_success "Android SDK已删除"
    
    # 删除测试项目
    log_info "删除测试项目..."
    [[ -d "$USER_HOME/flutter_test_app" ]] && rm -rf "$USER_HOME/flutter_test_app" && log_success "Flutter测试项目已删除"
    [[ -d "$USER_HOME/kotlin_android_app" ]] && rm -rf "$USER_HOME/kotlin_android_app" && log_success "Kotlin测试项目已删除"
    
    # 清理环境变量
    log_info "清理环境变量配置..."
    SHELL_RC="/root/.bashrc"
    if [[ -f "$SHELL_RC" ]]; then
        sed -i '/# Flutter开发环境变量/,/^$/d' "$SHELL_RC"
        sed -i '/# Kotlin开发环境变量/,/^$/d' "$SHELL_RC"
        log_success "环境变量配置已清理"
    fi
    
    # 删除配置文件
    [[ -f "$CONFIG_FILE" ]] && rm -f "$CONFIG_FILE" && log_success "配置文件已删除"
    
    # 清理临时文件
    log_info "清理临时文件..."
    rm -rf /tmp/flutter_install_* /tmp/kotlin_install_* /tmp/gradle_install_* 2>/dev/null || true
    
    log_success "=============================="
    log_success "所有开发环境卸载完成！"
    log_success "=============================="
    echo
    log_info "重要提示："
    log_info "  1. 重新登录以确保环境变量完全清理"
    log_info "  2. Java环境已保留，如需卸载请手动操作"
    log_info "  3. 已安装的系统依赖包未删除"
    echo
    
    echo "按回车键返回主菜单..."
    read -r
}

# 清理临时文件
cleanup() {
    log_info "清理临时文件..."
    cd /tmp
    rm -rf flutter_install_* kotlin_install_* gradle_install_* 2>/dev/null || true
    rm -rf flutter.tar.xz flutter.tar.gz flutter/ 2>/dev/null || true
    rm -rf kotlin-compiler-*.zip kotlinc/ 2>/dev/null || true
    rm -rf gradle-*-bin.zip gradle-*/ 2>/dev/null || true
    rm -rf commandlinetools.zip cmdline-tools/ 2>/dev/null || true
    log_success "临时文件清理完成"
}

# 主函数
main() {
    check_root
    
    # 设置陷阱，确保退出时清理
    trap cleanup EXIT
    
    # 开始主循环
    while true; do
        get_user_choice
    done
}

# 执行主函数
main "$@"
