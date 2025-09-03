#!/bin/bash

# BRCE FTP 精简版配置脚本
# 版本: v1.1.0 - 文件映射版本
# 专为录播姬设计的轻量级FTP服务，使用bind mount映射

# 部分严格模式 - 避免交互过程中意外退出
set -o pipefail

# 全局配置
readonly SCRIPT_VERSION="v1.2.6"
readonly LOG_FILE="/var/log/brce_ftp_lite.log"
SOURCE_DIR="/opt/brec/file"
FTP_USER=""
FTP_PASSWORD=""

# 日志函数
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*" | tee -a "$LOG_FILE"
}

# 初始化脚本
init_script() {
    # 创建日志目录
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # 检查root权限
    if [[ $EUID -ne 0 ]]; then
        echo "❌ 此脚本需要root权限运行"
        echo "💡 请使用: sudo $0"
        exit 1
    fi
    
    log_info "BRCE FTP 精简版脚本启动 - 版本: $SCRIPT_VERSION"
}

# 验证用户名格式
validate_username_format() {
    local username="$1"
    
    # 检查长度
    if [[ ${#username} -lt 3 || ${#username} -gt 16 ]]; then
        return 1
    fi
    
    # 检查格式：以字母开头，可包含字母、数字、下划线、连字符
    if [[ ! "$username" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
        return 1
    fi
    
    return 0
}

# 获取FTP用户名
get_ftp_username() {
    echo ""
    echo "======================================================"
    echo "👤 配置FTP用户名"
    echo "======================================================"
    echo ""
    echo "默认用户名: sunny"
    read -p "请输入FTP用户名（回车使用默认）: " input_user
    
    if [[ -z "$input_user" ]]; then
        FTP_USER="sunny"
    else
        if validate_username_format "$input_user"; then
            FTP_USER="$input_user"
        else
            echo "❌ 用户名格式不正确"
            echo "💡 格式要求: 以字母开头，可包含字母、数字、下划线、连字符，长度3-16位"
            return 1
        fi
    fi
    
    echo "✅ 用户名设置: $FTP_USER"
    return 0
}

# 检查源目录
check_source_directory() {
    echo ""
    echo "======================================================"
    echo "📁 检查源目录"
    echo "======================================================"
    echo ""
    echo "源目录: $SOURCE_DIR"
    
    if [[ ! -d "$SOURCE_DIR" ]]; then
        echo "⚠️  源目录不存在，正在创建..."
        if mkdir -p "$SOURCE_DIR"; then
            echo "✅ 源目录创建成功"
            log_info "创建源目录: $SOURCE_DIR"
        else
            echo "❌ 源目录创建失败"
            log_error "无法创建源目录: $SOURCE_DIR"
            return 1
        fi
    else
        echo "✅ 源目录已存在"
    fi
    
    # 安全权限配置
    echo "🔒 配置安全权限..."
    
    # 确保 /opt 目录有正确的执行权限
    if [[ "$SOURCE_DIR" == /opt/* ]]; then
        echo "   • 设置 /opt 目录权限..."
        chmod o+x /opt 2>/dev/null || true
        
        # 设置路径中所有父目录的执行权限
        local parent_dir=$(dirname "$SOURCE_DIR")
        while [[ "$parent_dir" != "/" && "$parent_dir" != "/opt" ]]; do
            chmod o+x "$parent_dir" 2>/dev/null || true
            parent_dir=$(dirname "$parent_dir")
        done
    fi
    
    # 设置源目录权限 - 只读访问
    chmod 755 "$SOURCE_DIR"
    echo "   • 源目录权限: 755 (只读访问)"
    
    # 设置目录内容权限 - 只读模式
    find "$SOURCE_DIR" -type d -exec chmod 755 {} \; 2>/dev/null || true
    find "$SOURCE_DIR" -type f -exec chmod 444 {} \; 2>/dev/null || true
    echo "   • 文件权限: 444 (只读模式，保护录播文件)"
    
    echo "✅ 安全权限配置完成"
    log_info "源目录权限配置完成: $SOURCE_DIR"
    return 0
}

# 检查端口可用性
check_port_availability() {
    local port="$1"
    local service_name="$2"
    
    echo "🔍 检查端口 $port 可用性..."
    
    # 检查端口是否被占用
    if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
        echo "❌ 端口 $port 已被占用"
        echo "💡 占用进程信息："
        netstat -tlnp 2>/dev/null | grep ":$port " | head -3
        echo ""
        echo "🔧 解决方案："
        echo "   1) 停止占用端口的服务"
        echo "   2) 修改FTP端口配置"
        echo "   3) 使用其他端口"
        echo ""
        read -p "是否继续安装？(y/n，默认 n): " continue_install
        continue_install=${continue_install:-n}
        
        if [[ "$continue_install" != "y" ]]; then
            echo "❌ 安装已取消"
            return 1
        fi
    else
        echo "✅ 端口 $port 可用"
    fi
    
    # 检查防火墙状态
    if command -v ufw &> /dev/null; then
        if ufw status | grep -q "Status: active"; then
            echo "⚠️  检测到防火墙已启用"
            echo "💡 建议开放FTP端口："
            echo "   sudo ufw allow 21/tcp"
            echo "   sudo ufw allow 40000:40100/tcp"
            echo ""
            read -p "是否自动开放FTP端口？(y/n，默认 y): " open_ports
            open_ports=${open_ports:-y}
            
            if [[ "$open_ports" == "y" ]]; then
                echo "🔓 开放FTP端口..."
                ufw allow 21/tcp 2>/dev/null || true
                ufw allow 40000:40100/tcp 2>/dev/null || true
                echo "✅ FTP端口已开放"
            fi
        fi
    fi
    
    return 0
}

# 安装依赖包
install_dependencies() {
    echo ""
    echo "======================================================"
    echo "📦 安装依赖包"
    echo "======================================================"
    echo ""
    
    # 检查端口可用性
    if ! check_port_availability "21" "FTP"; then
        return 1
    fi
    
    log_info "检测包管理器并安装vsftpd..."
    
    if command -v apt-get &> /dev/null; then
        echo "🔍 检测到 apt-get 包管理器"
        apt-get update -qq
        apt-get install -y vsftpd
    elif command -v yum &> /dev/null; then
        echo "🔍 检测到 yum 包管理器"
        yum install -y vsftpd
    elif command -v dnf &> /dev/null; then
        echo "🔍 检测到 dnf 包管理器"
        dnf install -y vsftpd
    else
        echo "❌ 不支持的包管理器"
        echo "💡 请手动安装: vsftpd"
        return 1
    fi
    
    echo "✅ vsftpd 安装完成"
    log_info "vsftpd 安装成功"
    return 0
}

# 创建FTP用户
create_ftp_user() {
    echo ""
    echo "======================================================"
    echo "👤 创建FTP用户"
    echo "======================================================"
    echo ""
    
    # 检查用户是否已存在
    if id "$FTP_USER" &>/dev/null; then
        echo "⚠️  用户 $FTP_USER 已存在，将重置密码"
        log_warn "用户已存在: $FTP_USER"
    else
        echo "🔨 创建新用户: $FTP_USER"
        if useradd -m -s /bin/bash "$FTP_USER"; then
            echo "✅ 用户创建成功"
            log_info "创建用户: $FTP_USER"
        else
            echo "❌ 用户创建失败"
            log_error "无法创建用户: $FTP_USER"
            return 1
        fi
    fi
    
    # 生成密码
    local ftp_password
    read -p "自动生成密码？(y/n，默认 y): " auto_pwd
    auto_pwd=${auto_pwd:-y}
    
    if [[ "$auto_pwd" == "y" ]]; then
        ftp_password=$(openssl rand -base64 12 | tr -d "=+/" | cut -c1-12)
        echo "✅ 密码已自动生成"
        log_info "自动生成密码"
    else
        local max_attempts=3
        local attempt=1
        
        while [[ $attempt -le $max_attempts ]]; do
            echo "密码要求：至少8位字符 (尝试 $attempt/$max_attempts)"
            read -s -p "FTP密码: " ftp_password
            echo
            
            if [[ ${#ftp_password} -ge 8 ]]; then
                read -s -p "再次输入密码确认: " ftp_password_confirm
                echo
                
                if [[ "$ftp_password" == "$ftp_password_confirm" ]]; then
                    break
                else
                    echo "❌ 两次输入的密码不一致"
                fi
            else
                echo "❌ 密码至少8位字符"
            fi
            
            ((attempt++))
            if [[ $attempt -le $max_attempts ]]; then
                echo "请重试..."
                sleep 1
            fi
        done
        
        if [[ $attempt -gt $max_attempts ]]; then
            echo "❌ 密码设置失败，已达到最大尝试次数"
            return 1
        fi
    fi
    
    # 设置密码
    if echo "$FTP_USER:$ftp_password" | chpasswd; then
        echo "✅ 密码设置成功"
        log_info "用户密码设置成功"
    else
        echo "❌ 密码设置失败"
        log_error "无法设置用户密码"
        return 1
    fi
    
    # 保存密码信息
    echo ""
    echo "🎉 ======================================================"
    echo "✅ FTP用户创建成功！"
    echo "======================================================"
    echo ""
    echo "📝 连接信息："
    echo "   👤 用户名: $FTP_USER"
    echo "   🔑 密码: $ftp_password"
    echo "   📁 目录: $SOURCE_DIR"
    echo "   🌐 端口: 21"
    echo "======================================================"
    echo ""
    
    # 保存密码到全局变量用于显示
    FTP_PASSWORD="$ftp_password"
    
    return 0
}

# 安全验证函数
verify_security_permissions() {
    local ftp_home="/home/$FTP_USER/ftp"
    
    echo "🔍 验证安全权限配置..."
    
    # 检查源目录权限
    local source_perms=$(stat -c %a "$SOURCE_DIR" 2>/dev/null)
    if [[ "$source_perms" == "755" ]]; then
        echo "   ✅ 源目录权限正确: $source_perms"
    else
        echo "   ⚠️  源目录权限异常: $source_perms (期望: 755)"
    fi
    
    # 检查文件权限（应该是只读）
    local test_file=$(find "$SOURCE_DIR" -type f -name "*.flv" -o -name "*.mp4" 2>/dev/null | head -1)
    if [[ -n "$test_file" ]]; then
        local file_perms=$(stat -c %a "$test_file" 2>/dev/null)
        if [[ "$file_perms" == "444" ]]; then
            echo "   ✅ 文件权限正确: $file_perms (只读模式)"
        else
            echo "   ⚠️  文件权限: $file_perms (期望: 444 只读)"
        fi
    fi
    
    # 检查FTP用户目录权限
    local ftp_perms=$(stat -c %a "$ftp_home" 2>/dev/null)
    if [[ "$ftp_perms" == "755" ]]; then
        echo "   ✅ FTP目录权限正确: $ftp_perms"
    else
        echo "   ⚠️  FTP目录权限异常: $ftp_perms (期望: 755)"
    fi
    
    # 检查挂载状态（只读模式）
    if mountpoint -q "$ftp_home" 2>/dev/null; then
        echo "   ✅ 只读文件映射正常"
        # 检查是否为只读挂载
        if mount | grep "$ftp_home" | tail -1 | grep -q "(ro,"; then
            echo "   ✅ 确认只读模式挂载"
        else
            echo "   ⚠️  挂载模式需要检查"
        fi
    else
        echo "   ❌ 文件映射异常"
        return 1
    fi
    
    # 检查目录遍历保护
    local test_path="$ftp_home/../"
    if [[ -d "$test_path" ]]; then
        local parent_perms=$(stat -c %a "$test_path" 2>/dev/null)
        if [[ "$parent_perms" == "755" ]]; then
            echo "   ✅ 父目录权限安全: $parent_perms"
        else
            echo "   ⚠️  父目录权限: $parent_perms"
        fi
    fi
    
    echo "✅ 安全权限验证完成"
    return 0
}

# 配置文件映射
setup_bind_mount() {
    echo ""
    echo "======================================================"
    echo "🔗 配置文件映射"
    echo "======================================================"
    echo ""
    
    local ftp_home="/home/$FTP_USER/ftp"
    
    # 创建FTP用户目录
    mkdir -p "$ftp_home"
    chown "$FTP_USER:$FTP_USER" "$ftp_home"
    chmod 755 "$ftp_home"
    
    # 卸载旧挂载（如果存在）
    if mountpoint -q "$ftp_home" 2>/dev/null; then
        echo "📤 卸载旧挂载..."
        umount "$ftp_home" 2>/dev/null || true
    fi
    
    # 创建只读bind mount
    echo "🔗 创建只读文件映射..."
    if mount --bind -o ro "$SOURCE_DIR" "$ftp_home"; then
        echo "✅ 只读文件映射创建成功"
        echo "   • 保护录播文件不被修改"
        echo "   • 避免与录播姬的I/O竞争"
        log_info "创建只读bind mount: $SOURCE_DIR -> $ftp_home"
    else
        echo "❌ 只读文件映射创建失败"
        log_error "无法创建只读bind mount"
        return 1
    fi
    
    # 添加到fstab实现开机自动挂载（只读模式）
    echo "💾 配置开机自动挂载（只读模式）..."
    local fstab_entry="$SOURCE_DIR $ftp_home none bind,ro 0 0"
    
    # 检查是否已存在
    if ! grep -q "$ftp_home" /etc/fstab 2>/dev/null; then
        echo "$fstab_entry" >> /etc/fstab
        echo "✅ 开机自动挂载配置完成"
        log_info "添加fstab条目: $fstab_entry"
    else
        echo "✅ 开机自动挂载已配置"
    fi
    
    # 验证安全权限
    verify_security_permissions
    
    return 0
}

# 生成vsftpd配置
generate_vsftpd_config() {
    echo ""
    echo "======================================================"
    echo "⚙️  配置vsftpd"
    echo "======================================================"
    echo ""
    
    local ftp_home="/home/$FTP_USER/ftp"
    
    # 备份原配置
    if [[ -f /etc/vsftpd.conf ]]; then
        cp /etc/vsftpd.conf /etc/vsftpd.conf.backup.$(date +%Y%m%d_%H%M%S)
        echo "✅ 原配置已备份"
    fi
    
    # 生成新配置
    cat > /etc/vsftpd.conf <<EOF
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=YES
chroot_local_user=YES
allow_writeable_chroot=YES
# 允许删除操作
delete_failed_uploads=YES
local_root=$ftp_home
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100
utf8_filesystem=YES
pam_service_name=vsftpd
seccomp_sandbox=NO
xferlog_enable=YES
xferlog_file=/var/log/vsftpd.log
log_ftp_protocol=YES
async_abor_enable=YES
ascii_upload_enable=YES
ascii_download_enable=YES
hide_ids=YES
use_localtime=YES
file_open_mode=0755
local_umask=022
# 禁用缓存，确保实时性
ls_recurse_enable=NO
use_sendfile=NO
# 针对openlist的优化配置
# 保持默认配置，主要优化在openlist端
EOF

    echo "✅ vsftpd配置生成完成"
    log_info "vsftpd配置文件已生成"
    
    # 显示openlist优化建议
    echo ""
    echo "💡 openlist缓存优化建议："
    echo "   1. 在openlist管理界面中设置："
    echo "      • 缓存过期时间: 1-5分钟"
    echo "      • 或设置为: 0.5 (30秒)"
    echo "   2. 避免使用永久缓存 (设置为0)"
    echo "   3. 定期刷新存储列表"
    
    return 0
}

# 启动FTP服务
start_ftp_service() {
    echo ""
    echo "======================================================"
    echo "🚀 启动FTP服务"
    echo "======================================================"
    echo ""
    
    # 重启vsftpd服务
    echo "🔄 启动vsftpd服务..."
    if systemctl restart vsftpd; then
        echo "✅ vsftpd服务启动成功"
        log_info "vsftpd服务启动成功"
    else
        echo "❌ vsftpd服务启动失败"
        log_error "vsftpd服务启动失败"
        return 1
    fi
    
    # 设置开机自启
    echo "🔧 设置开机自启..."
    if systemctl enable vsftpd; then
        echo "✅ 开机自启设置成功"
        log_info "vsftpd开机自启设置成功"
    else
        echo "⚠️  开机自启设置失败"
        log_warn "vsftpd开机自启设置失败"
    fi
    
    return 0
}

# 实时性测试函数
test_realtime_access() {
    echo ""
    echo "======================================================"
    echo "🧪 实时性测试"
    echo "======================================================"
    echo ""
    
    local ftp_home="/home/$FTP_USER/ftp"
    local test_file="$SOURCE_DIR/realtime_test_$(date +%s).txt"
    local test_content="实时测试文件 - $(date '+%Y-%m-%d %H:%M:%S')"
    
    echo "🔬 开始实时性测试..."
    echo "   测试文件: $test_file"
    echo "   映射目录: $ftp_home"
    echo ""
    
    # 创建测试文件
    echo "$test_content" > "$test_file"
    if [[ $? -eq 0 ]]; then
        echo "✅ 测试文件创建成功"
    else
        echo "❌ 测试文件创建失败"
        return 1
    fi
    
    # 等待1秒
    sleep 1
    
    # 检查映射目录中是否立即可见
    local mapped_file="$ftp_home/$(basename "$test_file")"
    if [[ -f "$mapped_file" ]]; then
        echo "✅ 文件立即在映射目录中可见"
        
        # 验证文件内容
        local mapped_content=$(cat "$mapped_file")
        if [[ "$mapped_content" == "$test_content" ]]; then
            echo "✅ 文件内容完全一致"
            echo "✅ 实时性测试通过！"
        else
            echo "❌ 文件内容不一致"
            return 1
        fi
    else
        echo "❌ 文件未在映射目录中可见"
        return 1
    fi
    
    # 清理测试文件
    rm -f "$test_file"
    echo "🧹 测试文件已清理"
    
    echo ""
    echo "🎉 实时性验证结果："
    echo "   ⚡ 延迟: 0秒 (立即可见)"
    echo "   🔄 机制: Bind Mount 文件系统映射"
    echo "   📁 源目录: $SOURCE_DIR"
    echo "   📁 映射目录: $ftp_home"
    echo ""
    
    return 0
}

# 挂载bind mount
mount_bind_mount() {
    local ftp_home="/home/$FTP_USER/ftp"
    
    echo "🔗 挂载bind mount..."
    
    # 检查源目录是否存在
    if [[ ! -d "$SOURCE_DIR" ]]; then
        echo "❌ 源目录不存在: $SOURCE_DIR"
        return 1
    fi
    
    # 检查FTP用户目录是否存在
    if [[ ! -d "$ftp_home" ]]; then
        echo "❌ FTP用户目录不存在: $ftp_home"
        return 1
    fi
    
    # 卸载旧挂载（如果存在）
    if mountpoint -q "$ftp_home" 2>/dev/null; then
        echo "📤 卸载旧挂载..."
        umount "$ftp_home" 2>/dev/null || true
    fi
    
    # 创建只读bind mount
    if mount --bind -o ro "$SOURCE_DIR" "$ftp_home"; then
        echo "✅ bind mount挂载成功"
        log_info "bind mount挂载成功: $SOURCE_DIR -> $ftp_home"
        return 0
    else
        echo "❌ bind mount挂载失败"
        log_error "bind mount挂载失败: $SOURCE_DIR -> $ftp_home"
        return 1
    fi
}

# 验证bind mount状态
verify_bind_mount() {
    local ftp_home="/home/$FTP_USER/ftp"
    
    echo "🔍 验证bind mount状态..."
    
    # 检查挂载点
    if mountpoint -q "$ftp_home" 2>/dev/null; then
        echo "   ✅ 挂载点正常"
        
        # 检查挂载类型
        local mount_info=$(mount | grep "$ftp_home" | tail -1)
        if echo "$mount_info" | grep -q "bind"; then
            echo "   ✅ bind mount类型正确"
        else
            echo "   ⚠️  挂载类型异常"
        fi
        
        # 检查只读模式
        if echo "$mount_info" | grep -q "(ro,"; then
            echo "   ✅ 只读模式正确"
        else
            echo "   ⚠️  未检测到只读模式"
        fi
        
        return 0
    else
        echo "   ❌ 挂载点异常"
        return 1
    fi
}

# 检查服务状态
check_service_status() {
    echo ""
    echo "======================================================"
    echo "📊 检查服务状态"
    echo "======================================================"
    echo ""
    
    # 检查vsftpd状态
    if systemctl is-active --quiet vsftpd; then
        echo "✅ vsftpd服务运行正常"
    else
        echo "❌ vsftpd服务未运行"
        return 1
    fi
    
    # 检查端口监听
    local port_listening=false
    
    # 方法1: 使用netstat检查
    if netstat -tlnp 2>/dev/null | grep -q ":21 "; then
        port_listening=true
    fi
    
    # 方法2: 使用lsof检查
    if lsof -i :21 2>/dev/null | grep -q "LISTEN"; then
        port_listening=true
    fi
    
    # 方法3: 使用ss检查
    if ss -tlnp 2>/dev/null | grep -q ":21 "; then
        port_listening=true
    fi
    
    if [[ "$port_listening" == "true" ]]; then
        echo "✅ FTP端口21监听正常"
    else
        echo "❌ FTP端口21未监听"
        echo "💡 详细检查："
        echo "   netstat结果: $(netstat -tlnp 2>/dev/null | grep :21 || echo '无')"
        echo "   lsof结果: $(lsof -i :21 2>/dev/null || echo '无')"
        echo "   ss结果: $(ss -tlnp 2>/dev/null | grep :21 || echo '无')"
        return 1
    fi
    
    # 自动检测FTP用户
    if [[ -z "$FTP_USER" ]]; then
        echo "🔍 自动检测FTP用户..."
        for user in $(getent passwd | cut -d: -f1); do
            if [[ -d "/home/$user/ftp" ]]; then
                FTP_USER="$user"
                echo "✅ 检测到FTP用户: $FTP_USER"
                break
            fi
        done
        
        if [[ -z "$FTP_USER" ]]; then
            echo "❌ 未检测到FTP用户"
            echo "💡 请先安装FTP服务"
            return 1
        fi
    fi
    
    # 检查文件映射
    local ftp_home="/home/$FTP_USER/ftp"
    if mountpoint -q "$ftp_home" 2>/dev/null; then
        echo "✅ 文件映射正常"
        
        # 验证bind mount状态
        verify_bind_mount
    else
        echo "❌ 文件映射异常"
        echo "💡 尝试重新挂载..."
        
        if mount_bind_mount; then
            echo "✅ 文件映射已修复"
        else
            echo "❌ 文件映射修复失败"
            return 1
        fi
    fi
    
    # 实时性测试
    echo ""
    read -p "是否进行实时性测试？(y/n，默认 y): " test_realtime
    test_realtime=${test_realtime:-y}
    
    if [[ "$test_realtime" == "y" ]]; then
        test_realtime_access
    fi
    
    echo ""
    echo "🎉 ======================================================"
    echo "✅ BRCE FTP 精简版安装完成！"
    echo "======================================================"
    echo ""
    echo "📝 连接信息："
    echo "   🌐 服务器: $(hostname -I | awk '{print $1}')"
    echo "   👤 用户名: $FTP_USER"
    if [[ -n "$FTP_PASSWORD" ]]; then
        echo "   🔑 密码: $FTP_PASSWORD"
    else
        echo "   🔑 密码: [已设置]"
    fi
    echo "   📁 目录: $SOURCE_DIR"
    echo "   🌐 端口: 21"
    echo "   🔌 被动端口: 40000-40100"
    echo ""
    echo "💡 使用说明："
    echo "   • 将录播文件放入 $SOURCE_DIR 目录"
    echo "   • 通过FTP客户端连接即可访问文件"
    echo "   • ⚡ 文件映射实时生效，零延迟访问"
    echo "   • 🔄 无需同步，基于内核级bind mount"
    echo "======================================================"
    echo ""
    
    return 0
}

# 用户管理菜单
user_management_menu() {
    while true; do
        clear
        echo "======================================================"
        echo "👥 FTP用户管理"
        echo "======================================================"
        echo ""
        echo "请选择操作："
        echo "1) 📄 查看FTP用户"
        echo "2) 🔑 更改用户密码"
        echo "3) ➕ 添加新用户"
        echo "4) 🗑️ 删除用户"
        echo "0) ⬅️ 返回主菜单"
        echo ""
        read -p "请输入选项 (0-4): " user_choice
        
        case $user_choice in
            1)
                list_ftp_users
                read -p "按回车键返回菜单..." -r
                ;;
            2)
                change_ftp_password
                read -p "按回车键返回菜单..." -r
                ;;
            3)
                add_ftp_user
                read -p "按回车键返回菜单..." -r
                ;;
            4)
                delete_ftp_user
                read -p "按回车键返回菜单..." -r
                ;;
            0)
                break
                ;;
            *)
                echo "❌ 无效选项，请重新选择"
                sleep 1
                ;;
        esac
    done
}

# 列出FTP用户
list_ftp_users() {
    echo ""
    echo "======================================================"
    echo "📄 FTP用户列表"
    echo "======================================================"
    echo ""
    
    local found_users=false
    
    # 查找所有可能的FTP用户
    for user in $(getent passwd | cut -d: -f1); do
        if [[ -d "/home/$user/ftp" ]]; then
            if [[ "$found_users" == false ]]; then
                found_users=true
                echo "👥 当前FTP用户："
                echo ""
            fi
            
            echo "   👤 用户名: $user"
            echo "   📁 FTP目录: /home/$user/ftp"
            
            # 检查挂载状态
            if mountpoint -q "/home/$user/ftp" 2>/dev/null; then
                echo "   🔗 映射状态: ✅ 正常"
            else
                echo "   🔗 映射状态: ❌ 异常"
            fi
            
            echo "   📅 创建时间: $(stat -c %y "/home/$user" 2>/dev/null | cut -d' ' -f1)"
            echo ""
        fi
    done
    
    if [[ "$found_users" == false ]]; then
        echo "❌ 没有找到FTP用户"
        echo "💡 请先安装FTP服务"
    fi
}

# 更改FTP用户密码
change_ftp_password() {
    echo ""
    echo "======================================================"
    echo "🔑 更改FTP用户密码"
    echo "======================================================"
    echo ""
    
    # 先列出所有用户
    if ! list_ftp_users; then
        echo ""
        echo "❌ 没有FTP用户"
        return 1
    fi
    
    echo "👤 请输入要更改密码的用户名："
    read -p "用户名: " target_user
    
    # 验证用户是否存在
    if ! id "$target_user" &>/dev/null; then
        echo "❌ 用户不存在"
        return 1
    fi
    
    # 检查是否为FTP用户
    if [[ ! -d "/home/$target_user/ftp" ]]; then
        echo "❌ 该用户不是FTP用户"
        return 1
    fi
    
    # 输入新密码
    local new_password
    local confirm_password
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        echo "🔑 设置新密码 (尝试 $attempt/$max_attempts)"
        echo "密码要求：至少8位字符"
        
        read -s -p "新密码: " new_password
        echo
        
        if [[ ${#new_password} -lt 8 ]]; then
            echo "❌ 密码长度不足，至少8位字符"
            ((attempt++))
            continue
        fi
        
        read -s -p "确认密码: " confirm_password
        echo
        
        if [[ "$new_password" == "$confirm_password" ]]; then
            break
        else
            echo "❌ 两次输入的密码不一致"
            ((attempt++))
        fi
        
        if [[ $attempt -le $max_attempts ]]; then
            echo "请重试..."
            sleep 1
        fi
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        echo "❌ 密码设置失败，已达到最大尝试次数"
        return 1
    fi
    
    # 更改密码
    echo "🔄 正在更改密码..."
    
    if echo "$target_user:$new_password" | chpasswd; then
        echo "✅ 密码更改成功"
        echo ""
        echo "📝 新密码信息："
        echo "   👤 用户名: $target_user"
        echo "   🔑 新密码: $new_password"
        echo ""
        log_info "用户 $target_user 的密码已更改"
        return 0
    else
        echo "❌ 密码更改失败"
        return 1
    fi
}

# 添加新FTP用户
add_ftp_user() {
    echo ""
    echo "======================================================"
    echo "➕ 添加新FTP用户"
    echo "======================================================"
    echo ""
    
    # 获取用户名
    local new_username
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        echo "👤 输入新用户名 (尝试 $attempt/$max_attempts)"
        echo "格式要求: 以字母开头，可包含字母、数字、下划线、连字符，长度3-16位"
        
        read -p "新用户名: " new_username
        
        # 验证用户名格式
        if ! validate_username_format "$new_username"; then
            echo "❌ 用户名格式不正确"
            ((attempt++))
            continue
        fi
        
        # 检查用户是否已存在
        if id "$new_username" &>/dev/null; then
            echo "❌ 用户已存在"
            ((attempt++))
            continue
        fi
        
        # 用户名通过验证
        break
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        echo "❌ 用户名设置失败，已达到最大尝试次数"
        return 1
    fi
    
    # 获取密码
    local user_password
    echo ""
    read -p "自动生成密码？(y/n，默认 y): " auto_pwd
    auto_pwd=${auto_pwd:-y}
    
    if [[ "$auto_pwd" == "y" ]]; then
        user_password=$(openssl rand -base64 12 | tr -d "=+/" | cut -c1-12)
        echo "✅ 已自动生成安全密码"
    else
        local confirm_password
        attempt=1
        
        while [[ $attempt -le $max_attempts ]]; do
            echo "密码要求：至少8位字符 (尝试 $attempt/$max_attempts)"
            read -s -p "请输入密码: " user_password
            echo
            
            if [[ ${#user_password} -lt 8 ]]; then
                echo "❌ 密码长度不足，至少8位字符"
                ((attempt++))
                continue
            fi
            
            read -s -p "确认密码: " confirm_password
            echo
            
            if [[ "$user_password" == "$confirm_password" ]]; then
                break
            else
                echo "❌ 两次输入的密码不一致"
                ((attempt++))
            fi
            
            if [[ $attempt -le $max_attempts ]]; then
                echo "请重试..."
                sleep 1
            fi
        done
        
        if [[ $attempt -gt $max_attempts ]]; then
            echo "❌ 密码设置失败，已达到最大尝试次数"
            return 1
        fi
    fi
    
    # 创建用户
    echo "🔨 正在创建用户..."
    
    # 创建系统用户
    if ! useradd -m -s /bin/bash "$new_username"; then
        echo "❌ 创建系统用户失败"
        return 1
    fi
    
    # 设置密码
    if ! echo "$new_username:$user_password" | chpasswd; then
        echo "❌ 设置密码失败"
        userdel -r "$new_username" 2>/dev/null || true
        return 1
    fi
    
    # 创建FTP目录和映射
    local ftp_home="/home/$new_username/ftp"
    mkdir -p "$ftp_home"
    chown "$new_username:$new_username" "$ftp_home"
    chmod 755 "$ftp_home"
    
    # 创建bind mount
    if mount --bind -o ro "$SOURCE_DIR" "$ftp_home"; then
        echo "✅ 文件映射创建成功"
    else
        echo "❌ 文件映射创建失败"
        userdel -r "$new_username" 2>/dev/null || true
        return 1
    fi
    
    # 添加到fstab
    local fstab_entry="$SOURCE_DIR $ftp_home none bind,ro 0 0"
    if ! grep -q "$ftp_home" /etc/fstab 2>/dev/null; then
        echo "$fstab_entry" >> /etc/fstab
    fi
    
    echo "✅ 用户创建成功"
    echo ""
    echo "📝 新用户信息："
    echo "   👤 用户名: $new_username"
    echo "   🔑 密码: $user_password"
    echo "   📁 目录: $SOURCE_DIR"
    echo ""
    
    log_info "创建新FTP用户: $new_username"
    return 0
}

# 删除FTP用户
delete_ftp_user() {
    echo ""
    echo "======================================================"
    echo "🗑️ 删除FTP用户"
    echo "======================================================"
    echo ""
    
    # 先列出所有用户
    if ! list_ftp_users; then
        echo ""
        echo "❌ 没有FTP用户"
        return 1
    fi
    
    echo "👤 请输入要删除的用户名："
    read -p "用户名: " target_user
    
    # 验证用户是否存在
    if ! id "$target_user" &>/dev/null; then
        echo "❌ 用户不存在"
        return 1
    fi
    
    # 检查是否为FTP用户
    if [[ ! -d "/home/$target_user/ftp" ]]; then
        echo "❌ 该用户不是FTP用户"
        return 1
    fi
    
    # 确认删除
    echo ""
    echo "⚠️  警告：删除用户将同时删除其所有数据！"
    echo "   用户名: $target_user"
    echo "   目录: /home/$target_user"
    echo ""
    read -p "确认删除？(y/N): " confirm_delete
    
    if [[ "$confirm_delete" != "y" && "$confirm_delete" != "Y" ]]; then
        echo "❌ 取消删除"
        return 0
    fi
    
    # 卸载文件映射
    local ftp_home="/home/$target_user/ftp"
    if mountpoint -q "$ftp_home" 2>/dev/null; then
        echo "📤 卸载文件映射..."
        umount "$ftp_home" 2>/dev/null || true
    fi
    
    # 从fstab中移除
    sed -i "\|$ftp_home|d" /etc/fstab 2>/dev/null || true
    
    # 删除用户
    echo "🗑️ 删除用户..."
    if userdel -r "$target_user" 2>/dev/null; then
        echo "✅ 用户删除成功"
        log_info "删除FTP用户: $target_user"
        return 0
    else
        echo "❌ 用户删除失败"
        return 1
    fi
}

# 卸载FTP服务
uninstall_ftp_service() {
    echo ""
    echo "======================================================"
    echo "🗑️ 卸载FTP服务"
    echo "======================================================"
    echo ""
    
    echo "⚠️  警告：此操作将删除所有FTP用户和相关配置！"
    echo ""
    read -p "确认卸载？(y/N): " confirm_uninstall
    
    if [[ "$confirm_uninstall" != "y" && "$confirm_uninstall" != "Y" ]]; then
        echo "❌ 取消卸载"
        return 0
    fi
    
    # 停止服务
    echo "⏹️ 停止FTP服务..."
    systemctl stop vsftpd 2>/dev/null || true
    systemctl disable vsftpd 2>/dev/null || true
    
    # 删除所有FTP用户
    echo "🗑️ 删除FTP用户..."
    for user in $(getent passwd | cut -d: -f1); do
        if [[ -d "/home/$user/ftp" ]]; then
            # 卸载文件映射
            if mountpoint -q "/home/$user/ftp" 2>/dev/null; then
                umount "/home/$user/ftp" 2>/dev/null || true
            fi
            
            # 删除用户
            userdel -r "$user" 2>/dev/null || true
            echo "   ✅ 删除用户: $user"
        fi
    done
    
    # 清理fstab
    echo "🧹 清理配置文件..."
    sed -i '/ftp.*bind/d' /etc/fstab 2>/dev/null || true
    
    # 恢复vsftpd配置
    local latest_backup=$(ls /etc/vsftpd.conf.backup.* 2>/dev/null | tail -1)
    if [[ -f "$latest_backup" ]]; then
        cp "$latest_backup" /etc/vsftpd.conf 2>/dev/null || true
        echo "   ✅ 恢复vsftpd配置"
    fi
    
    echo "✅ FTP服务卸载完成"
    log_info "FTP服务已卸载"
    return 0
}

# 挂载文件映射菜单
mount_bind_mount_menu() {
    echo ""
    echo "======================================================"
    echo "🔗 挂载文件映射"
    echo "======================================================"
    echo ""
    
    # 自动检测FTP用户
    if [[ -z "$FTP_USER" ]]; then
        echo "🔍 自动检测FTP用户..."
        for user in $(getent passwd | cut -d: -f1); do
            if [[ -d "/home/$user/ftp" ]]; then
                FTP_USER="$user"
                echo "✅ 检测到FTP用户: $FTP_USER"
                break
            fi
        done
        
        if [[ -z "$FTP_USER" ]]; then
            echo "❌ 未检测到FTP用户"
            echo "💡 请先安装FTP服务"
            return 1
        fi
    fi
    
    local ftp_home="/home/$FTP_USER/ftp"
    
    echo "📋 当前状态："
    echo "   源目录: $SOURCE_DIR"
    echo "   映射目录: $ftp_home"
    echo "   用户: $FTP_USER"
    echo ""
    
    # 检查源目录
    if [[ ! -d "$SOURCE_DIR" ]]; then
        echo "❌ 源目录不存在: $SOURCE_DIR"
        echo "💡 请先创建源目录"
        return 1
    fi
    
    # 检查FTP用户目录
    if [[ ! -d "$ftp_home" ]]; then
        echo "❌ FTP用户目录不存在: $ftp_home"
        echo "💡 请先安装FTP服务"
        return 1
    fi
    
    # 检查当前挂载状态
    if mountpoint -q "$ftp_home" 2>/dev/null; then
        echo "✅ 当前已挂载"
        echo ""
        echo "请选择操作："
        echo "1) 🔄 重新挂载"
        echo "2) 📤 卸载挂载"
        echo "3) 🔍 验证挂载状态"
        echo "0) ⬅️ 返回主菜单"
        echo ""
        read -p "请输入选项 (0-3): " mount_choice
        
        case $mount_choice in
            1)
                echo "🔄 重新挂载..."
                if mount_bind_mount; then
                    echo "✅ 重新挂载成功"
                    verify_bind_mount
                else
                    echo "❌ 重新挂载失败"
                fi
                ;;
            2)
                echo "📤 卸载挂载..."
                if umount "$ftp_home" 2>/dev/null; then
                    echo "✅ 挂载已卸载"
                else
                    echo "❌ 卸载失败"
                fi
                ;;
            3)
                verify_bind_mount
                ;;
            0)
                return 0
                ;;
            *)
                echo "❌ 无效选项"
                ;;
        esac
    else
        echo "❌ 当前未挂载"
        echo ""
        echo "请选择操作："
        echo "1) 🔗 挂载文件映射"
        echo "2) 🔍 检查挂载状态"
        echo "0) ⬅️ 返回主菜单"
        echo ""
        read -p "请输入选项 (0-2): " mount_choice
        
        case $mount_choice in
            1)
                echo "🔗 挂载文件映射..."
                if mount_bind_mount; then
                    echo "✅ 挂载成功"
                    verify_bind_mount
                else
                    echo "❌ 挂载失败"
                fi
                ;;
            2)
                verify_bind_mount
                ;;
            0)
                return 0
                ;;
            *)
                echo "❌ 无效选项"
                ;;
        esac
    fi
    
    return 0
}



# 删除文件功能
delete_file_function() {
    echo ""
    echo "======================================================"
    echo "🗑️ 删除文件功能"
    echo "======================================================"
    echo ""
    
    if [[ ! -d "$SOURCE_DIR" ]]; then
        echo "❌ 源目录不存在: $SOURCE_DIR"
        return 1
    fi
    
    echo "📁 当前目录: $SOURCE_DIR"
    echo ""
    
    # 显示文件列表（排除配置文件）
    echo "📋 文件列表："
    local file_count=0
    while IFS= read -r -d '' file; do
        file_count=$((file_count + 1))
        local file_size=$(du -h "$file" | cut -f1)
        local file_date=$(stat -c %y "$file" | cut -d' ' -f1)
        echo "   $file_count) $(basename "$file") (${file_size}, $file_date)"
    done < <(find "$SOURCE_DIR" -type f ! -name "config*.json" ! -name "*.backup" -print0 2>/dev/null | head -20 -z)
    
    if [[ $file_count -eq 0 ]]; then
        echo "   📭 暂无文件"
        echo ""
        read -p "按回车键返回主菜单..." -r
        return 0
    fi
    
    echo ""
    echo "请选择操作："
    echo "1) 🗑️ 删除指定文件"
    echo "2) 🗑️ 删除3天前的文件"
    echo "3) 🔍 查看文件详情"
    echo "0) ⬅️ 返回主菜单"
    echo ""
    read -p "请输入选项 (0-3): " delete_choice
    
    case $delete_choice in
        1)
            delete_specific_file
            ;;
        2)
            delete_old_files
            ;;
        3)
            show_file_details
            ;;
        0)
            return 0
            ;;
        *)
            echo "❌ 无效选项"
            ;;
    esac
    
    echo ""
    read -p "按回车键返回主菜单..." -r
    return 0
}

# 删除指定文件
delete_specific_file() {
    echo ""
    echo "🗑️ 删除指定文件"
    echo ""
    read -p "请输入要删除的文件名: " filename
    
    if [[ -z "$filename" ]]; then
        echo "❌ 文件名不能为空"
        return 1
    fi
    
    local file_path="$SOURCE_DIR/$filename"
    
    if [[ ! -f "$file_path" ]]; then
        echo "❌ 文件不存在: $filename"
        return 1
    fi
    
    # 检查是否为配置文件
    if [[ "$filename" == config*.json || "$filename" == *.backup ]]; then
        echo "❌ 配置文件受保护，不能删除: $filename"
        echo "💡 受保护的文件类型："
        echo "   • config*.json (配置文件)"
        echo "   • *.backup (备份文件)"
        return 1
    fi
    
    echo "📄 文件信息："
    echo "   名称: $filename"
    echo "   大小: $(du -h "$file_path" | cut -f1)"
    echo "   修改时间: $(stat -c %y "$file_path")"
    echo ""
    
    read -p "确认删除此文件？(y/N): " confirm
    confirm=${confirm:-n}
    
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        if rm "$file_path"; then
            echo "✅ 文件删除成功: $filename"
            log_info "删除文件: $filename"
        else
            echo "❌ 文件删除失败: $filename"
            return 1
        fi
    else
        echo "❌ 已取消删除"
    fi
}

# 删除指定目录
delete_specific_directory() {
    echo ""
    echo "🗑️ 删除指定目录"
    echo ""
    read -p "请输入要删除的目录名: " dirname
    
    if [[ -z "$dirname" ]]; then
        echo "❌ 目录名不能为空"
        return 1
    fi
    
    local dir_path="$SOURCE_DIR/$dirname"
    
    if [[ ! -d "$dir_path" ]]; then
        echo "❌ 目录不存在: $dirname"
        return 1
    fi
    
    echo "📁 目录信息："
    echo "   名称: $dirname"
    echo "   大小: $(du -sh "$dir_path" | cut -f1)"
    echo "   文件数量: $(find "$dir_path" -type f | wc -l)"
    echo ""
    
    read -p "确认删除此目录及其所有内容？(y/N): " confirm
    confirm=${confirm:-n}
    
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        if rm -rf "$dir_path"; then
            echo "✅ 目录删除成功: $dirname"
            log_info "删除目录: $dirname"
        else
            echo "❌ 目录删除失败: $dirname"
            return 1
        fi
    else
        echo "❌ 已取消删除"
    fi
}

# 删除3天前的文件
delete_old_files() {
    echo ""
    echo "🗑️ 删除72小时前的文件"
    echo ""
    
        # 查找72小时前的文件，排除配置文件（4320分钟 = 72小时）
    local old_files=$(find "$SOURCE_DIR" -type f -mmin +4320 ! -name "config*.json" ! -name "*.backup" 2>/dev/null)
    
    if [[ -z "$old_files" ]]; then
        echo "📭 没有找到72小时前的文件"
        return 0
    fi
    
    echo "📋 找到的72小时前文件："
    local file_count=0
    while IFS= read -r file; do
        file_count=$((file_count + 1))
        local file_size=$(du -h "$file" | cut -f1)
        local file_date=$(stat -c %y "$file" | cut -d' ' -f1)
        echo "   $file_count) $(basename "$file") (${file_size}, $file_date)"
    done <<< "$old_files"
    
    echo ""
    echo "📊 统计信息："
    echo "   文件数量: $file_count"
    
    # 计算总大小
    local total_size=$(find "$SOURCE_DIR" -type f -mmin +4320 ! -name "config*.json" ! -name "*.backup" -exec du -ch {} + 2>/dev/null | tail -1 | cut -f1)
    
    echo "   总大小: $total_size"
    echo ""
    
    read -p "确认删除这些文件？(y/N): " confirm
    confirm=${confirm:-n}
    
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        echo "🗑️ 正在删除文件..."
        
        # 使用find命令直接删除
        local deleted_files=$(find "$SOURCE_DIR" -type f -mmin +4320 ! -name "config*.json" ! -name "*.backup" -print -delete 2>/dev/null)
        
        if [[ -n "$deleted_files" ]]; then
            local deleted_count=$(echo "$deleted_files" | wc -l)
            echo "✅ 删除完成！共删除 $deleted_count 个文件"
            echo "📋 已删除的文件："
            echo "$deleted_files" | while read -r file; do
                echo "   • $(basename "$file")"
            done
        else
            echo "❌ 没有文件被删除"
        fi
        log_info "批量删除72小时前文件: $deleted_count 个"
    else
        echo "❌ 已取消删除"
    fi
}

# 显示文件详情
show_file_details() {
    echo ""
    echo "🔍 文件详情"
    echo ""
    read -p "请输入文件名: " filename
    
    if [[ -z "$filename" ]]; then
        echo "❌ 文件名不能为空"
        return 1
    fi
    
    local file_path="$SOURCE_DIR/$filename"
    
    if [[ ! -f "$file_path" ]]; then
        echo "❌ 文件不存在: $filename"
        return 1
    fi
    
    echo "📄 文件详情："
    echo "   名称: $filename"
    echo "   路径: $file_path"
    echo "   大小: $(du -h "$file_path" | cut -f1)"
    echo "   权限: $(stat -c %a "$file_path")"
    echo "   所有者: $(stat -c %U:%G "$file_path")"
    echo "   创建时间: $(stat -c %w "$file_path")"
    echo "   修改时间: $(stat -c %y "$file_path")"
    echo "   访问时间: $(stat -c %x "$file_path")"
}

# 定时任务管理
cron_task_management() {
    echo ""
    echo "======================================================"
    echo "⏰ 定时任务管理"
    echo "======================================================"
    echo ""
    
    echo "请选择操作："
    echo "1) 📅 设置自动清理任务（保留72小时文件）"
    echo "2) 🔍 查看当前定时任务"
    echo "3) 🗑️ 删除定时任务"
    echo "4) 🧪 测试清理功能"
    echo "0) ⬅️ 返回主菜单"
    echo ""
    read -p "请输入选项 (0-4): " cron_choice
    
    case $cron_choice in
        1)
            setup_auto_cleanup_task
            ;;
        2)
            show_cron_tasks
            ;;
        3)
            remove_cron_task
            ;;
        4)
            test_cleanup_function
            ;;
        0)
            return 0
            ;;
        *)
            echo "❌ 无效选项"
            ;;
    esac
    
    echo ""
    read -p "按回车键返回主菜单..." -r
    return 0
}

# 设置自动清理任务
setup_auto_cleanup_task() {
    echo ""
    echo "📅 设置自动清理任务（72小时）"
    echo ""
    
    # 检查cron服务是否安装
    if ! command -v crontab &> /dev/null; then
        echo "❌ 系统未安装cron服务"
        echo ""
        echo "🔧 正在安装cron服务..."
        
        # 检测系统类型并安装cron
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y cron
        elif command -v yum &> /dev/null; then
            yum install -y cronie
        elif command -v dnf &> /dev/null; then
            dnf install -y cronie
        else
            echo "❌ 无法自动安装cron服务，请手动安装："
            echo "   Ubuntu/Debian: apt-get install cron"
            echo "   CentOS/RHEL: yum install cronie"
            echo "   Fedora: dnf install cronie"
            return 1
        fi
        
        # 启动cron服务
        systemctl enable cron 2>/dev/null || systemctl enable crond 2>/dev/null || true
        systemctl start cron 2>/dev/null || systemctl start crond 2>/dev/null || true
        
        echo "✅ cron服务安装完成"
        echo ""
    fi
    
    # 检查是否已存在任务
    if crontab -l 2>/dev/null | grep -q "cleanup_old_files"; then
        echo "⚠️ 已存在自动清理任务"
        echo ""
        read -p "是否重新设置？(y/N): " confirm
        confirm=${confirm:-n}
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "❌ 已取消"
            return 0
        fi
    fi
    
    echo "请选择清理时间："
    echo "1) 每天凌晨2点"
    echo "2) 每天凌晨3点"
    echo "3) 每天凌晨4点"
    echo "4) 自定义时间"
    echo ""
    read -p "请输入选项 (1-4): " time_choice
    
    local cron_time=""
    case $time_choice in
        1)
            cron_time="0 2 * * *"
            ;;
        2)
            cron_time="0 3 * * *"
            ;;
        3)
            cron_time="0 4 * * *"
            ;;
        4)
            echo ""
            echo "请输入自定义时间（格式：分 时 日 月 周）"
            echo "例如：0 2 * * * 表示每天凌晨2点"
            read -p "时间: " cron_time
            ;;
        *)
            echo "❌ 无效选项"
            return 1
            ;;
    esac
    
    # 创建清理脚本
    local cleanup_script="/usr/local/bin/cleanup_old_files.sh"
    cat > "$cleanup_script" <<EOF
#!/bin/bash
# 自动清理3天前的录播文件
# 创建时间: $(date)

SOURCE_DIR="/opt/brec/file"
LOG_FILE="/var/log/cleanup_old_files.log"

# 记录开始时间
echo "\$(date '+%Y-%m-%d %H:%M:%S') - 开始清理任务" >> "\$LOG_FILE"

# 查找并删除72小时前的文件（排除配置文件）
echo "\$(date '+%Y-%m-%d %H:%M:%S') - 开始清理任务" >> "\$LOG_FILE"

# 使用find命令直接删除，4320分钟 = 72小时
find "\$SOURCE_DIR" -type f -mmin +4320 ! -name "config*.json" ! -name "*.backup" -print -delete >> "\$LOG_FILE" 2>&1

echo "\$(date '+%Y-%m-%d %H:%M:%S') - 清理任务完成" >> "\$LOG_FILE"
EOF
    
    chmod +x "$cleanup_script"
    
    # 添加到crontab
    if (crontab -l 2>/dev/null | grep -v "cleanup_old_files"; echo "$cron_time $cleanup_script") | crontab -; then
        echo "✅ 定时任务添加成功"
    else
        echo "❌ 定时任务添加失败"
        return 1
    fi
    
    echo ""
    echo "✅ 自动清理任务设置成功！"
    echo "   清理时间: $cron_time"
    echo "   清理脚本: $cleanup_script"
    echo "   日志文件: /var/log/cleanup_old_files.log"
    echo ""
    echo "💡 任务说明："
    echo "   • 自动删除72小时前的录播文件"
    echo "   • 每天自动执行一次"
    echo "   • 操作记录在日志文件中"
    echo "   • 保护配置文件不被删除"
    
    log_info "设置自动清理任务: $cron_time"
}

# 查看当前定时任务
show_cron_tasks() {
    echo ""
    echo "🔍 当前定时任务"
    echo ""
    
    # 检查cron服务是否可用
    if ! command -v crontab &> /dev/null; then
        echo "❌ cron服务未安装或不可用"
        echo "💡 请先安装cron服务："
        echo "   Ubuntu/Debian: apt-get install cron"
        echo "   CentOS/RHEL: yum install cronie"
        return 1
    fi
    
    local cleanup_tasks=$(crontab -l 2>/dev/null | grep "cleanup_old_files")
    
    if [[ -n "$cleanup_tasks" ]]; then
        echo "📋 自动清理任务："
        while IFS= read -r task; do
            echo "   $task"
        done <<< "$cleanup_tasks"
        echo ""
        
        # 显示日志
        if [[ -f "/var/log/cleanup_old_files.log" ]]; then
            echo "📄 最近日志："
            tail -5 "/var/log/cleanup_old_files.log" | while IFS= read -r line; do
                echo "   $line"
            done
        else
            echo "📄 日志文件: 暂无"
        fi
    else
        echo "📭 暂无自动清理任务"
    fi
}

# 删除定时任务
remove_cron_task() {
    echo ""
    echo "🗑️ 删除定时任务"
    echo ""
    
    # 检查cron服务是否可用
    if ! command -v crontab &> /dev/null; then
        echo "❌ cron服务未安装或不可用"
        echo "💡 请先安装cron服务"
        return 1
    fi
    
    if crontab -l 2>/dev/null | grep -q "cleanup_old_files"; then
        read -p "确认删除自动清理任务？(y/N): " confirm
        confirm=${confirm:-n}
        
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            # 删除crontab中的任务
            crontab -l 2>/dev/null | grep -v "cleanup_old_files" | crontab -
            
            # 删除清理脚本
            rm -f "/usr/local/bin/cleanup_old_files.sh"
            
            echo "✅ 自动清理任务已删除"
            log_info "删除自动清理任务"
        else
            echo "❌ 已取消"
        fi
    else
        echo "📭 没有找到自动清理任务"
    fi
}

# 测试清理功能
test_cleanup_function() {
    echo ""
    echo "🧪 测试清理功能（72小时）"
    echo ""
    
        # 查找72小时前的文件（排除配置文件）（4320分钟 = 72小时）
    local old_files=$(find "$SOURCE_DIR" -type f -mmin +4320 ! -name "config*.json" ! -name "*.backup" 2>/dev/null)
    
    if [[ -z "$old_files" ]]; then
        echo "📭 没有找到72小时前的文件"
        echo "💡 可以创建一些测试文件来验证功能"
        return 0
    fi
    
    echo "📋 找到的72小时前文件："
    local file_count=0
    while IFS= read -r file; do
        file_count=$((file_count + 1))
        local file_size=$(du -h "$file" | cut -f1)
        local file_date=$(stat -c %y "$file" | cut -d' ' -f1)
        echo "   $file_count) $(basename "$file") (${file_size}, $file_date)"
    done <<< "$old_files"
    
    echo ""
    echo "📊 统计信息："
    echo "   文件数量: $file_count"
    
    # 计算总大小
    local total_size=$(find "$SOURCE_DIR" -type f -mmin +4320 ! -name "config*.json" ! -name "*.backup" -exec du -ch {} + 2>/dev/null | tail -1 | cut -f1)
    
    echo "   总大小: $total_size"
    echo ""
    echo "💡 这是测试模式，不会实际删除文件"
    echo "   如需删除，请使用删除文件功能"
    echo "   清理规则：删除72小时前的文件"
}

# 检查脚本更新
check_script_update() {
    echo ""
    echo "======================================================"
    echo "🔄 检查脚本更新"
    echo "======================================================"
    echo ""
    
    local script_name="ftp-setup-lite.sh"
    local github_url="https://raw.githubusercontent.com/Sannylew/bilirec-ftp-sync/main/$script_name"
    local temp_file="/tmp/$script_name.new"
    
    echo "🔍 检查远程版本..."
    
    # 检查网络连接
    if ! curl -s --connect-timeout 10 "$github_url" > /dev/null; then
        echo "❌ 无法连接到GitHub，请检查网络连接"
        return 1
    fi
    
    # 下载远程版本
    if curl -s --connect-timeout 10 "$github_url" -o "$temp_file"; then
        echo "✅ 远程版本下载成功"
    else
        echo "❌ 下载远程版本失败"
        return 1
    fi
    
    # 比较版本
    local remote_version=$(grep "readonly SCRIPT_VERSION=" "$temp_file" 2>/dev/null | cut -d'"' -f2)
    local current_version="$SCRIPT_VERSION"
    
    echo "   当前版本: $current_version"
    echo "   远程版本: $remote_version"
    
    if [[ "$remote_version" == "$current_version" ]]; then
        echo "✅ 已是最新版本"
        rm -f "$temp_file"
        return 0
    fi
    
    # 统计代码行数
    local current_lines=$(wc -l < "$script_name" 2>/dev/null || echo "0")
    local remote_lines=$(wc -l < "$temp_file" 2>/dev/null || echo "0")
    local line_diff=$((remote_lines - current_lines))
    
    echo ""
    echo "🆕 发现新版本: $remote_version"
    echo "📊 代码统计："
    echo "   当前版本行数: $current_lines"
    echo "   远程版本行数: $remote_lines"
    if [[ $line_diff -gt 0 ]]; then
        echo "   新增代码行数: +$line_diff"
    elif [[ $line_diff -lt 0 ]]; then
        echo "   减少代码行数: $line_diff"
    else
        echo "   代码行数无变化"
    fi
    echo ""
    echo "💡 更新内容："
    echo "   • 移除脚本更新备份功能"
    echo "   • 添加代码行数统计对比"
    echo "   • 优化更新信息显示"
    echo ""
    
    read -p "是否更新到最新版本？(y/n，默认 y): " update_confirm
    update_confirm=${update_confirm:-y}
    
    if [[ "$update_confirm" == "y" ]]; then
        echo "🔄 正在更新脚本..."
        
        # 替换脚本
        if cp "$temp_file" "$script_name"; then
            chmod +x "$script_name"
            echo "✅ 脚本更新成功"
            echo ""
            echo "🎉 更新完成！"
            echo "💡 建议重新运行脚本以使用新功能"
            echo ""
            read -p "是否立即重新运行脚本？(y/n，默认 n): " restart_script
            restart_script=${restart_script:-n}
            
            if [[ "$restart_script" == "y" ]]; then
                echo "🔄 重新启动脚本..."
                exec "$0" "$@"
            fi
        else
            echo "❌ 脚本更新失败"
            echo "💡 请手动更新或联系技术支持"
            return 1
        fi
    else
        echo "❌ 更新已取消"
    fi
    
    rm -f "$temp_file"
    return 0
}

# 主菜单
main_menu() {
    while true; do
        clear
        echo "======================================================"
        echo "🚀 BRCE FTP 精简版管理控制台 ${SCRIPT_VERSION}"
        echo "======================================================"
        echo ""
        echo "请选择操作："
        echo "1) 🚀 安装/配置FTP服务 (文件映射版)"
        echo "2) 📊 查看FTP服务状态"
        echo "3) 🔄 重启FTP服务"
        echo "4) ⏹️ 停止FTP服务"
        echo "5) 👥 FTP用户管理"
        echo "6) 🧪 实时性测试"
        echo "7) 🔗 挂载文件映射"
        echo "8) 🗑️ 删除文件功能"
        echo "9) ⏰ 定时任务管理"
        echo "10) 🔄 检查脚本更新"
        echo "11) 🗑️ 卸载FTP服务"
        echo "0) 退出"
        echo ""
        echo "📝 快捷键： Ctrl+C 快速退出"
        echo ""
        read -p "请输入选项 (0-11): " choice
        
        case $choice in
            1)
                install_ftp_service
                read -p "按回车键返回主菜单..." -r
                ;;
            2)
                check_service_status
                read -p "按回车键返回主菜单..." -r
                ;;
            3)
                echo "🔄 重启FTP服务..."
                systemctl restart vsftpd
                echo "✅ 服务重启完成"
                read -p "按回车键返回主菜单..." -r
                ;;
            4)
                echo "⏹️ 停止FTP服务..."
                systemctl stop vsftpd
                echo "✅ 服务已停止"
                read -p "按回车键返回主菜单..." -r
                ;;
            5)
                user_management_menu
                ;;
            6)
                test_realtime_access
                read -p "按回车键返回主菜单..." -r
                ;;
            7)
                mount_bind_mount_menu
                read -p "按回车键返回主菜单..." -r
                ;;
            8)
                delete_file_function
                ;;
            9)
                cron_task_management
                ;;
            10)
                check_script_update
                read -p "按回车键返回主菜单..." -r
                ;;
            11)
                uninstall_ftp_service
                read -p "按回车键返回主菜单..." -r
                ;;
            0)
                echo "👋 再见！"
                exit 0
                ;;
            *)
                echo "❌ 无效选项，请重新选择"
                sleep 1
                ;;
        esac
    done
}

# 安装FTP服务主函数
install_ftp_service() {
    echo ""
    echo "======================================================"
    echo "🚀 开始安装BRCE FTP 精简版"
    echo "======================================================"
    echo ""
    echo "🎯 源目录: $SOURCE_DIR"
    echo "🔥 特性: 文件映射，零延迟访问"
    echo ""
    
    # 确认安装
    read -p "是否继续安装？(y/n，默认 y): " confirm
    confirm=${confirm:-y}
    
    if [[ "$confirm" != "y" ]]; then
        echo "❌ 安装已取消"
        return 1
    fi
    
    # 执行安装步骤
    if ! get_ftp_username; then
        return 1
    fi
    
    if ! check_source_directory; then
        return 1
    fi
    
    if ! install_dependencies; then
        return 1
    fi
    
    if ! create_ftp_user; then
        return 1
    fi
    
    if ! setup_bind_mount; then
        return 1
    fi
    
    if ! generate_vsftpd_config; then
        return 1
    fi
    
    if ! start_ftp_service; then
        return 1
    fi
    
    check_service_status
    return 0
}

# 主程序入口
main() {
    init_script
    
    # 检查脚本更新（可选）
    if [[ "$1" == "--check-update" ]]; then
        check_script_update
        return 0
    fi
    
    # 检查是否已安装
    if systemctl is-active --quiet vsftpd 2>/dev/null; then
        echo "✅ 检测到FTP服务已安装"
        echo "💡 使用菜单选项进行管理"
        echo ""
        sleep 2
    fi
    
    main_menu
}

# 信号处理
trap 'echo ""; echo "👋 程序已退出"; exit 0' INT TERM

# 运行主程序
main "$@"
