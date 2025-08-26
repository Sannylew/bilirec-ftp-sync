#!/bin/bash

# BRCE FTP 轻量版部署脚本
# 版本: v1.0.0-lite
# 功能: 只读bind mount映射 + FTP服务
# 适合: 只需要文件分享，无需实时同步的用户

set -o pipefail

# 脚本信息
SCRIPT_VERSION="v1.0.0-lite"
SCRIPT_NAME="BRCE FTP Lite"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
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
    # 备份原配置
    if [[ -f "/etc/vsftpd.conf" ]]; then
        cp "/etc/vsftpd.conf" "/etc/vsftpd.conf.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "已备份原配置文件"
    fi
    
    # 生成新配置
    cat > /etc/vsftpd.conf << EOF
# BRCE FTP Lite 配置文件
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=YES
delete_enable=YES
local_umask=022
file_open_mode=0666
allow_writeable_chroot=YES
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
chroot_local_user=YES
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
rsa_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
rsa_private_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
ssl_enable=NO

# 被动模式配置
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100
pasv_address=
EOF

    log_info "vsftpd 配置文件已生成 - 用户被限制在家目录内"
}

# 创建FTP用户
create_ftp_user() {
    local username="$1"
    local password="$2"
    local source_dir="$3"
    
    # 检查源目录
    if [[ ! -d "$source_dir" ]]; then
        log_error "源目录不存在: $source_dir"
        return 1
    fi
    
    # 检查用户是否已存在
    if id "$username" &>/dev/null; then
        log_warn "用户 $username 已存在，将重新配置"
        # 清理旧的挂载点
        cleanup_existing_user "$username"
    else
        # 创建用户，但家目录设为/home/username/ftp
        useradd -m -s /bin/bash "$username"
        log_info "已创建用户: $username"
    fi
    
    # 设置密码
    echo "$username:$password" | chpasswd
    log_info "已设置用户密码"
    
    # 创建FTP目录结构
    local ftp_home="/home/$username/ftp"
    mkdir -p "$ftp_home"
    
    # 关键：chroot环境下的权限设置
    # 家目录的父目录必须属于root且不能被其他用户写入
    chown root:root "/home/$username"
    chmod 755 "/home/$username"
    
    # ftp目录初始权限设置
    chown root:root "$ftp_home"
    chmod 755 "$ftp_home"
    
    # 修改用户家目录指向ftp目录，这样用户登录后直接到ftp目录
    usermod -d "$ftp_home" "$username"
    
    # 创建读写bind mount映射
    log_info "创建读写映射: $source_dir -> $ftp_home"
    mount --bind "$source_dir" "$ftp_home"
    
    # bind mount后重新设置权限
    # 重要：bind mount后需要重新设置挂载点的权限
    chown "$username:ftp-users" "$ftp_home"
    chmod 755 "$ftp_home"
    
    # 设置源目录权限（这会影响到挂载点）
    chmod 755 "$source_dir"
    chown root:ftp-users "$source_dir" 2>/dev/null || true
    chmod 775 "$source_dir" 2>/dev/null || true
    
    # 确保父目录权限正确（chroot要求）
    chown root:root "/home/$username"
    chmod 755 "/home/$username"
    
    # 添加到fstab以实现开机自动挂载
    local fstab_entry="$source_dir $ftp_home none bind 0 0"
    if ! grep -q "$ftp_home" /etc/fstab; then
        echo "$fstab_entry" >> /etc/fstab
        log_info "已添加到 /etc/fstab 实现开机自动挂载"
    fi
    
    # 创建FTP用户组（用于管理和识别）
    if ! getent group ftp-users >/dev/null; then
        groupadd ftp-users
        log_info "已创建 ftp-users 用户组"
    fi
    usermod -a -G ftp-users "$username"
    
    log_info "FTP用户配置完成 - 用户登录后直接在 $ftp_home，可以读写删除源目录内容"
}

# 修复FTP权限问题
fix_ftp_permissions() {
    echo ""
    echo "🔧 修复FTP权限问题..."
    echo ""
    
    local fixed=false
    
    # 检查所有FTP用户目录
    for user_home in /home/*/ftp; do
        if [[ -d "$user_home" ]]; then
            local username=$(basename $(dirname "$user_home"))
            echo "🔧 修复用户 $username 的权限..."
            
            # 修复chroot目录权限（关键！）
            echo "   🔧 修复chroot权限结构..."
            chown root:root "/home/$username"
            chmod 755 "/home/$username"
            
            # 修复挂载点权限
            if mountpoint -q "$user_home"; then
                local source_dir=$(findmnt -n -o SOURCE "$user_home")
                echo "   📁 修复源目录权限: $source_dir"
                
                # 先设置源目录权限
                chmod 775 "$source_dir"
                chown root:ftp-users "$source_dir" 2>/dev/null || true
                
                # 再设置挂载点权限
                chown "$username:ftp-users" "$user_home"
                chmod 755 "$user_home"
            else
                echo "   ⚠️ 警告: $user_home 不是挂载点，可能需要重新挂载"
            fi
            
            # 确保用户在ftp-users组中
            usermod -a -G ftp-users "$username" 2>/dev/null || true
            
            echo "   ✅ 用户 $username 权限修复完成"
            fixed=true
        fi
    done
    
    if [[ "$fixed" == "true" ]]; then
        echo ""
        echo "🔄 重启vsftpd服务..."
        systemctl restart vsftpd
        if systemctl is-active --quiet vsftpd; then
            echo "✅ 服务重启成功"
        else
            echo "❌ 服务重启失败"
        fi
        echo ""
        echo "🔍 权限诊断信息："
        echo "   - vsftpd配置: /etc/vsftpd.conf"
        echo "   - 检查配置: allow_writeable_chroot=YES"
        if grep -q "allow_writeable_chroot=YES" /etc/vsftpd.conf 2>/dev/null; then
            echo "   ✅ chroot配置正确"
        else
            echo "   ❌ 缺少 allow_writeable_chroot=YES 配置"
            echo ""
            echo "🔧 添加缺失配置..."
            echo "allow_writeable_chroot=YES" >> /etc/vsftpd.conf
            echo "   ✅ 已添加 allow_writeable_chroot=YES"
        fi
        echo ""
        echo "🎉 权限修复完成！请重新尝试FTP操作"
    else
        echo "ℹ️  未找到需要修复的FTP用户"
    fi
    
    echo ""
    read -p "按回车键返回主菜单..." -r
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
    # 启动vsftpd
    systemctl start vsftpd
    systemctl enable vsftpd
    
    if systemctl is-active --quiet vsftpd; then
        log_info "vsftpd 服务启动成功"
    else
        log_error "vsftpd 服务启动失败"
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
    echo ""
    echo "======================================================"
    echo "🚀 $SCRIPT_NAME 安装向导 $SCRIPT_VERSION"
    echo "======================================================"
    echo ""
    echo "💡 轻量版特性："
    echo "   • 只读bind mount映射 - 零资源消耗"
    echo "   • 实时文件访问 - 录制文件立即可见"
    echo "   • 完全兼容录播姬 - 无任何干扰"
    echo "   • 简单易用 - 一键部署"
    echo ""
    
    # 获取源目录
    read -p "📁 请输入录播姬目录路径 (默认: /root/brec/file): " source_dir
    source_dir=${source_dir:-/root/brec/file}
    
    # 检查源目录
    if [[ ! -d "$source_dir" ]]; then
        log_warn "目录 $source_dir 不存在"
        read -p "是否创建此目录？(y/N): " create_dir
        if [[ "$create_dir" =~ ^[Yy]$ ]]; then
            mkdir -p "$source_dir"
            log_info "已创建目录: $source_dir"
        else
            log_error "安装取消"
            return 1
        fi
    fi
    
    # 获取FTP用户名
    read -p "👤 请输入FTP用户名 (默认: sunny): " ftp_user
    ftp_user=${ftp_user:-sunny}
    
    # 生成密码
    read -p "🔐 自动生成密码？(Y/n): " auto_pwd
    auto_pwd=${auto_pwd:-Y}
    
    if [[ "$auto_pwd" =~ ^[Yy]$ ]]; then
        ftp_password=$(generate_password 12)
        log_info "已自动生成密码"
    else
        while true; do
            read -s -p "请输入FTP密码: " ftp_password
            echo ""
            read -s -p "请确认FTP密码: " ftp_password2
            echo ""
            
            if [[ "$ftp_password" == "$ftp_password2" ]]; then
                break
            else
                log_error "密码不匹配，请重新输入"
            fi
        done
    fi
    
    # 显示配置信息
    echo ""
    echo "📋 安装配置："
    echo "   📁 源目录: $source_dir"
    echo "   👤 FTP用户: $ftp_user"
    echo "   🔧 登录方式: 用户被限制在家目录内，登录后进入根目录"
    echo "   📁 FTP目录: /home/$ftp_user/ftp (读写映射到 $source_dir)"
    echo "   📁 用户权限: 可以读取、写入、删除文件"
    echo ""
    
    read -p "确认开始安装？(Y/n): " confirm
    confirm=${confirm:-Y}
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "安装取消"
        return 1
    fi
    
    # 开始安装
    echo ""
    echo "🚀 开始安装..."
    
    # 检查网络
    check_network
    
    # 安装vsftpd
    log_info "正在安装 vsftpd..."
    if ! install_vsftpd; then
        log_error "vsftpd 安装失败"
        return 1
    fi
    
    # 创建FTP用户
    log_info "正在配置FTP用户..."
    if ! create_ftp_user "$ftp_user" "$ftp_password" "$source_dir"; then
        log_error "FTP用户配置失败"
        return 1
    fi
    
    # 生成配置
    log_info "正在生成配置文件..."
    generate_vsftpd_config
    
    # 配置防火墙
    configure_firewall
    
    # 启动服务
    log_info "正在启动服务..."
    if ! start_services; then
        log_error "服务启动失败"
        return 1
    fi
    
    # 获取服务器IP
    local server_ip=$(get_server_ip)
    
    # 显示安装结果
    echo ""
    echo "======================================================"
    echo "🎉 $SCRIPT_NAME 安装完成！"
    echo "======================================================"
    echo ""
    echo "📋 连接信息："
    echo "   🌐 服务器地址: $server_ip"
    echo "   🔌 FTP端口: 21"
    echo "   👤 用户名: $ftp_user"
    echo "   🔐 密码: $ftp_password"
    echo "   📁 登录目录: / (用户被限制在家目录内，显示为根目录)"
    echo "   📁 实际目录: /home/$ftp_user/ftp (映射到 $source_dir)"
    
    echo ""
    echo "💡 特性说明："
    echo "   • 📍 安全限制: 用户被限制在家目录内，无法访问其他系统目录"
    echo "   • 🔗 读写映射: 该目录映射到录播文件目录，支持读写"
    echo "   • 🚀 实时可见: 录制文件立即显示"
    echo "   • 🛡️ 完全兼容: 不会干扰录播姬录制过程"
    echo "   • 💾 零消耗: 无后台进程，直接bind mount"
    echo "   • ✏️ 完整权限: 用户可以下载、上传、删除、重命名文件"
    echo ""
    echo "🔧 常用命令："
    echo "   • 重启FTP服务: sudo systemctl restart vsftpd"
    echo "   • 查看服务状态: sudo systemctl status vsftpd"
    echo "   • 重新运行脚本: sudo $0"
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
    
    # 检查FTP用户（通过检查/home/*/ftp目录）
    for user_home in /home/*/ftp; do
        if [[ -d "$user_home" ]]; then
            local username=$(basename $(dirname "$user_home"))
            echo "   👤 $username"
            echo "      📁 家目录: $user_home"
            
            # 检查映射状态
            if mountpoint -q "$user_home"; then
                echo "      🔗 映射状态: 已映射"
                local source_dir=$(findmnt -n -o SOURCE "$user_home")
                echo "      📁 映射源: $source_dir"
            else
                echo "      ❌ 映射状态: 未映射"
            fi
            ftp_users_found=true
        fi
    done
    
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

# 列出用户
list_users() {
    echo ""
    echo "📋 当前FTP用户："
    local count=0
    
    # 显示FTP用户（通过检查/home/*/ftp目录）
    for user_home in /home/*/ftp; do
        if [[ -d "$user_home" ]]; then
            local username=$(basename $(dirname "$user_home"))
            ((count++))
            echo "$count. 👤 $username"
            echo "   📁 家目录: $user_home"
            
            # 检查映射状态
            if mountpoint -q "$user_home"; then
                local source_dir=$(findmnt -n -o SOURCE "$user_home")
                echo "   🔗 映射到: $source_dir"
            else
                echo "   ❌ 映射状态: 未映射"
            fi
        fi
    done
    
    if [[ $count -eq 0 ]]; then
        echo "   (无FTP用户)"
    fi
    
    echo ""
    read -p "按回车键返回用户管理..." -r
}

# 添加用户
add_user() {
    echo ""
    echo "➕ 添加新用户"
    echo ""
    
    read -p "👤 请输入新用户名: " new_username
    if [[ -z "$new_username" ]]; then
        log_error "用户名不能为空"
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
        if create_ftp_user "$new_username" "$new_password" "$source_dir"; then
            echo ""
            echo "✅ 用户添加成功！"
            echo "   👤 用户名: $new_username"
            echo "   🔐 密码: $new_password"
            echo "   📁 用户家目录: /home/$new_username/ftp"
            echo "   🔗 映射源目录: $source_dir (读写权限)"
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
    for user_home in /home/*/ftp; do
        if [[ -d "$user_home" ]]; then
            local username=$(basename $(dirname "$user_home"))
            users+=("$username")
        fi
    done
    
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

# 删除用户
delete_user() {
    echo ""
    echo "🗑️ 删除用户"
    echo ""
    
    # 列出用户
    local users=()
    for user_home in /home/*/ftp; do
        if [[ -d "$user_home" ]]; then
            local username=$(basename $(dirname "$user_home"))
            users+=("$username")
        fi
    done
    
    if [[ ${#users[@]} -eq 0 ]]; then
        log_error "没有FTP用户可删除"
        read -p "按回车键返回..." -r
        return 1
    fi
    
    echo "📋 当前用户："
    for i in "${!users[@]}"; do
        echo "$((i+1)). ${users[$i]}"
    done
    echo ""
    
    read -p "请输入要删除的用户名: " target_user
    
    if ! id "$target_user" &>/dev/null; then
        log_error "用户不存在: $target_user"
        read -p "按回车键返回..." -r
        return 1
    fi
    
    local user_home="/home/$target_user/ftp"
    
    echo ""
    echo "⚠️ 即将删除用户: $target_user"
    echo "   📁 将删除目录: /home/$target_user"
    if mountpoint -q "$user_home"; then
        echo "   🔗 将卸载映射"
    fi
    echo ""
    
    read -p "确认删除用户 $target_user？(y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # 卸载映射
        if mountpoint -q "$user_home"; then
            umount "$user_home"
            sed -i "\|$user_home|d" /etc/fstab
        fi
        
        # 删除用户
        userdel -r "$target_user" 2>/dev/null || true
        
        echo ""
        echo "✅ 用户删除成功: $target_user"
    else
        log_info "取消删除操作"
    fi
    
    echo ""
    read -p "按回车键返回用户管理..." -r
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
    echo "请选择更新方式："
    echo "1) 🔍 检查更新 (智能更新)"
    echo "2) ⚡ 强制更新 (直接覆盖)"
    echo "0) ⬅️ 返回主菜单"
    echo ""
    echo "💡 说明："
    echo "   • 智能更新: 比较版本和内容，仅在有差异时更新"
    echo "   • 强制更新: 无条件从GitHub获取最新代码"
    echo ""
    read -p "请输入选项 (0-2): " update_choice
    
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
        0)
            return 0
            ;;
        *)
            echo ""
            echo "❌ 无效选项！请输入 0-2 之间的数字"
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
    local BACKUP_SCRIPT="${CURRENT_SCRIPT}.backup.$(date +%Y%m%d_%H%M%S)"
    
    echo "📋 更新信息："
    echo "   - 当前脚本: $CURRENT_SCRIPT"
    echo "   - 远程仓库: https://github.com/Sannylew/bilirec-ftp-sync"
    echo "   - 备份位置: $BACKUP_SCRIPT"
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
    execute_update "$TEMP_SCRIPT" "$BACKUP_SCRIPT"
}

# 强制更新功能
perform_force_update() {
    echo ""
    echo "⚡ 开始强制更新..."
    echo "======================================================"
    
    local SCRIPT_URL="https://raw.githubusercontent.com/Sannylew/bilirec-ftp-sync/main/ftp-setup-lite.sh"
    local CURRENT_SCRIPT="$(readlink -f "$0")"
    local TEMP_SCRIPT="/tmp/ftp_setup_lite_new.sh"
    local BACKUP_SCRIPT="${CURRENT_SCRIPT}.backup.$(date +%Y%m%d_%H%M%S)"
    
    echo "📋 强制更新信息："
    echo "   - 当前脚本: $CURRENT_SCRIPT"
    echo "   - 远程地址: $SCRIPT_URL"
    echo "   - 备份位置: $BACKUP_SCRIPT"
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
    execute_update "$TEMP_SCRIPT" "$BACKUP_SCRIPT"
}

# 执行更新操作
execute_update() {
    local temp_script="$1"
    local backup_script="$2"
    local current_script="$(readlink -f "$0")"
    
    echo ""
    echo "🔄 执行更新操作..."
    
    # 备份当前脚本
    echo "💾 备份当前脚本..."
    if ! cp "$current_script" "$backup_script"; then
        echo "❌ 备份失败"
        rm -f "$temp_script"
        return 1
    fi
    echo "✅ 备份完成: $backup_script"
    
    # 验证新脚本语法
    echo "🔍 验证新脚本..."
    if ! bash -n "$temp_script" 2>/dev/null; then
        echo "❌ 新脚本语法错误"
        rm -f "$temp_script"
        return 1
    fi
    echo "✅ 脚本验证通过"
    
    # 替换脚本
    echo "🔄 替换脚本文件..."
    if ! cp "$temp_script" "$current_script"; then
        echo "❌ 脚本替换失败"
        # 尝试恢复备份
        cp "$backup_script" "$current_script" 2>/dev/null || true
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
    echo "   - 备份文件: $backup_script"
    echo ""
    echo "💡 提示："
    echo "   - 更新已完成，建议重新运行脚本"
    echo "   - 如有问题可使用备份文件恢复"
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
    echo "   • 所有FTP用户和目录"
    echo "   • vsftpd服务配置"
    echo "   • 目录映射"
    echo ""
    echo "💡 保留的内容："
    echo "   • 源目录数据（录播文件安全）"
    echo "   • vsftpd软件包"
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
    for user_home in /home/*/ftp; do
        if [[ -d "$user_home" ]]; then
            local username=$(basename $(dirname "$user_home"))
            
            # 卸载映射
            if mountpoint -q "$user_home"; then
                umount "$user_home" 2>/dev/null || true
                sed -i "\|$user_home|d" /etc/fstab 2>/dev/null || true
            fi
            
            # 删除用户
            userdel -r "$username" 2>/dev/null || true
            log_info "已删除用户: $username"
        fi
    done
    
    # 恢复配置
    log_info "恢复配置文件..."
    local latest_backup=$(ls /etc/vsftpd.conf.backup.* 2>/dev/null | tail -1)
    if [[ -f "$latest_backup" ]]; then
        cp "$latest_backup" /etc/vsftpd.conf
        log_info "已恢复配置: $latest_backup"
    fi
    
    echo ""
    echo "✅ 卸载完成！"
    echo ""
    echo "💡 提示："
    echo "   • 源目录数据已保留"
    echo "   • 如需重新安装，请重新运行此脚本"
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
        echo "💡 轻量版特性: 只读映射 + 零资源消耗 + 完全兼容录播姬"
        echo ""
        echo "请选择操作："
        echo "1) 🚀 安装/配置FTP服务 (只读映射)"
        echo "2) 📊 查看服务状态"
        echo "3) ▶️ 启动FTP服务"
        echo "4) ⏹️ 停止FTP服务"
        echo "5) 🔄 重启FTP服务"
        echo "6) 👥 用户管理 (添加/删除/改密码)"
        echo "7) 🔧 修复FTP权限问题 (解决550错误)"
        echo "8) 🔄 在线更新脚本"
        echo "9) 🗑️ 卸载FTP服务"
        echo "0) 🚪 退出"
        echo ""
        echo "📝 快捷键： Ctrl+C 快速退出"
        echo ""
        read -p "请输入选项 (0-9): " choice
        
        case $choice in
            1) install_ftp_lite ;;
            2) show_status ;;
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
            6) manage_users ;;
            7) fix_ftp_permissions ;;
            8) update_script ;;
            9) uninstall_service ;;
            0) 
                echo ""
                echo "👋 感谢使用 $SCRIPT_NAME！"
                exit 0
                ;;
            *) 
                echo ""
                echo "❌ 无效选项！请输入 0-9 之间的数字"
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
    
    # 显示欢迎信息
    echo "======================================================"
    echo "🚀 欢迎使用 $SCRIPT_NAME $SCRIPT_VERSION"
    echo "======================================================"
    echo ""
    echo "💡 轻量版专为录播姬用户设计："
    echo "   • 🔗 只读bind mount映射技术"
    echo "   • 🚀 零延迟文件访问"
    echo "   • 🛡️ 完全兼容录播姬，无任何干扰"
    echo "   • 💾 零系统资源消耗"
    echo ""
    echo "📖 与完整版对比："
    echo "   • ❌ 无实时同步服务（避免录播干扰）"
    echo "   • ✅ 保留核心FTP功能"
    echo "   • ✅ 简单易用，一键部署"
    echo ""
    
    read -p "按回车键进入主菜单..." -r
    
    # 进入主菜单
    main_menu
}

# 启动程序
main "$@"
