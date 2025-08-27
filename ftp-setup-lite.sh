#!/bin/bash

# BRCE FTP 轻量版部署脚本
# 版本: v1.1.0-lite
# 功能: 直接目录访问 + FTP服务
# 适合: 简单的录播文件分享，无复杂权限配置

set -o pipefail

# 脚本信息
SCRIPT_VERSION="v1.1.0-lite"
SCRIPT_NAME="BRCE FTP Lite"

# 日志配置
LOG_DIR="/var/log/brce-ftp"
LOG_FILE="$LOG_DIR/install.log"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 初始化日志
init_logging() {
    # 创建日志目录
    if [[ ! -d "$LOG_DIR" ]]; then
        mkdir -p "$LOG_DIR" 2>/dev/null || {
            echo "⚠️ 无法创建日志目录，将使用临时日志"
            LOG_DIR="/tmp"
            LOG_FILE="$LOG_DIR/brce-ftp-install.log"
        }
    fi
    
    # 开始新的日志会话
    echo "=====================================================" >> "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $SCRIPT_NAME $SCRIPT_VERSION" >> "$LOG_FILE"
    echo "=====================================================" >> "$LOG_FILE"
}

# 增强的日志函数
log_info() {
    local msg="$*"
    echo -e "${GREEN}[INFO]${NC} $msg"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $msg" >> "$LOG_FILE"
}

log_warn() {
    local msg="$*"
    echo -e "${YELLOW}[WARN]${NC} $msg"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] $msg" >> "$LOG_FILE"
}

log_error() {
    local msg="$*"
    echo -e "${RED}[ERROR]${NC} $msg"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $msg" >> "$LOG_FILE"
}

log_debug() {
    local msg="$*"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [DEBUG] $msg" >> "$LOG_FILE"
}

# 记录函数执行
log_function_start() {
    local func_name="$1"
    log_debug "开始执行函数: $func_name"
}

log_function_end() {
    local func_name="$1"
    local result="$2"
    log_debug "函数执行完成: $func_name (返回值: $result)"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限，请使用 sudo 运行"
        exit 1
    fi
}

# 检查网络连接
check_network() {
    if ! ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        log_warn "网络连接检查失败，可能影响软件包安装"
        return 1
    fi
    return 0
}

# 检测包管理器
detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        echo "apt"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v zypper &> /dev/null; then
        echo "zypper"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    else
        echo "unknown"
    fi
}

# 安装vsftpd
install_vsftpd() {
    local pkg_manager=$(detect_package_manager)
    
    log_info "检测到包管理器: $pkg_manager"
    
    case $pkg_manager in
        apt)
            apt-get update -qq
            apt-get install -y vsftpd
            ;;
        yum)
            yum install -y vsftpd
            ;;
        dnf)
            dnf install -y vsftpd
            ;;
        zypper)
            zypper install -y vsftpd
            ;;
        pacman)
            pacman -S --noconfirm vsftpd
            ;;
        *)
            log_error "不支持的包管理器，请手动安装 vsftpd"
            return 1
            ;;
    esac
    
    log_info "vsftpd 安装完成"
}

# 生成配置文件
generate_vsftpd_config() {
    # 直接生成新配置，不备份
    log_info "生成vsftpd配置文件"
    
    # 确保关键目录存在
    mkdir -p /var/run/vsftpd/empty 2>/dev/null || true
    
    # 生成新配置
    cat > /etc/vsftpd.conf << EOF
# BRCE FTP Lite 配置文件 - 简化版

# 基本设置
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES

# 用户权限设置
chroot_local_user=NO
allow_writeable_chroot=YES

# PAM 认证
pam_service_name=vsftpd

# 被动模式配置
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100

# 安全设置
secure_chroot_dir=/var/run/vsftpd/empty

# 禁用不必要功能
userlist_enable=NO
tcp_wrappers=NO
guest_enable=NO
virtual_use_local_privs=NO

# 文件传输设置
ascii_upload_enable=YES
ascii_download_enable=YES

# 日志设置
xferlog_std_format=YES
log_ftp_protocol=NO

# 超时设置
idle_session_timeout=600
data_connection_timeout=120
EOF

    # 验证配置文件语法
    log_debug "验证配置文件语法"
    if vsftpd /etc/vsftpd.conf -t 2>/dev/null; then
        log_debug "配置文件语法验证通过"
    else
        log_warn "无法验证配置文件语法（可能vsftpd版本不支持-t选项）"
    fi
    
    log_info "vsftpd 配置文件已生成 - 简化配置，无chroot限制"
}

# 创建FTP用户 - 简化版
create_ftp_user() {
    log_function_start "create_ftp_user"
    local username="$1"
    local password="$2"
    local recording_dir="$3"
    
    log_debug "创建FTP用户参数: username=$username, recording_dir=$recording_dir"
    
    # 检查录制目录
    if [[ ! -d "$recording_dir" ]]; then
        log_error "录制目录不存在: $recording_dir"
        log_function_end "create_ftp_user" "1"
        return 1
    fi
    log_debug "录制目录检查通过: $recording_dir"
    
    # 检查用户是否已存在
    if id "$username" &>/dev/null; then
        log_warn "用户 $username 已存在，将重新配置"
        log_debug "删除现有用户: $username"
        userdel -r "$username" 2>/dev/null || true
        log_debug "用户删除完成"
    fi
    
    # 创建用户，直接使用录制目录作为家目录
    log_debug "执行: useradd -d $recording_dir -s /bin/bash $username"
    if useradd -d "$recording_dir" -s /bin/bash "$username"; then
        log_info "已创建用户: $username (家目录: $recording_dir)"
        log_debug "用户创建成功"
    else
        log_error "用户创建失败: $username"
        log_function_end "create_ftp_user" "1"
        return 1
    fi
    
    # 设置密码
    log_debug "设置用户密码"
    if echo "$username:$password" | chpasswd; then
        log_info "已设置用户密码"
        log_debug "密码设置成功"
    else
        log_error "密码设置失败"
        log_function_end "create_ftp_user" "1"
        return 1
    fi
    
    # 创建FTP用户组（用于管理和识别）- 必须先创建组
    if ! getent group ftp-users >/dev/null; then
        log_debug "创建ftp-users用户组"
        if groupadd ftp-users; then
            log_info "已创建 ftp-users 用户组"
        else
            log_error "ftp-users用户组创建失败"
            log_function_end "create_ftp_user" "1"
            return 1
        fi
    else
        log_debug "ftp-users用户组已存在"
    fi
    
    log_debug "将用户添加到ftp-users组"
    if usermod -a -G ftp-users "$username"; then
        log_debug "用户组添加成功"
    else
        log_error "用户组添加失败"
        log_function_end "create_ftp_user" "1"
        return 1
    fi
    
    # 设置录制目录权限 - 在创建用户组后执行
    log_debug "设置录制目录权限"
    log_debug "执行: chown root:ftp-users $recording_dir"
    
    # 先设置所有者
    if chown root:ftp-users "$recording_dir"; then
        log_debug "目录所有者设置成功: root:ftp-users"
    else
        log_error "目录所有者设置失败: chown root:ftp-users $recording_dir"
        log_function_end "create_ftp_user" "1"
        return 1
    fi
    
    log_debug "执行: chmod 775 $recording_dir"
    # 再设置权限
    if chmod 775 "$recording_dir"; then
        log_debug "目录权限设置成功: 775"
        log_info "目录权限配置完成: root:ftp-users 775"
    else
        log_error "目录权限设置失败: chmod 775 $recording_dir"
        log_function_end "create_ftp_user" "1"
        return 1
    fi
    
    log_info "FTP用户配置完成 - 用户登录后直接在录制目录 $recording_dir，可以读写删除文件"
    log_function_end "create_ftp_user" "0"
}



# 清理已存在用户的配置
cleanup_existing_user() {
    local username="$1"
    local user_home=$(getent passwd "$username" | cut -d: -f6)
    
    # 如果有旧的挂载点，先卸载
    if [[ -n "$user_home" && -d "$user_home/ftp" ]]; then
        if mountpoint -q "$user_home/ftp" 2>/dev/null; then
            log_info "卸载旧的挂载点: $user_home/ftp"
            umount "$user_home/ftp" 2>/dev/null || true
        fi
        
        # 从fstab中移除旧条目
        if grep -q "$user_home/ftp" /etc/fstab 2>/dev/null; then
            log_info "从 /etc/fstab 移除旧挂载条目"
            sed -i "\|$user_home/ftp|d" /etc/fstab
        fi
    fi
}

# 启动服务
start_services() {
    log_debug "准备启动vsftpd服务"
    
    # 检查配置文件是否存在
    if [[ ! -f /etc/vsftpd.conf ]]; then
        log_error "配置文件不存在: /etc/vsftpd.conf"
        return 1
    fi
    log_debug "配置文件存在: /etc/vsftpd.conf"
    
    # 确保关键目录存在
    log_debug "检查并创建关键目录"
    if ! mkdir -p /var/run/vsftpd/empty 2>/dev/null; then
        log_warn "无法创建vsftpd运行目录"
    else
        log_debug "vsftpd运行目录检查完成"
    fi
    
    # 设置目录权限
    chmod 755 /var/run/vsftpd 2>/dev/null || true
    chmod 755 /var/run/vsftpd/empty 2>/dev/null || true
    
    # 测试配置文件
    log_debug "获取vsftpd版本信息"
    if vsftpd -v 2>/dev/null; then
        log_debug "vsftpd版本信息获取成功"
    else
        log_warn "无法获取vsftpd版本信息"
    fi
    
    # 启动vsftpd
    log_debug "执行: systemctl start vsftpd"
    if systemctl start vsftpd; then
        log_debug "systemctl start 命令执行成功"
    else
        log_error "systemctl start 命令执行失败"
        log_debug "获取启动失败日志"
        # 获取详细错误信息
        journalctl -u vsftpd --no-pager -n 10 >> "$LOG_FILE" 2>&1
        return 1
    fi
    
    # 等待服务启动
    log_debug "等待服务启动完成"
    sleep 2
    
    log_debug "执行: systemctl enable vsftpd"
    if systemctl enable vsftpd; then
        log_debug "systemctl enable 命令执行成功"
    else
        log_warn "systemctl enable 命令执行失败"
    fi
    
    # 检查服务状态
    log_debug "检查服务启动状态"
    if systemctl is-active --quiet vsftpd; then
        log_info "vsftpd 服务启动成功"
        log_debug "服务状态: $(systemctl is-active vsftpd)"
    else
        log_error "vsftpd 服务启动失败"
        log_debug "服务状态: $(systemctl is-active vsftpd)"
        log_debug "获取服务状态详情"
        systemctl status vsftpd --no-pager -l >> "$LOG_FILE" 2>&1
        return 1
    fi
}

# 配置防火墙
configure_firewall() {
    log_info "配置防火墙端口..."
    
    # ufw
    if command -v ufw &> /dev/null; then
        ufw allow 21/tcp >/dev/null 2>&1
        ufw allow 40000:40100/tcp >/dev/null 2>&1
        log_info "已配置 ufw 防火墙规则"
    fi
    
    # firewall-cmd
    if command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=21/tcp >/dev/null 2>&1
        firewall-cmd --permanent --add-port=40000-40100/tcp >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
        log_info "已配置 firewall-cmd 防火墙规则"
    fi
    
    # iptables
    if command -v iptables &> /dev/null && ! command -v ufw &> /dev/null && ! command -v firewall-cmd &> /dev/null; then
        iptables -I INPUT -p tcp --dport 21 -j ACCEPT
        iptables -I INPUT -p tcp --dport 40000:40100 -j ACCEPT
        log_info "已配置 iptables 防火墙规则"
    fi
}

# 日志管理功能
manage_logs() {
    echo ""
    echo "======================================================"
    echo "📝 日志管理"
    echo "======================================================"
    echo ""
    echo "📁 日志文件位置: $LOG_FILE"
    echo ""
    
    if [[ -f "$LOG_FILE" ]]; then
        local log_size=$(du -h "$LOG_FILE" 2>/dev/null | cut -f1)
        local log_lines=$(wc -l < "$LOG_FILE" 2>/dev/null)
        echo "📊 日志信息："
        echo "   📏 文件大小: $log_size"
        echo "   📄 行数: $log_lines"
        echo ""
    else
        echo "⚠️ 日志文件不存在"
        echo ""
        read -p "按回车键返回主菜单..." -r
        return
    fi
    
    echo "请选择操作："
    echo "1) 📖 查看最新20行日志"
    echo "2) 📖 查看完整日志"
    echo "3) 🔍 搜索日志内容"
    echo "4) 🗑️ 清理日志文件"
    echo "0) ⬅️ 返回主菜单"
    echo ""
    read -p "请输入选项 (0-4): " log_choice
    
    case $log_choice in
        1)
            echo ""
            echo "📖 最新20行日志："
            echo "======================================================"
            tail -20 "$LOG_FILE" 2>/dev/null || echo "❌ 读取日志失败"
            echo "======================================================"
            ;;
        2)
            echo ""
            echo "📖 完整日志内容："
            echo "======================================================"
            cat "$LOG_FILE" 2>/dev/null || echo "❌ 读取日志失败"
            echo "======================================================"
            ;;
        3)
            echo ""
            read -p "🔍 请输入搜索关键词: " search_keyword
            if [[ -n "$search_keyword" ]]; then
                echo ""
                echo "🔍 搜索结果 (关键词: $search_keyword)："
                echo "======================================================"
                grep -i "$search_keyword" "$LOG_FILE" 2>/dev/null || echo "❌ 未找到匹配内容"
                echo "======================================================"
            else
                echo "❌ 搜索关键词不能为空"
            fi
            ;;
        4)
            echo ""
            echo "⚠️ 确认清理日志文件？"
            echo "📁 文件: $LOG_FILE"
            read -p "输入 'YES' 确认清理: " confirm_clean
            if [[ "$confirm_clean" == "YES" ]]; then
                if > "$LOG_FILE" 2>/dev/null; then
                    echo "✅ 日志文件已清理"
                    log_info "日志文件已被用户手动清理"
                else
                    echo "❌ 日志清理失败"
                fi
            else
                echo "❌ 清理已取消"
            fi
            ;;
        0)
            return
            ;;
        *)
            echo ""
            echo "❌ 无效选项！"
            sleep 2
            manage_logs
            return
            ;;
    esac
    
    echo ""
    read -p "按回车键返回主菜单..." -r
}

# 诊断vsftpd启动问题
diagnose_vsftpd() {
    echo ""
    echo "======================================================"
    echo "🔍 vsftpd 启动问题诊断"
    echo "======================================================"
    echo ""
    
    # 检查vsftpd是否安装
    echo "📋 检查vsftpd安装状态..."
    if command -v vsftpd >/dev/null 2>&1; then
        echo "✅ vsftpd 已安装"
        echo "   版本: $(vsftpd -v 2>&1 | head -1 || echo '无法获取版本')"
    else
        echo "❌ vsftpd 未安装"
        echo ""
        read -p "按回车键返回主菜单..." -r
        return 1
    fi
    
    # 检查配置文件
    echo ""
    echo "📋 检查配置文件..."
    if [[ -f /etc/vsftpd.conf ]]; then
        echo "✅ 配置文件存在: /etc/vsftpd.conf"
        echo "   文件大小: $(ls -lh /etc/vsftpd.conf | awk '{print $5}')"
        echo "   修改时间: $(ls -l /etc/vsftpd.conf | awk '{print $6, $7, $8}')"
    else
        echo "❌ 配置文件不存在: /etc/vsftpd.conf"
    fi
    
    # 检查服务状态
    echo ""
    echo "📋 检查服务状态..."
    echo "当前状态: $(systemctl is-active vsftpd 2>/dev/null || echo '未知')"
    echo "启用状态: $(systemctl is-enabled vsftpd 2>/dev/null || echo '未知')"
    
    # 尝试启动并获取错误信息
    echo ""
    echo "📋 尝试启动服务并获取错误信息..."
    echo "执行: systemctl start vsftpd"
    
    if systemctl start vsftpd 2>/dev/null; then
        echo "✅ 启动成功！"
        echo "当前状态: $(systemctl is-active vsftpd)"
    else
        echo "❌ 启动失败"
        echo ""
        echo "🔍 详细错误信息："
        echo "----------------------------------------"
        systemctl status vsftpd --no-pager -l 2>/dev/null || echo "无法获取状态信息"
        echo "----------------------------------------"
        echo ""
        echo "🔍 系统日志 (最近10条)："
        echo "----------------------------------------"
        journalctl -u vsftpd --no-pager -n 10 2>/dev/null || echo "无法获取日志信息"
        echo "----------------------------------------"
    fi
    
    # 检查端口占用
    echo ""
    echo "📋 检查端口占用..."
    if command -v ss >/dev/null 2>&1; then
        local port21=$(ss -tuln | grep ":21 " | wc -l)
        if [[ $port21 -gt 0 ]]; then
            echo "⚠️ 端口21已被占用："
            ss -tuln | grep ":21 " || echo "无法获取详细信息"
        else
            echo "✅ 端口21未被占用"
        fi
    elif command -v netstat >/dev/null 2>&1; then
        local port21=$(netstat -tuln | grep ":21 " | wc -l)
        if [[ $port21 -gt 0 ]]; then
            echo "⚠️ 端口21已被占用："
            netstat -tuln | grep ":21 " || echo "无法获取详细信息"
        else
            echo "✅ 端口21未被占用"
        fi
    else
        echo "⚠️ 无法检查端口占用（缺少ss或netstat命令）"
    fi
    
    # 检查关键目录
    echo ""
    echo "📋 检查关键目录..."
    
    # 检查secure_chroot_dir
    if [[ -d /var/run/vsftpd ]]; then
        echo "✅ vsftpd运行目录存在: /var/run/vsftpd"
    else
        echo "❌ vsftpd运行目录不存在: /var/run/vsftpd"
        echo "   尝试创建..."
        if mkdir -p /var/run/vsftpd/empty 2>/dev/null; then
            echo "   ✅ 创建成功"
        else
            echo "   ❌ 创建失败"
        fi
    fi
    
    # 检查empty目录
    if [[ -d /var/run/vsftpd/empty ]]; then
        echo "✅ chroot目录存在: /var/run/vsftpd/empty"
    else
        echo "❌ chroot目录不存在: /var/run/vsftpd/empty"
        echo "   尝试创建..."
        if mkdir -p /var/run/vsftpd/empty 2>/dev/null; then
            echo "   ✅ 创建成功"
        else
            echo "   ❌ 创建失败"
        fi
    fi
    
    # 检查用户和组
    echo ""
    echo "📋 检查FTP用户配置..."
    if getent group ftp-users >/dev/null 2>&1; then
        local ftp_users=$(getent group ftp-users | cut -d: -f4)
        if [[ -n "$ftp_users" ]]; then
            echo "✅ ftp-users组存在，用户: $ftp_users"
        else
            echo "⚠️ ftp-users组存在但无用户"
        fi
    else
        echo "❌ ftp-users组不存在"
    fi
    
    echo ""
    echo "💡 建议操作："
    echo "1. 如果是目录问题，已自动尝试创建"
    echo "2. 如果是端口占用，请停止占用端口的服务"
    echo "3. 如果是配置问题，请重新安装"
    echo "4. 查看上方的详细错误信息进行针对性修复"
    
    echo ""
    read -p "按回车键返回主菜单..." -r
}

# 生成随机密码
generate_password() {
    local length=${1:-12}
    # 使用字母和数字，避免特殊字符
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length"
}

# 获取服务器IP
get_server_ip() {
    # 尝试获取外网IP
    local external_ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null)
    if [[ -n "$external_ip" ]]; then
        echo "$external_ip"
    else
        # 获取内网IP
        local internal_ip=$(hostname -I | awk '{print $1}' 2>/dev/null)
        if [[ -n "$internal_ip" ]]; then
            echo "$internal_ip"
        else
            echo "localhost"
        fi
    fi
}

# 主安装函数
install_ftp_lite() {
    log_function_start "install_ftp_lite"
    
    echo ""
    echo "======================================================"
    echo "🚀 $SCRIPT_NAME 安装向导 $SCRIPT_VERSION"
    echo "======================================================"
    echo ""
    echo "📝 日志文件: $LOG_FILE"
    echo ""
    echo "💡 轻量版特性："
    echo "   • 🎯 统一目录: 录播姬和FTP共用 /opt/brec/file"
    echo "   • 🚀 一键部署: 所有配置都有默认值"
    echo "   • 🛡️ 完全兼容: 不干扰录播姬工作"
    echo ""
    
    log_info "开始安装流程"
    
    # 设置录制目录
    local recording_dir="/opt/brec/file"
    echo "📁 录制目录: $recording_dir"
    echo "💡 录播姬请设置输出目录为: $recording_dir"
    echo ""
    
    # 确认是否继续
    log_debug "等待用户确认安装"
    read -p "🤔 是否继续安装？录播姬需要配置输出到此目录 (Y/n): " confirm
    confirm=${confirm:-Y}
    log_debug "用户输入: $confirm"
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "❌ 安装已取消"
        log_info "用户取消安装"
        log_function_end "install_ftp_lite" "0"
        return 0
    fi
    log_info "用户确认继续安装"
    
    # 检查并创建录制目录
    log_debug "检查录制目录: $recording_dir"
    if [[ ! -d "$recording_dir" ]]; then
        echo "📁 创建录制目录: $recording_dir"
        log_debug "执行: mkdir -p $recording_dir"
        if mkdir -p "$recording_dir"; then
            log_info "已创建录制目录: $recording_dir"
        else
            log_error "创建录制目录失败: $recording_dir"
            log_function_end "install_ftp_lite" "1"
            return 1
        fi
    else
        echo "✅ 录制目录已存在: $recording_dir"
        log_debug "录制目录已存在: $recording_dir"
    fi
    
    # 获取FTP用户名
    log_debug "获取FTP用户名"
    read -p "👤 FTP用户名 (默认: sunny，直接回车使用默认): " ftp_user
    ftp_user=${ftp_user:-sunny}
    echo "✅ 使用FTP用户名: $ftp_user"
    log_debug "FTP用户名: $ftp_user"
    
    # 生成密码
    log_debug "获取FTP密码配置"
    read -p "🔐 自动生成密码？(Y/n，直接回车自动生成): " auto_pwd
    auto_pwd=${auto_pwd:-Y}
    log_debug "密码生成选择: $auto_pwd"
    
    if [[ "$auto_pwd" =~ ^[Yy]$ ]]; then
        log_debug "自动生成密码"
        ftp_password=$(generate_password 12)
        echo "✅ 已自动生成12位密码"
        log_info "已自动生成密码"
        log_debug "密码长度: ${#ftp_password}"
    else
        log_debug "手动输入密码"
        while true; do
            read -s -p "请输入FTP密码: " ftp_password
            echo ""
            read -s -p "请确认FTP密码: " ftp_password2
            echo ""
            
            if [[ "$ftp_password" == "$ftp_password2" ]]; then
                log_debug "密码确认成功"
                break
            else
                log_error "密码不匹配，请重新输入"
                log_debug "密码不匹配，重新输入"
            fi
        done
    fi
    
    # 显示配置信息
    echo ""
    echo "📋 安装配置："
    echo "   📁 录制目录: $recording_dir"
    echo "   👤 FTP用户: $ftp_user"
    echo "   🔧 登录方式: 用户直接访问录制目录，无chroot限制"
    echo "   📁 FTP目录: $recording_dir (与录制目录相同)"
    echo "   📁 用户权限: 可以读取、写入、删除文件"
    echo ""
    
    log_debug "等待用户最终确认"
    read -p "确认开始安装？(Y/n): " confirm
    confirm=${confirm:-Y}
    log_debug "最终确认: $confirm"
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "用户取消安装"
        log_function_end "install_ftp_lite" "1"
        return 1
    fi
    log_info "用户确认开始安装"
    
    # 开始安装
    echo ""
    echo "🚀 开始安装..."
    
    # 检查网络
    echo "🌐 检查网络连接..."
    log_debug "开始网络检查"
    if check_network; then
        log_debug "网络检查通过"
    else
        log_warn "网络检查失败，但继续安装"
    fi
    
    # 安装vsftpd
    echo "📦 步骤1/5: 安装vsftpd..."
    log_info "开始安装 vsftpd"
    log_debug "调用 install_vsftpd 函数"
    if ! install_vsftpd; then
        log_error "vsftpd 安装失败"
        echo "❌ 安装步骤失败，请检查网络连接和权限"
        echo "📝 详细日志请查看: $LOG_FILE"
        read -p "按回车键返回主菜单..." -r
        log_function_end "install_ftp_lite" "1"
        return 1
    fi
    echo "✅ vsftpd 安装完成"
    log_info "vsftpd 安装成功"
    
    # 创建FTP用户
    echo "👤 步骤2/5: 创建FTP用户..."
    log_info "开始配置FTP用户: $ftp_user"
    log_debug "调用 create_ftp_user 函数，参数: user=$ftp_user, dir=$recording_dir"
    if ! create_ftp_user "$ftp_user" "$ftp_password" "$recording_dir"; then
        log_error "FTP用户配置失败"
        echo "❌ 用户配置失败"
        echo "📝 详细日志请查看: $LOG_FILE"
        read -p "按回车键返回主菜单..." -r
        log_function_end "install_ftp_lite" "1"
        return 1
    fi
    echo "✅ FTP用户创建完成"
    log_info "FTP用户创建成功: $ftp_user"
    
    # 生成配置
    echo "⚙️ 步骤3/5: 生成配置文件..."
    log_info "开始生成vsftpd配置文件"
    log_debug "调用 generate_vsftpd_config 函数"
    if generate_vsftpd_config; then
        echo "✅ 配置文件生成完成"
        log_info "vsftpd配置文件生成成功"
    else
        log_error "配置文件生成失败"
        echo "❌ 配置文件生成失败"
        echo "📝 详细日志请查看: $LOG_FILE"
        read -p "按回车键返回主菜单..." -r
        log_function_end "install_ftp_lite" "1"
        return 1
    fi
    
    # 配置防火墙
    echo "🔥 步骤4/5: 配置防火墙..."
    log_info "开始配置防火墙"
    log_debug "调用 configure_firewall 函数"
    if configure_firewall; then
        echo "✅ 防火墙配置完成"
        log_info "防火墙配置成功"
    else
        log_warn "防火墙配置失败，但继续安装"
    fi
    
    # 启动服务
    echo "🚀 步骤5/5: 启动服务..."
    log_info "开始启动服务"
    log_debug "调用 start_services 函数"
    if ! start_services; then
        log_error "服务启动失败"
        echo "❌ 服务启动失败"
        echo "📝 详细日志请查看: $LOG_FILE"
        read -p "按回车键返回主菜单..." -r
        log_function_end "install_ftp_lite" "1"
        return 1
    fi
    echo "✅ 服务启动完成"
    log_info "服务启动成功"
    
    # 获取服务器IP
    log_debug "获取服务器IP地址"
    local server_ip=$(get_server_ip)
    log_debug "服务器IP: $server_ip"
    
    # 显示安装结果
    echo ""
    echo "======================================================"
    echo "🎉 $SCRIPT_NAME 安装完成！"
    echo "======================================================"
    echo ""
    log_info "安装流程全部完成"
    log_info "服务器IP: $server_ip, FTP用户: $ftp_user, 录制目录: $recording_dir"
    
    echo "📋 连接信息："
    echo "   🌐 服务器地址: $server_ip"
    echo "   🔌 FTP端口: 21"
    echo "   👤 用户名: $ftp_user"
    echo "   🔐 密码: $ftp_password"
    echo "   📁 登录目录: $recording_dir"
    echo "   📁 录制目录: $recording_dir (与FTP目录相同)"
    
    echo ""
    echo "💡 特性说明："
    echo "   • 📁 统一目录: 录播姬和FTP使用相同目录，无需映射"
    echo "   • 🚀 实时可见: 录制文件立即显示"
    echo "   • 🛡️ 完全兼容: 不会干扰录播姬录制过程"
    echo "   • 💾 零消耗: 无后台进程，无bind mount"
    echo "   • ✏️ 完整权限: 用户可以下载、上传、删除、重命名文件"
    echo "   • 🔧 简单配置: 无复杂chroot或权限问题"
    echo ""
    echo "🔧 常用命令："
    echo "   • 重启FTP服务: sudo systemctl restart vsftpd"
    echo "   • 查看服务状态: sudo systemctl status vsftpd"
    echo "   • 重新运行脚本: sudo $0"
    echo ""
    echo "📝 日志文件: $LOG_FILE"
    echo ""
    
    log_function_end "install_ftp_lite" "0"
    read -p "按回车键返回主菜单..." -r
}

# 停止FTP服务
stop_ftp_service() {
    echo ""
    echo "======================================================"
    echo "⏹️ 停止FTP服务"
    echo "======================================================"
    echo ""
    
    # 检查当前状态
    if ! systemctl is-active --quiet vsftpd; then
        echo "ℹ️ vsftpd服务已经停止"
        echo ""
        read -p "按回车键返回主菜单..." -r
        return 0
    fi
    
    echo "🔄 正在停止vsftpd服务..."
    echo ""
    
    # 停止服务
    if systemctl stop vsftpd; then
        echo "✅ vsftpd服务停止成功"
        echo "🔴 服务状态: 已停止"
    else
        echo "❌ vsftpd服务停止失败"
        echo ""
        echo "📊 当前状态："
        systemctl status vsftpd --no-pager -l | head -5
    fi
    
    echo ""
    read -p "按回车键返回主菜单..." -r
}

# 列出所有用户
list_users() {
    echo ""
    echo "======================================================"
    echo "📋 FTP用户列表"
    echo "======================================================"
    echo ""
    
    local recording_dir="/opt/brec/file"
    local ftp_users_found=false
    
    # 检查FTP用户（通过ftp-users组）
    if getent group ftp-users >/dev/null 2>&1; then
        local ftp_users=$(getent group ftp-users | cut -d: -f4)
        if [[ -n "$ftp_users" ]]; then
            echo "👥 FTP用户："
            for username in $(echo "$ftp_users" | tr ',' ' '); do
                if id "$username" &>/dev/null; then
                    echo "   👤 $username"
                    echo "      📁 家目录: $recording_dir"
                    echo "      📁 录制目录: $recording_dir"
                    echo "      🔗 访问状态: 直接访问（无映射）"
                    echo ""
                    ftp_users_found=true
                fi
            done
        fi
    fi
    
    if [[ "$ftp_users_found" == "false" ]]; then
        echo "❌ 未找到FTP用户"
        echo "💡 请先使用菜单选项1进行安装配置"
    fi
    
    echo ""
    read -p "按回车键返回主菜单..." -r
}

# 显示服务状态
show_status() {
    echo ""
    echo "======================================================"
    echo "📊 $SCRIPT_NAME 服务状态"
    echo "======================================================"
    echo ""
    
    # 检查vsftpd状态
    if systemctl is-active --quiet vsftpd; then
        echo "✅ vsftpd 服务: 运行中"
    else
        echo "❌ vsftpd 服务: 未运行"
    fi
    
    # 检查端口
    if ss -tlnp | grep -q ":21 "; then
        echo "✅ FTP端口21: 已开放"
    else
        echo "❌ FTP端口21: 未开放"
    fi
    
    # 显示FTP用户
    echo ""
    echo "📋 FTP用户列表:"
    local ftp_users_found=false
    local recording_dir="/opt/brec/file"
    
    # 检查FTP用户（通过ftp-users组）
    if getent group ftp-users >/dev/null 2>&1; then
        local ftp_users=$(getent group ftp-users | cut -d: -f4)
        if [[ -n "$ftp_users" ]]; then
            for username in $(echo "$ftp_users" | tr ',' ' '); do
                if id "$username" &>/dev/null; then
                    echo "   👤 $username"
                    echo "      📁 家目录: $recording_dir"
                    echo "      📁 录制目录: $recording_dir"
                    echo "      🔗 访问状态: 直接访问（无映射）"
                    ftp_users_found=true
                fi
            done
        fi
    fi
    
    if [[ "$ftp_users_found" == "false" ]]; then
        echo "   (无FTP用户)"
    fi
    
    echo ""
    read -p "按回车键返回主菜单..." -r
}

# 用户管理
manage_users() {
    while true; do
        echo ""
        echo "======================================================"
        echo "👥 用户管理"
        echo "======================================================"
        echo ""
        echo "请选择操作："
        echo "1) 📄 查看所有FTP用户"
        echo "2) ➕ 添加新用户"
        echo "3) 🔑 更改用户密码"
        echo "4) 🗑️ 删除用户"
        echo "0) ⬅️ 返回主菜单"
        echo ""
        read -p "请输入选项 (0-4): " choice
        
        case $choice in
            1) list_users ;;
            2) add_user ;;
            3) change_password ;;
            4) delete_user ;;
            0) break ;;
            *) log_error "无效选项！请输入 0-4 之间的数字" && sleep 2 ;;
        esac
    done
}

# 列出用户 - 专业版
list_users() {
    echo ""
    echo "📋 FTP用户详细状态"
    echo ""
    
    # 检查ftp-users组
    if ! getent group ftp-users >/dev/null 2>&1; then
        echo "❌ ftp-users 用户组不存在"
        echo "💡 建议: 先安装FTP服务"
        echo ""
        read -p "按回车键返回..." -r
        return 1
    fi
    
    # 获取组信息
    local group_info=$(getent group ftp-users)
    local group_id=$(echo "$group_info" | cut -d: -f3)
    local ftp_users=$(echo "$group_info" | cut -d: -f4)
    
    echo "📊 用户组信息:"
    echo "   组名: ftp-users"
    echo "   组ID: $group_id"
    echo "   原始数据: $group_info"
    echo ""
    
    # 分析用户状态
    local valid_count=0
    local ghost_count=0
    local recording_dir="/opt/brec/file"
    
    if [[ -n "$ftp_users" ]]; then
        echo "🔍 用户状态分析:"
        echo ""
        
        for username in $(echo "$ftp_users" | tr ',' ' '); do
            if [[ -n "$username" ]]; then
                echo "👤 用户: $username"
                
                # 检查系统用户是否存在
                if id "$username" &>/dev/null 2>&1; then
                    ((valid_count++))
                    echo "   ✅ 系统状态: 存在"
                    
                    # 获取用户详细信息
                    local user_info=$(getent passwd "$username")
                    local user_id=$(echo "$user_info" | cut -d: -f3)
                    local user_gid=$(echo "$user_info" | cut -d: -f4)
                    local user_home=$(echo "$user_info" | cut -d: -f6)
                    local user_shell=$(echo "$user_info" | cut -d: -f7)
                    
                    echo "   📊 用户ID: $user_id"
                    echo "   📊 主组ID: $user_gid"
                    echo "   🏠 家目录: $user_home"
                    echo "   🐚 登录Shell: $user_shell"
                    
                    # 检查家目录
                    if [[ -d "$user_home" ]]; then
                        echo "   📁 家目录状态: 存在"
                        local home_size=$(du -sh "$user_home" 2>/dev/null | cut -f1 || echo "未知")
                        echo "   📏 家目录大小: $home_size"
                    else
                        echo "   ❌ 家目录状态: 不存在"
                    fi
                    
                    # 检查录制目录访问
                    if [[ -d "$recording_dir" ]]; then
                        if [[ -r "$recording_dir" && -w "$recording_dir" ]]; then
                            echo "   ✅ 录制目录权限: 可读写"
                        else
                            echo "   ⚠️ 录制目录权限: 权限不足"
                        fi
                    else
                        echo "   ❌ 录制目录: 不存在"
                    fi
                    
                    # 检查进程
                    local process_count=$(ps -u "$username" 2>/dev/null | wc -l)
                    if [[ $process_count -gt 1 ]]; then
                        echo "   🔄 活跃进程: $((process_count-1)) 个"
                    else
                        echo "   💤 活跃进程: 无"
                    fi
                    
                else
                    ((ghost_count++))
                    echo "   ❌ 系统状态: 不存在（僵尸用户）"
                    echo "   💡 建议: 需要清理"
                fi
                echo ""
            fi
        done
    else
        echo "📋 组中无用户"
    fi
    
    # 统计信息
    echo "📊 统计总结:"
    echo "   ✅ 有效用户: $valid_count 个"
    echo "   ❌ 僵尸用户: $ghost_count 个"
    echo "   📁 录制目录: $recording_dir"
    
    # 检查录制目录状态
    if [[ -d "$recording_dir" ]]; then
        local dir_owner=$(stat -c "%U:%G" "$recording_dir" 2>/dev/null || echo "未知")
        local dir_perms=$(stat -c "%a" "$recording_dir" 2>/dev/null || echo "未知")
        local dir_size=$(du -sh "$recording_dir" 2>/dev/null | cut -f1 || echo "未知")
        echo "   📁 目录所有者: $dir_owner"
        echo "   📁 目录权限: $dir_perms"
        echo "   📁 目录大小: $dir_size"
    else
        echo "   ❌ 录制目录不存在"
    fi
    
    if [[ $ghost_count -gt 0 ]]; then
        echo ""
        echo "⚠️ 发现僵尸用户，建议使用删除用户功能进行清理"
    fi
    
    echo ""
    read -p "按回车键返回..." -r
}

# 添加用户
add_user() {
    echo ""
    echo "➕ 添加新用户"
    echo ""
    
    read -p "👤 新用户名 (直接回车取消): " new_username
    if [[ -z "$new_username" ]]; then
        echo "❌ 用户名不能为空，已取消"
        read -p "按回车键返回..." -r
        return 1
    fi
    
    if id "$new_username" &>/dev/null; then
        log_error "用户 $new_username 已存在"
        read -p "按回车键返回..." -r
        return 1
    fi
    
    read -p "📁 请输入要映射的源目录 (默认: /root/brec/file): " source_dir
    source_dir=${source_dir:-/root/brec/file}
    
    if [[ ! -d "$source_dir" ]]; then
        log_error "源目录不存在: $source_dir"
        read -p "按回车键返回..." -r
        return 1
    fi
    
    # 生成密码
    local new_password=$(generate_password 12)
    
    echo ""
    echo "📋 新用户信息："
    echo "   👤 用户名: $new_username"
    echo "   🔐 密码: $new_password"
    echo "   📁 源目录: $source_dir"
    echo "   📁 FTP目录: /home/$new_username/ftp (读写映射到 $source_dir)"
    echo "   📁 用户权限: 可以读取、写入、删除文件"
    echo ""
    
    read -p "确认添加此用户？(Y/n): " confirm
    confirm=${confirm:-Y}
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        if create_ftp_user "$new_username" "$new_password" "/opt/brec/file"; then
            echo ""
            echo "✅ 用户添加成功！"
            echo "   👤 用户名: $new_username"
            echo "   🔐 密码: $new_password"
            echo "   📁 用户家目录: /opt/brec/file"
            echo "   📁 录制目录: /opt/brec/file (与家目录相同)"
            echo "   📁 用户权限: 可以读取、写入、删除文件"
        else
            log_error "用户添加失败"
        fi
    else
        log_info "取消添加用户"
    fi
    
    echo ""
    read -p "按回车键返回用户管理..." -r
}

# 更改密码
change_password() {
    echo ""
    echo "🔑 更改用户密码"
    echo ""
    
    # 列出用户
    local users=()
    if getent group ftp-users >/dev/null 2>&1; then
        local ftp_users=$(getent group ftp-users | cut -d: -f4)
        if [[ -n "$ftp_users" ]]; then
            for username in $(echo "$ftp_users" | tr ',' ' '); do
                if id "$username" &>/dev/null; then
                    users+=("$username")
                fi
            done
        fi
    fi
    
    if [[ ${#users[@]} -eq 0 ]]; then
        log_error "没有FTP用户"
        read -p "按回车键返回..." -r
        return 1
    fi
    
    echo "📋 当前用户："
    for i in "${!users[@]}"; do
        echo "$((i+1)). ${users[$i]}"
    done
    echo ""
    
    read -p "请输入要修改密码的用户名: " target_user
    
    if ! id "$target_user" &>/dev/null; then
        log_error "用户不存在: $target_user"
        read -p "按回车键返回..." -r
        return 1
    fi
    
    # 生成新密码
    local new_password=$(generate_password 12)
    
    echo ""
    echo "📋 密码信息："
    echo "   👤 用户: $target_user"
    echo "   🔐 新密码: $new_password"
    echo ""
    
    read -p "确认修改密码？(Y/n): " confirm
    confirm=${confirm:-Y}
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "$target_user:$new_password" | chpasswd
        echo ""
        echo "✅ 密码修改成功！"
        echo "   👤 用户: $target_user"
        echo "   🔐 新密码: $new_password"
    else
        log_info "取消密码修改"
    fi
    
    echo ""
    read -p "按回车键返回用户管理..." -r
}

# 删除用户 - 专业版
delete_user() {
    echo ""
    echo "🗑️ 删除用户 (调试模式)"
    echo ""
    
    # 第一步：详细诊断当前用户状态
    echo "🔍 诊断当前用户状态..."
    
    # 检查ftp-users组是否存在
    if ! getent group ftp-users >/dev/null 2>&1; then
        log_error "ftp-users 用户组不存在，没有FTP用户可删除"
        read -p "按回车键返回..." -r
        return 1
    fi
    
    # 获取组中的用户列表
    local group_info=$(getent group ftp-users)
    local ftp_users=$(echo "$group_info" | cut -d: -f4)
    echo "📊 ftp-users组信息: $group_info"
    echo "📋 组中用户列表: '$ftp_users'"
    
    # 分析用户状态
    local valid_users=()
    local ghost_users=()
    
    if [[ -n "$ftp_users" ]]; then
        echo ""
        echo "🔍 分析每个用户状态:"
        for username in $(echo "$ftp_users" | tr ',' ' '); do
            if [[ -n "$username" ]]; then
                echo "   检查用户: $username"
                if id "$username" &>/dev/null; then
                    valid_users+=("$username")
                    echo "     ✅ 系统用户存在"
                else
                    ghost_users+=("$username")
                    echo "     ❌ 系统用户不存在（僵尸用户）"
                fi
            fi
        done
    fi
    
    echo ""
    echo "📊 用户状态统计:"
    echo "   有效用户数: ${#valid_users[@]}"
    echo "   僵尸用户数: ${#ghost_users[@]}"
    
    # 如果有僵尸用户，提供清理选项
    if [[ ${#ghost_users[@]} -gt 0 ]]; then
        echo ""
        echo "⚠️ 发现僵尸用户（在组中但系统不存在）:"
        for ghost in "${ghost_users[@]}"; do
            echo "     👻 $ghost"
        done
        echo ""
        read -p "是否先清理僵尸用户？(Y/n): " clean_ghost
        clean_ghost=${clean_ghost:-Y}
        
        if [[ "$clean_ghost" =~ ^[Yy]$ ]]; then
            echo "🧹 清理僵尸用户..."
            for ghost in "${ghost_users[@]}"; do
                echo "   清理: $ghost"
                if gpasswd -d "$ghost" ftp-users 2>/dev/null; then
                    echo "     ✅ 已从组中移除"
                else
                    echo "     ❌ 从组中移除失败"
                    # 尝试手动编辑组文件
                    echo "     🔧 尝试手动修复..."
                    sed -i "s/,$ghost//g; s/$ghost,//g; s/:$ghost:/::/g" /etc/group 2>/dev/null || true
                    if ! getent group ftp-users | grep -q "$ghost"; then
                        echo "     ✅ 手动修复成功"
                    else
                        echo "     ❌ 手动修复失败"
                    fi
                fi
            done
            
            # 重新获取清理后的用户列表
            group_info=$(getent group ftp-users)
            ftp_users=$(echo "$group_info" | cut -d: -f4)
            valid_users=()
            if [[ -n "$ftp_users" ]]; then
                for username in $(echo "$ftp_users" | tr ',' ' '); do
                    if [[ -n "$username" ]] && id "$username" &>/dev/null; then
                        valid_users+=("$username")
                    fi
                done
            fi
            echo "✅ 僵尸用户清理完成"
        fi
    fi
    
    # 检查是否还有可删除的用户
    if [[ ${#valid_users[@]} -eq 0 ]]; then
        echo ""
        log_error "没有有效的FTP用户可删除"
        read -p "按回车键返回..." -r
        return 1
    fi
    
    echo ""
    echo "📋 可删除的用户："
    for i in "${!valid_users[@]}"; do
        echo "$((i+1)). 👤 ${valid_users[$i]}"
        echo "     🏠 家目录: $(getent passwd "${valid_users[$i]}" | cut -d: -f6)"
        echo "     🐚 Shell: $(getent passwd "${valid_users[$i]}" | cut -d: -f7)"
    done
    echo ""
    
    read -p "请输入要删除的用户名: " target_user
    
    # 验证输入的用户
    local user_found=false
    for user in "${valid_users[@]}"; do
        if [[ "$user" == "$target_user" ]]; then
            user_found=true
            break
        fi
    done
    
    if [[ "$user_found" == false ]]; then
        log_error "用户 '$target_user' 不在可删除列表中"
        read -p "按回车键返回..." -r
        return 1
    fi
    
    local recording_dir="/opt/brec/file"
    
    echo ""
    echo "⚠️ 即将删除用户: $target_user"
    echo "   📁 当前家目录: $(getent passwd "$target_user" | cut -d: -f6)"
    echo "   🎯 录制目录: $recording_dir"
    echo "   💡 注意: 录制目录和文件将完全保留"
    echo ""
    
    read -p "确认删除用户 $target_user？(y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo ""
        echo "🗑️ 开始删除用户: $target_user"
        
        local delete_success=true
        
        # 第一步：从ftp-users组中移除
        echo "   📝 步骤1: 从ftp-users组中移除用户..."
        if getent group ftp-users | grep -q "\b$target_user\b"; then
            echo "     🔍 用户确实在组中"
            if gpasswd -d "$target_user" ftp-users 2>/dev/null; then
                echo "     ✅ gpasswd 命令执行成功"
            else
                echo "     ❌ gpasswd 命令失败，尝试手动编辑"
                # 备份组文件
                cp /etc/group /etc/group.backup.$(date +%s) 2>/dev/null || true
                # 手动移除用户
                sed -i "s/,$target_user//g; s/$target_user,//g; s/:$target_user:/::/g" /etc/group 2>/dev/null || true
                delete_success=false
            fi
            
            # 验证是否从组中移除成功
            if getent group ftp-users | grep -q "\b$target_user\b"; then
                echo "     ❌ 用户仍在组中，移除失败"
                delete_success=false
            else
                echo "     ✅ 用户已从组中移除"
            fi
        else
            echo "     ℹ️ 用户不在ftp-users组中"
        fi
        
        # 第二步：删除系统用户
        echo "   🗑️ 步骤2: 删除系统用户..."
        if id "$target_user" &>/dev/null; then
            echo "     🔍 用户存在于系统中"
            # 先杀死用户进程
            pkill -u "$target_user" 2>/dev/null || true
            sleep 1
            
            # 删除用户（不删除家目录）
            if userdel "$target_user" 2>/dev/null; then
                echo "     ✅ userdel 命令执行成功"
            else
                echo "     ❌ userdel 命令失败"
                delete_success=false
                
                # 尝试强制删除
                echo "     🔧 尝试强制删除..."
                if userdel -f "$target_user" 2>/dev/null; then
                    echo "     ✅ 强制删除成功"
                else
                    echo "     ❌ 强制删除也失败"
                fi
            fi
        else
            echo "     ℹ️ 用户不存在于系统中"
        fi
        
        # 第三步：最终验证
        echo "   🔍 步骤3: 验证删除结果..."
        local final_check=true
        
        # 检查系统用户
        if id "$target_user" &>/dev/null; then
            echo "     ❌ 系统用户仍然存在"
            final_check=false
        else
            echo "     ✅ 系统用户已删除"
        fi
        
        # 检查组成员
        if getent group ftp-users | grep -q "\b$target_user\b"; then
            echo "     ❌ 用户仍在ftp-users组中"
            final_check=false
        else
            echo "     ✅ 用户已从ftp-users组中移除"
        fi
        
        echo ""
        if [[ "$final_check" == true ]]; then
            echo "🎉 用户删除完全成功: $target_user"
            echo "💾 录制目录 $recording_dir 及所有文件已保留"
        else
            echo "⚠️ 用户删除不完整!"
            echo "🔧 建议操作:"
            echo "   1. 重启服务器后重试"
            echo "   2. 手动检查 /etc/passwd 和 /etc/group"
            echo "   3. 联系系统管理员"
        fi
    else
        log_info "取消删除操作"
    fi
    
    echo ""
    read -p "按回车键返回..." -r
}

# 启动FTP服务
start_ftp_service() {
    echo ""
    echo "======================================================"
    echo "🚀 启动FTP服务"
    echo "======================================================"
    echo ""
    
    # 检查vsftpd是否已安装
    if ! systemctl list-unit-files vsftpd.service >/dev/null 2>&1; then
        echo "❌ vsftpd服务未安装"
        echo "💡 请先使用菜单选项1进行安装配置"
        echo ""
        read -p "按回车键返回主菜单..." -r
        return 1
    fi
    
    # 检查当前状态
    if systemctl is-active --quiet vsftpd; then
        echo "ℹ️ vsftpd服务已经在运行中"
        echo ""
        echo "📊 服务状态信息："
        systemctl status vsftpd --no-pager -l | head -10
        echo ""
        read -p "按回车键返回主菜单..." -r
        return 0
    fi
    
    echo "🔄 正在启动vsftpd服务..."
    echo ""
    
    # 启动服务
    if systemctl start vsftpd; then
        echo "✅ vsftpd服务启动成功"
        
        # 检查服务状态
        if systemctl is-active --quiet vsftpd; then
            echo "🟢 服务状态: 运行中"
            
            # 启用开机自启
            if systemctl enable vsftpd >/dev/null 2>&1; then
                echo "✅ 已设置开机自启动"
            fi
            
            echo ""
            echo "📊 服务详细信息："
            systemctl status vsftpd --no-pager -l | head -8
            
            echo ""
            echo "🌐 FTP服务信息："
            echo "   - 服务端口: 21"
            echo "   - 被动端口: 40000-40100"
            
            # 检查网络IP
            local server_ip=""
            if command -v hostname >/dev/null 2>&1; then
                server_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "获取失败")
            fi
            if [[ -n "$server_ip" && "$server_ip" != "获取失败" ]]; then
                echo "   - 内网地址: ftp://$server_ip"
            fi
            
            # 检查是否有用户
            if getent group ftp-users >/dev/null 2>&1; then
                local user_count=$(getent group ftp-users | cut -d: -f4 | tr ',' '\n' | wc -l)
                if [[ $user_count -gt 0 ]]; then
                    echo "   - FTP用户数: $user_count 个"
                else
                    echo "   - FTP用户数: 0 个 (建议先创建用户)"
                fi
            else
                echo "   - FTP用户数: 0 个 (建议先创建用户)"
            fi
            
        else
            echo "⚠️ 服务启动后状态异常"
        fi
    else
        echo "❌ vsftpd服务启动失败"
        echo ""
        echo "🔍 错误信息："
        journalctl -u vsftpd --no-pager -n 5 2>/dev/null || echo "无法获取日志信息"
        echo ""
        echo "💡 建议检查："
        echo "   - 配置文件是否正确"
        echo "   - 端口是否被占用"
        echo "   - 防火墙设置"
    fi
    
    echo ""
    read -p "按回车键返回主菜单..." -r
}

# 停止FTP服务
stop_ftp_service() {
    echo ""
    echo "======================================================"
    echo "⏹️ 停止FTP服务"
    echo "======================================================"
    echo ""
    
    # 检查vsftpd是否已安装
    if ! systemctl list-unit-files vsftpd.service >/dev/null 2>&1; then
        echo "ℹ️ vsftpd服务未安装或不存在"
        echo ""
        read -p "按回车键返回主菜单..." -r
        return 0
    fi
    
    # 检查当前状态
    if ! systemctl is-active --quiet vsftpd; then
        echo "ℹ️ vsftpd服务已经处于停止状态"
        echo ""
        echo "📊 服务状态："
        systemctl status vsftpd --no-pager -l | head -5
        echo ""
        read -p "按回车键返回主菜单..." -r
        return 0
    fi
    
    echo "📋 当前vsftpd服务正在运行"
    echo ""
    
    # 显示当前连接数
    local connections=0
    if command -v ss >/dev/null 2>&1; then
        connections=$(ss -tuln | grep ":21 " | wc -l 2>/dev/null || echo "0")
    fi
    
    if [[ $connections -gt 0 ]]; then
        echo "⚠️ 检测到活跃FTP连接: $connections 个"
        echo "💡 停止服务将断开所有现有连接"
    else
        echo "ℹ️ 当前无活跃FTP连接"
    fi
    
    echo ""
    read -p "🛑 确认停止vsftpd服务？(y/N): " confirm_stop
    
    if [[ ! "$confirm_stop" =~ ^[Yy]$ ]]; then
        echo "✅ 已取消停止操作"
        echo ""
        read -p "按回车键返回主菜单..." -r
        return 0
    fi
    
    echo ""
    echo "🔄 正在停止vsftpd服务..."
    
    # 停止服务
    if systemctl stop vsftpd; then
        echo "✅ vsftpd服务已停止"
        
        # 验证停止状态
        sleep 1
        if ! systemctl is-active --quiet vsftpd; then
            echo "🔴 服务状态: 已停止"
            
            # 询问是否禁用开机自启
            echo ""
            read -p "是否同时禁用开机自启动？(y/N): " disable_autostart
            
            if [[ "$disable_autostart" =~ ^[Yy]$ ]]; then
                if systemctl disable vsftpd >/dev/null 2>&1; then
                    echo "✅ 已禁用开机自启动"
                else
                    echo "⚠️ 禁用开机自启动失败"
                fi
            else
                echo "ℹ️ 保持开机自启动设置"
            fi
            
            echo ""
            echo "📊 服务状态信息："
            systemctl status vsftpd --no-pager -l | head -5
            
        else
            echo "⚠️ 服务停止后状态异常"
        fi
    else
        echo "❌ vsftpd服务停止失败"
        echo ""
        echo "🔍 可能原因："
        echo "   - 服务进程异常"
        echo "   - 权限不足"
        echo "   - 系统资源问题"
        echo ""
        echo "💡 可尝试强制停止："
        echo "   sudo systemctl kill vsftpd"
    fi
    
    echo ""
    read -p "按回车键返回主菜单..." -r
}

# 检查网络连接
check_network_connection() {
    if ! ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        log_error "网络连接失败，请检查网络设置"
        return 1
    fi
    return 0
}

# 在线更新脚本
update_script() {
    echo ""
    echo "======================================================"
    echo "🔄 $SCRIPT_NAME 在线更新"
    echo "======================================================"
    echo ""
    echo "⚠️ 注意事项："
    echo "   • 当前版本: $SCRIPT_VERSION (已移除备份功能)"
    echo "   • GitHub版本可能与本地版本不同"
    echo "   • 更新可能会恢复到旧版本(有备份功能)"
    echo "   • 建议仅在确实需要时进行更新"
    echo ""
    echo "请选择更新方式："
    echo "1) 🔍 检查更新 (智能更新)"
    echo "2) ⚡ 强制更新 (直接覆盖)"
    echo "3) 🔧 修复GitHub版本语法错误后更新"
    echo "0) ⬅️ 返回主菜单"
    echo ""
    read -p "请输入选项 (0-3): " update_choice
    
    case $update_choice in
        1)
            perform_smart_update
            echo ""
            read -p "按回车键返回主菜单..." -r
            ;;
        2)
            perform_force_update
            echo ""
            read -p "按回车键返回主菜单..." -r
            ;;
        3)
            perform_fix_and_update
            echo ""
            read -p "按回车键返回主菜单..." -r
            ;;
        0)
            return 0
            ;;
        *)
            echo ""
            echo "❌ 无效选项！请输入 0-3 之间的数字"
            sleep 2
            update_script
            ;;
    esac
}

# 智能更新功能
perform_smart_update() {
    echo ""
    echo "🔍 开始智能更新检查..."
    echo "======================================================"
    
    local SCRIPT_URL="https://raw.githubusercontent.com/Sannylew/bilirec-ftp-sync/main/ftp-setup-lite.sh"
    local CURRENT_SCRIPT="$(readlink -f "$0")"
    local TEMP_SCRIPT="/tmp/ftp_setup_lite_new.sh"

    
    echo "📋 更新信息："
    echo "   - 当前脚本: $CURRENT_SCRIPT"
    echo "   - 远程仓库: https://github.com/Sannylew/bilirec-ftp-sync"
    echo ""
    
    # 检查网络连接
    if ! check_network_connection; then
        return 1
    fi
    
    # 下载最新版本
    echo "📥 下载最新版本..."
    if curl -s --max-time 30 "$SCRIPT_URL" -o "$TEMP_SCRIPT" 2>/dev/null; then
        if [[ -f "$TEMP_SCRIPT" && -s "$TEMP_SCRIPT" ]]; then
            # 检查是否是有效的shell脚本
            if head -1 "$TEMP_SCRIPT" | grep -q "#!/bin/bash"; then
                echo "✅ 下载成功"
            else
                echo "❌ 下载的文件格式无效"
                rm -f "$TEMP_SCRIPT"
                return 1
            fi
        else
            echo "❌ 下载失败或文件为空"
            rm -f "$TEMP_SCRIPT"
            return 1
        fi
    else
        echo "❌ 下载失败，请检查网络连接"
        return 1
    fi
    
    # 提取版本信息
    local CURRENT_VERSION=$(grep "SCRIPT_VERSION=" "$CURRENT_SCRIPT" | head -1 | cut -d'"' -f2 2>/dev/null || echo "未知")
    local NEW_VERSION=$(grep "SCRIPT_VERSION=" "$TEMP_SCRIPT" | head -1 | cut -d'"' -f2 2>/dev/null || echo "未知")
    
    # 计算文件内容差异
    local content_changed=false
    if ! diff -q "$CURRENT_SCRIPT" "$TEMP_SCRIPT" >/dev/null 2>&1; then
        content_changed=true
    fi
    
    # 获取文件大小信息
    local current_size=$(wc -c < "$CURRENT_SCRIPT" 2>/dev/null || echo "0")
    local new_size=$(wc -c < "$TEMP_SCRIPT" 2>/dev/null || echo "0")
    local current_lines=$(wc -l < "$CURRENT_SCRIPT" 2>/dev/null || echo "0")
    local new_lines=$(wc -l < "$TEMP_SCRIPT" 2>/dev/null || echo "0")
    
    echo ""
    echo "📊 版本和内容对比："
    echo "   - 当前版本: $CURRENT_VERSION"
    echo "   - 最新版本: $NEW_VERSION"
    echo "   - 当前文件: $current_lines 行, $current_size 字节"
    echo "   - 远程文件: $new_lines 行, $new_size 字节"
    
    if [[ "$content_changed" == "true" ]]; then
        echo "   - 📝 文件内容: 有差异 (建议更新)"
    else
        echo "   - ✅ 文件内容: 完全相同"
    fi
    echo ""
    
    # 智能更新判断
    local should_update=false
    local update_reason=""
    
    if [[ "$content_changed" == "true" ]]; then
        should_update=true
        if [[ "$CURRENT_VERSION" != "$NEW_VERSION" ]]; then
            update_reason="发现新版本和内容变更"
        else
            update_reason="发现内容变更 (版本号相同但代码已更新)"
        fi
    elif [[ "$CURRENT_VERSION" != "$NEW_VERSION" ]] && [[ "$NEW_VERSION" != "未知" ]]; then
        should_update=true
        update_reason="发现新版本"
    fi
    
    if [[ "$should_update" == "true" ]]; then
        echo "🆕 $update_reason"
        echo "💡 建议进行更新以获取最新功能和修复"
        echo ""
        read -p "🔄 确定要更新吗？(Y/n): " confirm_update
        confirm_update=${confirm_update:-Y}
    else
        echo "ℹ️  当前脚本已是最新版本 (版本和内容均相同)"
        echo ""
        read -p "是否强制更新？(y/N): " confirm_update
        confirm_update=${confirm_update:-N}
    fi
    
    if [[ ! "$confirm_update" =~ ^[Yy]$ ]]; then
        echo "✅ 取消更新，保持当前版本"
        rm -f "$TEMP_SCRIPT"
        return 0
    fi
    
    # 执行更新
    execute_update "$TEMP_SCRIPT"
}

# 强制更新功能
perform_force_update() {
    echo ""
    echo "⚡ 开始强制更新..."
    echo "======================================================"
    
    local SCRIPT_URL="https://raw.githubusercontent.com/Sannylew/bilirec-ftp-sync/main/ftp-setup-lite.sh"
    local CURRENT_SCRIPT="$(readlink -f "$0")"
    local TEMP_SCRIPT="/tmp/ftp_setup_lite_new.sh"

    
    echo "📋 强制更新信息："
    echo "   - 当前脚本: $CURRENT_SCRIPT"
    echo "   - 远程地址: $SCRIPT_URL"
    echo ""
    
    # 检查网络连接
    if ! check_network_connection; then
        return 1
    fi
    
    echo "⚠️ 强制更新将无条件覆盖当前脚本"
    read -p "确认执行强制更新？(y/N): " confirm_force
    if [[ ! "$confirm_force" =~ ^[Yy]$ ]]; then
        echo "✅ 取消强制更新"
        return 0
    fi
    
    # 下载最新版本
    echo ""
    echo "📥 下载最新版本..."
    if curl -s --max-time 30 "$SCRIPT_URL" -o "$TEMP_SCRIPT" 2>/dev/null; then
        if [[ -f "$TEMP_SCRIPT" && -s "$TEMP_SCRIPT" ]]; then
            if head -1 "$TEMP_SCRIPT" | grep -q "#!/bin/bash"; then
                echo "✅ 下载成功"
            else
                echo "❌ 下载的文件格式无效"
                rm -f "$TEMP_SCRIPT"
                return 1
            fi
        else
            echo "❌ 下载失败或文件为空"
            rm -f "$TEMP_SCRIPT"
            return 1
        fi
    else
        echo "❌ 下载失败，请检查网络连接"
        return 1
    fi
    
    # 执行更新
    execute_update "$TEMP_SCRIPT"
}

# 修复GitHub版本并更新
perform_fix_and_update() {
    echo ""
    echo "🔧 修复GitHub版本语法错误后更新"
    echo "======================================================"
    
    local SCRIPT_URL="https://raw.githubusercontent.com/Sannylew/bilirec-ftp-sync/main/ftp-setup-lite.sh"
    local CURRENT_SCRIPT="$(readlink -f "$0")"
    local TEMP_SCRIPT="/tmp/ftp_setup_lite_new.sh"
    
    # 检查网络连接
    if ! check_network_connection; then
        return 1
    fi
    
    echo "📥 下载GitHub版本..."
    if curl -s --max-time 30 "$SCRIPT_URL" -o "$TEMP_SCRIPT" 2>/dev/null; then
        if [[ -f "$TEMP_SCRIPT" && -s "$TEMP_SCRIPT" ]]; then
            echo "✅ 下载成功"
        else
            echo "❌ 下载失败"
            return 1
        fi
    else
        echo "❌ 下载失败"
        return 1
    fi
    
    echo "🔧 修复已知语法错误..."
    # 修复 {bei 错误
    if grep -q "{bei" "$TEMP_SCRIPT"; then
        sed -i 's/{bei/{/g' "$TEMP_SCRIPT"
        echo "   ✅ 修复了 {bei 语法错误"
    fi
    
    # 验证修复后的语法
    echo "🔍 验证修复后的脚本语法..."
    if ! bash -n "$TEMP_SCRIPT" 2>/dev/null; then
        echo "❌ 修复后仍有语法错误，无法更新"
        rm -f "$TEMP_SCRIPT"
        return 1
    fi
    echo "✅ 语法验证通过"
    
    echo ""
    echo "⚠️ 注意：更新后可能会恢复到GitHub版本(可能包含备份功能)"
    read -p "确认执行修复更新？(y/N): " confirm_fix
    if [[ ! "$confirm_fix" =~ ^[Yy]$ ]]; then
        echo "✅ 取消更新"
        rm -f "$TEMP_SCRIPT"
        return 0
    fi
    
    # 执行更新
    execute_update "$TEMP_SCRIPT"
}

# 执行更新操作
execute_update() {
    local temp_script="$1"
    local backup_script="$2"  # 向后兼容，但不使用
    local current_script="$(readlink -f "$0")"
    
    echo ""
    echo "🔄 执行更新操作..."
    
    # 验证新脚本语法
    echo "🔍 验证新脚本..."
    if ! bash -n "$temp_script" 2>/dev/null; then
        echo "❌ 新脚本语法错误，可能的原因："
        echo "   • GitHub版本存在语法错误"
        echo "   • 版本不兼容"
        echo "   • 下载过程中文件损坏"
        echo ""
        echo "🔧 建议："
        echo "   • 检查网络连接"
        echo "   • 稍后重试"
        echo "   • 或继续使用当前版本"
        rm -f "$temp_script"
        return 1
    fi
    echo "✅ 脚本验证通过"
    
    # 替换脚本
    echo "🔄 替换脚本文件..."
    if ! cp "$temp_script" "$current_script"; then
        echo "❌ 脚本替换失败"
        rm -f "$temp_script"
        return 1
    fi
    
    # 设置执行权限
    chmod +x "$current_script"
    rm -f "$temp_script"
    
    echo "✅ 脚本替换成功"
    echo ""
    echo "🎉 更新完成！"
    echo ""
    echo "📋 更新后信息："
    local new_version=$(grep "SCRIPT_VERSION=" "$current_script" | head -1 | cut -d'"' -f2 2>/dev/null || echo "未知")
    echo "   - 新版本: $new_version"
    echo ""
    echo "💡 提示："
    echo "   - 更新已完成，建议重新运行脚本"
    echo ""
    
    read -p "是否立即重启脚本？(Y/n): " restart_script
    restart_script=${restart_script:-Y}
    
    if [[ "$restart_script" =~ ^[Yy]$ ]]; then
        echo ""
        echo "🚀 重启脚本..."
        sleep 2
        exec "$current_script"
    fi
}

# 卸载服务
uninstall_service() {
    echo ""
    echo "======================================================"
    echo "🗑️ 卸载 $SCRIPT_NAME"
    echo "======================================================"
    echo ""
    
    echo "⚠️ 这将删除："
    echo "   • 所有FTP用户和用户组"
    echo "   • vsftpd服务配置"
    echo "   • FTP相关配置文件"
    echo ""
    echo "💡 保留的内容："
    echo "   • 源目录数据（录播文件安全）"
    echo "   • vsftpd软件包"
    echo "   • 脚本文件（可选择删除）"
    echo ""
    
    read -p "确认卸载？(y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "取消卸载"
        read -p "按回车键返回主菜单..." -r
        return 0
    fi
    
    echo ""
    echo "🗑️ 开始卸载..."
    
    # 停止服务
    log_info "停止vsftpd服务..."
    systemctl stop vsftpd 2>/dev/null || true
    systemctl disable vsftpd 2>/dev/null || true
    
    # 删除FTP用户
    log_info "删除FTP用户..."
    if getent group ftp-users >/dev/null 2>&1; then
        local ftp_users=$(getent group ftp-users | cut -d: -f4)
        if [[ -n "$ftp_users" ]]; then
            for username in $(echo "$ftp_users" | tr ',' ' '); do
                if id "$username" &>/dev/null; then
                    # 先从组中移除，再删除用户
                    gpasswd -d "$username" ftp-users 2>/dev/null || true
                    # 删除用户（不删除录制目录）
                    userdel "$username" 2>/dev/null || true
                    log_info "已删除用户: $username"
                fi
            done
        fi
    fi
    
    # 删除FTP用户组
    log_info "删除用户组..."
    groupdel ftp-users 2>/dev/null || true
    
    # 移除配置文件
    log_info "移除配置文件..."
    rm -f /etc/vsftpd.conf
    
    echo ""
    echo "✅ 卸载完成！"
    echo ""
    
    # 询问是否删除脚本本身
    echo "🤔 是否要删除脚本文件本身？"
    echo ""
    echo "选择操作："
    echo "1) 保留脚本文件 (可重新安装)"
    echo "2) 删除脚本文件 (完全清理)"
    echo ""
    read -p "请选择 (1/2，默认1): " delete_choice
    delete_choice=${delete_choice:-1}
    
    case $delete_choice in
        2)
            echo ""
            echo "⚠️ 确认删除脚本文件？此操作不可恢复"
            read -p "输入 'DELETE' 确认删除脚本: " confirm_delete
            if [[ "$confirm_delete" == "DELETE" ]]; then
                local script_path="$(readlink -f "$0")"
                echo ""
                echo "🗑️ 删除脚本文件: $script_path"
                
                # 创建一个临时脚本来删除主脚本
                cat > /tmp/cleanup_ftp_script.sh << 'EOF'
#!/bin/bash
sleep 1
rm -f "$1"
echo "✅ 脚本文件已删除"
echo "🎉 $SCRIPT_NAME 已完全卸载"
EOF
                chmod +x /tmp/cleanup_ftp_script.sh
                
                echo "🎉 $SCRIPT_NAME 完全卸载完成！"
                echo "💡 感谢使用！"
                
                # 执行清理脚本并退出
                exec /tmp/cleanup_ftp_script.sh "$script_path"
            else
                echo "❌ 删除已取消，脚本文件保留"
            fi
            ;;
        1|*)
            echo ""
            echo "💡 提示："
            echo "   • 源目录数据已保留"
            echo "   • 脚本文件已保留: $0"
            echo "   • 如需重新安装，请重新运行此脚本"
            ;;
    esac
    
    echo ""
    read -p "按回车键退出..." -r
    exit 0
}

# 主菜单
main_menu() {
    while true; do
        clear
        echo "======================================================"
        echo "🚀 $SCRIPT_NAME 管理控制台 $SCRIPT_VERSION"
        echo "======================================================"
        echo ""
        echo "💡 轻量版特性: 直接目录访问 + 零资源消耗 + 完全兼容录播姬"
        echo "📁 录制目录: /opt/brec/file (录播姬和FTP共用)"
        echo ""
            echo "请选择操作："
    echo ""
    echo "📦 安装与配置："
    echo "1) 🚀 安装FTP服务"
    echo ""
    echo "🔧 服务管理："
    echo "2) 📊 查看服务状态"
    echo "3) ▶️ 启动FTP服务"
    echo "4) ⏹️ 停止FTP服务"
    echo "5) 🔄 重启FTP服务"
    echo ""
    echo "👥 用户管理："
    echo "6) 📋 列出所有用户"
    echo "7) ➕ 添加新用户"
    echo "8) 🔐 修改用户密码"
    echo "9) 🗑️ 删除用户"
    echo ""
    echo "🛠️ 系统功能："
    echo "10) 📝 查看日志"
    echo "11) 🧹 清理日志"
    echo "12) 🔍 诊断启动问题"
    echo "13) 🔄 在线更新"
    echo "14) 🗑️ 卸载服务"
    echo ""
    echo "0) 🚪 退出"
        echo ""
        echo "📝 快捷键： Ctrl+C 快速退出"
        echo ""
            echo "💡 使用提示："
    echo "   • 首次使用: 选择 1) 安装FTP服务"
    echo "   • 录播姬输出目录: /opt/brec/file"
    echo "   • 所有选项都有默认值，直接回车即可"
        echo ""
        read -p "请输入选项 (0-14): " choice
        
        case $choice in
            1) install_ftp_lite ;;
            2) 
                show_status
                echo ""
                read -p "按回车键返回主菜单..." -r
                ;;
            3) start_ftp_service ;;
            4) stop_ftp_service ;;
            5) 
                echo ""
                echo "🔄 重启vsftpd服务..."
                systemctl restart vsftpd
                if systemctl is-active --quiet vsftpd; then
                    echo "✅ 服务重启成功"
                else
                    echo "❌ 服务重启失败"
                fi
                echo ""
                read -p "按回车键返回主菜单..." -r
                ;;
            6) list_users ;;
            7) add_user ;;
            8) change_password ;;
            9) delete_user ;;
            10) 
                echo ""
                echo "📖 查看最新20行日志："
                echo "======================================================"
                tail -20 "$LOG_FILE" 2>/dev/null || echo "❌ 读取日志失败"
                echo "======================================================"
                echo ""
                read -p "按回车键返回主菜单..." -r
                ;;
            11) 
                echo ""
                echo "⚠️ 确认清理日志文件？"
                echo "📁 文件: $LOG_FILE"
                read -p "输入 'YES' 确认清理: " confirm_clean
                if [[ "$confirm_clean" == "YES" ]]; then
                    if > "$LOG_FILE" 2>/dev/null; then
                        echo "✅ 日志文件已清理"
                        log_info "日志文件已被用户手动清理"
                    else
                        echo "❌ 日志清理失败"
                    fi
                else
                    echo "❌ 清理已取消"
                fi
                echo ""
                read -p "按回车键返回主菜单..." -r
                ;;
            12) diagnose_vsftpd ;;
            13) update_script ;;
            14) uninstall_service ;;
            0) 
                echo ""
                echo "👋 感谢使用 $SCRIPT_NAME！"
                exit 0
                ;;
            *) 
                echo ""
                echo "❌ 无效选项！请输入 0-14 之间的数字"
                echo "ℹ️  提示：输入数字后按回车键确认"
                sleep 2
                ;;
        esac
    done
}

# 清理函数
cleanup_and_exit() {
    local exit_code=${1:-0}
    echo ""
    echo "👋 感谢使用 $SCRIPT_NAME！"
    exit $exit_code
}

# 信号处理
trap 'cleanup_and_exit 1' SIGINT SIGTERM

# 主程序入口
main() {
    # 检查root权限
    check_root
    
    # 初始化日志系统
    init_logging
    
    # 显示欢迎信息
    echo "======================================================"
    echo "🚀 欢迎使用 $SCRIPT_NAME $SCRIPT_VERSION"
    echo "======================================================"
    echo ""
    echo "💡 专为录播姬设计的轻量版FTP："
    echo "   • 🎯 录播姬和FTP共用统一目录"
    echo "   • 🚀 一键部署，全程默认配置"
    echo "   • 🛡️ 零干扰，完全兼容录播姬"
    echo "   • 💾 无后台服务，零资源消耗"
    echo ""
    
    read -p "按回车键进入主菜单..." -r
    
    # 进入主菜单
    main_menu
}

# 启动程序
main "$@"
