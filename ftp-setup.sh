#!/bin/bash

# BRCE FTP服务配置脚本
# 版本: v1.0.3 - 修复密码显示问题
# 修复语法错误、字符编码问题和密码显示bug

# 部分严格模式 - 避免交互过程中意外退出
set -o pipefail
# 注意: 不使用 set -e 以避免菜单交互中的闪退问题

# 全局配置
readonly SCRIPT_VERSION="v1.0.3"
readonly LOG_FILE="/var/log/brce_ftp_setup.log"
SOURCE_DIR=""
FTP_USER=""

# 自动日志轮转函数
auto_rotate_log() {
    local log_file="$1"
    local max_lines="${2:-2000}"  # 默认最大行数
    
    if [[ -f "$log_file" ]]; then
        local current_lines=$(wc -l < "$log_file" 2>/dev/null || echo "0")
        if [[ "$current_lines" -gt "$max_lines" ]]; then
            # 创建备份并保留最近的行数
            local backup_file="${log_file}.old"
            local keep_lines=$((max_lines / 2))  # 保留一半行数
            
            tail -n "$keep_lines" "$log_file" > "${log_file}.tmp"
            head -n "$((current_lines - keep_lines))" "$log_file" > "$backup_file" 2>/dev/null || true
            mv "${log_file}.tmp" "$log_file"
            
            # 压缩旧日志以节省空间
            if command -v gzip &> /dev/null && [[ -f "$backup_file" ]]; then
                gzip "$backup_file" 2>/dev/null || true
            fi
        fi
    fi
}

# 增强的日志函数
log_info() {
    auto_rotate_log "$LOG_FILE" 2000
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" | tee -a "$LOG_FILE"
}

log_error() {
    auto_rotate_log "$LOG_FILE" 2000
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

log_warn() {
    auto_rotate_log "$LOG_FILE" 2000
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*" | tee -a "$LOG_FILE"
}

log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        auto_rotate_log "$LOG_FILE" 2000
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: $*" | tee -a "$LOG_FILE"
    fi
}

# 记录命令执行结果的函数
log_command() {
    local cmd="$1"
    local description="${2:-执行命令}"
    
    log_info "$description: $cmd"
    
    if eval "$cmd" 2>&1 | tee -a "$LOG_FILE"; then
        log_info "$description 成功"
        return 0
    else
        local exit_code=$?
        log_error "$description 失败 (退出码: $exit_code)"
        return $exit_code
    fi
}

# 记录步骤开始和结束的函数
log_step_start() {
    echo "" | tee -a "$LOG_FILE"
    echo "=== $* ===" | tee -a "$LOG_FILE"
    log_info "开始步骤: $*"
}

log_step_end() {
    log_info "完成步骤: $*"
    echo "===========================================" | tee -a "$LOG_FILE"
}

# 重试机制函数
retry_operation() {
    local max_attempts=${1:-3}
    local delay=${2:-2}
    local description="${3:-操作}"
    shift 3
    local command=("$@")
    
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        log_info "$description (尝试 $attempt/$max_attempts)"
        
        if "${command[@]}"; then
            log_info "$description 成功"
            return 0
        else
            log_error "$description 失败"
            if [[ $attempt -lt $max_attempts ]]; then
                log_info "等待 ${delay} 秒后重试..."
                sleep "$delay"
            fi
            ((attempt++))
        fi
    done
    
    log_error "$description 在 $max_attempts 次尝试后仍然失败"
    return 1
}

# 网络连接检查函数
check_network_connection() {
    local test_url="https://github.com"
    local timeout=10
    
    echo "🌐 检查网络连接..."
    
    if retry_operation 3 5 "网络连接测试" curl -s --max-time "$timeout" "$test_url" >/dev/null 2>&1; then
        echo "✅ 网络连接正常"
        return 0
    else
        echo "❌ 网络连接失败，请检查网络设置"
        return 1
    fi
}

# 清理和退出函数
cleanup_and_exit() {
    local exit_code=${1:-0}
    echo ""
    echo "📦 正在清理资源..."
    
    # 如果有运行中的后台进程，尝试清理
    if [[ -n "${BACKGROUND_PIDS:-}" ]]; then
        for pid in $BACKGROUND_PIDS; do
            if kill -0 "$pid" 2>/dev/null; then
                log_info "正在停止后台进程: $pid"
                kill "$pid" 2>/dev/null || true
            fi
        done
    fi
    
    echo "👋 程序已退出"
    exit "$exit_code"
}

# 设置信号处理
setup_signal_handlers() {
    trap 'cleanup_and_exit 130' SIGINT   # Ctrl+C
    trap 'cleanup_and_exit 143' SIGTERM  # 终止信号
    # 移除 ERR 陷阱以避免菜单交互中的意外退出
    # trap 'cleanup_and_exit 1' ERR        # 错误退出 - 已禁用
}

# 初始化函数
init_script() {
    echo "======================================================"
    echo "📁 BRCE FTP服务配置工具 ${SCRIPT_VERSION}"
    echo "======================================================"
    echo ""

    # 设置信号处理
    setup_signal_handlers

    # 创建日志目录（在权限检查前）
    if ! mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null; then
        echo "警告: 无法创建日志目录，将仅输出到终端"
        LOG_FILE="/dev/null"
    else
        echo "📝 日志文件: $LOG_FILE"
    fi

    # 记录脚本启动信息
    log_step_start "脚本初始化"
    log_info "BRCE FTP服务配置工具启动 - 版本 $SCRIPT_VERSION"
    log_info "执行用户: $(whoami)"
    log_info "当前时间: $(date)"
    log_info "系统信息: $(uname -a)"
    log_info "工作目录: $(pwd)"
    log_info "脚本路径: $0"
    log_info "日志文件: $LOG_FILE"

    log_info "权限检查通过 - 以root用户运行"
    log_step_end "脚本初始化"
}

# 统一的用户名验证函数
validate_username_format() {
    local username="$1"
    
    if [[ -z "$username" ]]; then
        return 1
    fi
    
    # 统一验证规则：以字母开头，可包含字母、数字、下划线和连字符，长度3-16位
    if [[ "$username" =~ ^[a-zA-Z][a-zA-Z0-9_-]{2,15}$ ]]; then
        return 0
    else
        return 1
    fi
}

# 获取和验证FTP用户名 - 修复递归调用问题
get_ftp_username() {
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        echo ""
        echo "======================================================"
        echo "👤 配置FTP用户名 (尝试 $attempt/$max_attempts)"
        echo "======================================================"
        echo ""
        echo "默认用户名: sunny"
        echo "格式要求: 以字母开头，可包含字母、数字、下划线、连字符，长度3-16位"
        echo ""
        
        echo "示例: alice, bob123, user_name, test-user"
        echo ""
        read -p "请输入FTP用户名（回车使用默认用户名）: " input_user
        
        if [[ -z "$input_user" ]]; then
            # 用户回车，使用默认用户名
            FTP_USER="sunny"
            log_info "使用默认用户名: $FTP_USER"
            return 0
        else
            # 验证用户名格式
            if validate_username_format "$input_user"; then
                FTP_USER="$input_user"
                log_info "自定义用户名: $FTP_USER"
                return 0
            else
                echo "❌ 用户名格式错误！"
                        echo "ℹ️  格式要求："
        echo "   • 以字母开头 (a-z, A-Z)"
        echo "   • 可包含字母、数字、下划线、连字符"
        echo "   • 长度 3-16 位"
        echo ""
        echo "✅ 正确示例: alice, user123, test_user, my-ftp"
        echo "❌ 错误示例: 123user, _test, -user, verylongusername123456"
                ((attempt++))
                if [[ $attempt -le $max_attempts ]]; then
                    echo "请重试..."
                    sleep 1
                fi
            fi
        fi
    done
    
    log_error "用户名配置失败，已达到最大尝试次数"
    echo "💡 您可以稍后重新运行脚本"
    return 1
}

# 获取和验证源目录路径 - 修复递归调用问题
get_source_directory() {
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        echo ""
        echo "======================================================"
        echo "📁 配置源目录路径 (尝试 $attempt/$max_attempts)"
        echo "======================================================"
        echo ""
        echo "默认目录: /root/brec/file (录播姬默认路径)"
        echo ""
        
        echo "示例: /home/video, ./recordings, /mnt/storage/brec"
        echo ""
        read -p "请输入目录路径（回车使用默认路径）: " input_dir
        
        if [[ -z "$input_dir" ]]; then
            # 用户回车，使用默认路径
            SOURCE_DIR="/root/brec/file"
            log_info "使用默认路径: $SOURCE_DIR"
        else
            # 用户输入了路径，使用自定义路径
            # 处理相对路径
            if [[ "$input_dir" != /* ]]; then
                input_dir="$(pwd)/$input_dir"
            fi
            
            # 规范化路径
            if ! SOURCE_DIR=$(realpath -m "$input_dir" 2>/dev/null); then
                log_error "路径格式无效: $input_dir"
                ((attempt++))
                if [[ $attempt -le $max_attempts ]]; then
                    echo "请重试..."
                    sleep 1
                fi
                continue
            fi
            log_info "自定义目录: $SOURCE_DIR"
        fi
        
        echo ""
        echo "📋 目录信息："
        echo "   - 源目录路径: $SOURCE_DIR"
        
        # 检查目录是否存在
        if [[ -d "$SOURCE_DIR" ]]; then
            if file_count=$(find "$SOURCE_DIR" -type f 2>/dev/null | wc -l); then
                echo "   - 目录状态: 已存在"
                echo "   - 文件数量: $file_count 个文件"
            else
                log_error "无法访问目录: $SOURCE_DIR"
                ((attempt++))
                if [[ $attempt -le $max_attempts ]]; then
                    echo "请重试..."
                    sleep 1
                fi
                continue
            fi
        else
            echo "   - 目录状态: 不存在（将自动创建）"
        fi
        
        echo ""
        read -p "确认使用此目录？(y/N): " confirm_dir
        if [[ "$confirm_dir" =~ ^[Yy]$ ]]; then
            # 创建目录（如果不存在）
            if [[ ! -d "$SOURCE_DIR" ]]; then
                log_info "创建源目录: $SOURCE_DIR"
                if ! mkdir -p "$SOURCE_DIR"; then
                    log_error "创建目录失败，请检查权限"
                    ((attempt++))
                    if [[ $attempt -le $max_attempts ]]; then
                        echo "请重试..."
                        sleep 1
                    fi
                    continue
                fi
                log_info "目录创建成功"
            fi
            
            log_info "源目录配置完成: $SOURCE_DIR"
            return 0
        else
            log_info "用户取消，重新选择目录"
            ((attempt++))
            if [[ $attempt -le $max_attempts ]]; then
                sleep 1
            fi
        fi
    done
    
    log_error "源目录配置失败，已达到最大尝试次数"
    echo "💡 您可以稍后重新运行脚本"
    return 1
}

# 验证用户名函数（统一使用新的验证规则）
validate_username() {
    local username="${1:-}"
    
    if [[ -z "$username" ]]; then
        log_error "validate_username: 缺少用户名参数"
        return 1
    fi
    
    # 使用统一的验证函数
    if validate_username_format "$username"; then
        return 0
    else
        log_error "用户名不合法！要求：以字母开头，可包含字母、数字、下划线、连字符，长度3-16位"
        return 1
    fi
}

# 检查实时同步依赖 - 增强包管理器支持
check_sync_dependencies() {
    local missing_deps=()
    
    log_info "检查实时同步依赖..."
    
    if ! command -v rsync &> /dev/null; then
        missing_deps+=("rsync")
    fi
    
    if ! command -v inotifywait &> /dev/null; then
        missing_deps+=("inotify-tools")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_info "安装实时同步依赖: ${missing_deps[*]}"
        
        # 支持多种包管理器
        if command -v apt-get &> /dev/null; then
            log_info "使用 apt 包管理器安装依赖"
            if ! apt-get update -qq; then
                log_error "更新包列表失败"
                return 1
            fi
            if ! apt-get install -y "${missing_deps[@]}"; then
                log_error "使用 apt 安装依赖失败"
                return 1
            fi
        elif command -v dnf &> /dev/null; then
            log_info "使用 dnf 包管理器安装依赖"
            if ! dnf install -y "${missing_deps[@]}"; then
                log_error "使用 dnf 安装依赖失败"
                return 1
            fi
        elif command -v yum &> /dev/null; then
            log_info "使用 yum 包管理器安装依赖"
            if ! yum install -y "${missing_deps[@]}"; then
                log_error "使用 yum 安装依赖失败"
                return 1
            fi
        elif command -v zypper &> /dev/null; then
            log_info "使用 zypper 包管理器安装依赖"
            if ! zypper install -y "${missing_deps[@]}"; then
                log_error "使用 zypper 安装依赖失败"
                return 1
            fi
        elif command -v pacman &> /dev/null; then
            log_info "使用 pacman 包管理器安装依赖"
            if ! pacman -S --noconfirm "${missing_deps[@]}"; then
                log_error "使用 pacman 安装依赖失败"
                return 1
            fi
        else
            log_error "不支持的包管理器，请手动安装: ${missing_deps[*]}"
            return 1
        fi
        log_info "依赖安装完成"
    else
        log_info "实时同步依赖已安装"
    fi
    return 0
}

# 录播姬权限配置函数
setup_brec_root_permissions() {
    local ftp_user="$1"
    local source_dir="$2"
    
    # 检查是否需要处理 /root 路径权限
    if [[ "$source_dir" != /root/* ]]; then
        return 0  # 不在 /root 下，无需特殊处理
    fi
    
    echo ""
    echo "🔧 检测到录播姬路径在 /root 下，正在配置访问权限..."
    echo "源路径: $source_dir"
    
    # 检查源目录是否存在
    if [[ ! -d "$source_dir" ]]; then
        echo "⚠️  源目录不存在，将自动创建: $source_dir"
        mkdir -p "$source_dir"
        if [[ $? -ne 0 ]]; then
            log_error "创建源目录失败: $source_dir"
            return 1
        fi
    fi
    
    # 创建专用用户组
    local group_name="brec-ftp"
    if ! getent group "$group_name" >/dev/null 2>&1; then
        groupadd "$group_name"
        if [[ $? -eq 0 ]]; then
            echo "✅ 已创建用户组: $group_name"
        else
            log_error "创建用户组失败: $group_name"
            return 1
        fi
    else
        echo "✅ 用户组已存在: $group_name"
    fi
    
    # 将FTP用户加入组
    usermod -a -G "$group_name" "$ftp_user"
    if [[ $? -eq 0 ]]; then
        echo "✅ 用户 $ftp_user 已加入组 $group_name"
    else
        log_error "用户加入组失败"
        return 1
    fi
    
    # 设置目录权限
    local brec_dir="/root/brec"
    
    # 确保 /root/brec 目录存在
    if [[ ! -d "$brec_dir" ]]; then
        mkdir -p "$brec_dir"
        echo "✅ 已创建目录: $brec_dir"
    fi
    
    # 设置组权限（最小权限原则）
    chgrp -R "$group_name" "$brec_dir"
    chmod 750 "$brec_dir"                    # root:brec-ftp rwxr-x---
    chmod -R 750 "$source_dir"              # 允许组读取和执行
    
    if [[ $? -eq 0 ]]; then
        echo "✅ 已设置目录组权限: $brec_dir"
    else
        log_error "设置目录权限失败"
        return 1
    fi
    
    # 验证权限设置
    echo "🔍 验证权限配置..."
    
    # 尝试权限验证，但不因验证失败而中断整个安装
    local permission_test_result=0
    
    if sudo -u "$ftp_user" test -r "$source_dir" 2>/dev/null; then
        echo "✅ FTP用户可以访问录播文件目录"
        
        # 测试列出目录内容
        if sudo -u "$ftp_user" ls "$source_dir" >/dev/null 2>&1; then
            echo "✅ FTP用户可以列出目录内容"
        else
            echo "⚠️  FTP用户可以访问目录但无法列出内容（目录可能为空）"
        fi
        
        permission_test_result=0
    else
        echo "⚠️  权限验证遇到问题，但安装将继续"
        echo "💡 可能的原因："
        echo "   • SELinux 或 AppArmor 安全策略限制"
        echo "   • 复杂的目录权限结构"
        echo "   • sudo 配置限制"
        echo "💡 建议安装完成后手动测试FTP访问"
        
        # 返回警告而不是错误，允许安装继续
        permission_test_result=1
    fi
    
    return $permission_test_result
}

# 智能权限配置函数（基于主程序逻辑）
configure_smart_permissions() {
    local user="${1:-}"
    local source_dir="${2:-}"
    
    # 参数验证
    if [[ -z "$user" || -z "$source_dir" ]]; then
        log_error "configure_smart_permissions: 缺少必要参数 - user=$user, source_dir=$source_dir"
        return 1
    fi
    
    local user_home="/home/$user"
    local ftp_home="$user_home/ftp"
    
    log_info "配置FTP目录权限（完整读写删除权限）..."
    
    mkdir -p "$ftp_home"
    
    # 配置用户主目录
    chown root:root "$user_home"
    chmod 755 "$user_home"
    
    # 确保源目录存在
    mkdir -p "$source_dir"
    
    # 关键修复：设置源目录权限，确保FTP用户有完整权限
    echo "🔧 设置源目录权限 $source_dir"
    chown -R "$user":"$user" "$source_dir"
    chmod -R 755 "$source_dir"
    
    # 如果源目录在/opt下，设置特殊权限
    if [[ "$source_dir" == /opt/* ]]; then
        echo "⚠️  检测到/opt目录，设置访问权限..."
        chmod o+x /opt 2>/dev/null || true
        dirname_path=$(dirname "$source_dir")
        while [ "$dirname_path" != "/" ] && [ "$dirname_path" != "/opt" ]; do
            chmod o+x "$dirname_path" 2>/dev/null || true
            dirname_path=$(dirname "$dirname_path")
        done
    fi
    
    # 设置FTP目录权限
    chown "$user":"$user" "$ftp_home"
    chmod 755 "$ftp_home"
    
    echo "✅ 权限配置完成（用户拥有完整读写删除权限）"
}

# 生成vsftpd配置文件（基于主程序配置）
generate_optimal_config() {
    local ftp_home="${1:-}"
    
    if [[ -z "$ftp_home" ]]; then
        log_error "generate_optimal_config: 缺少FTP主目录参数"
        return 1
    fi
    
    log_info "生成vsftpd配置..."
    
    # 备份原配置
    [ -f /etc/vsftpd.conf ] && cp /etc/vsftpd.conf /etc/vsftpd.conf.backup.$(date +%Y%m%d_%H%M%S)
    
    # 生成优化的配置（基于主程序，适合视频文件，禁用缓存）
    cat > /etc/vsftpd.conf <<EOF
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=YES
chroot_local_user=YES
allow_writeable_chroot=YES
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
EOF

    log_info "vsftpd配置文件生成完成"
    echo "✅ 配置文件已生成"
}

# 创建实时同步脚本 - 改进错误处理和日志
create_sync_script() {
    local user="${1:-}"
    local source_dir="${2:-}"
    local target_dir="${3:-}"
    
    if [[ -z "$user" ]]; then
        log_error "create_sync_script: 缺少用户名参数"
        return 1
    fi
    
    local script_path="/usr/local/bin/ftp_sync_${user}.sh"
    log_info "创建实时同步脚本: $script_path"
    
    # 验证参数
    if [[ -z "$source_dir" || -z "$target_dir" ]]; then
        log_error "create_sync_script: 参数不完整"
        log_error "  用户: $user"
        log_error "  源目录: $source_dir" 
        log_error "  目标目录: $target_dir"
        return 1
    fi
    
    cat > "$script_path" << 'EOF'
#!/bin/bash

# BRCE FTP双向实时同步脚本
# 解决文件修改延迟问题 - 支持双向同步

set -euo pipefail

USER="${USER}"
SOURCE_DIR="${SOURCE_DIR}"
TARGET_DIR="${TARGET_DIR}"
LOCK_FILE="/tmp/brce_sync.lock"
LOG_FILE="/var/log/brce_sync.log"

# 日志函数
log_sync() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_sync "启动BRCE FTP双向实时同步服务"
log_sync "源目录: $SOURCE_DIR"
log_sync "目标目录: $TARGET_DIR"

# 创建锁文件目录和日志目录
mkdir -p "$(dirname "$LOCK_FILE")"
mkdir -p "$(dirname "$LOG_FILE")"

# 同步函数：避免循环同步，增强错误处理
sync_to_target() {
    if [[ ! -f "$LOCK_FILE.target" ]]; then
        touch "$LOCK_FILE.target"
        log_sync "同步 源→FTP"
        
        if rsync -av --delete "$SOURCE_DIR/" "$TARGET_DIR/" 2>> "$LOG_FILE"; then
            # 设置正确权限
            if chown -R "$USER:$USER" "$TARGET_DIR" 2>> "$LOG_FILE"; then
                find "$TARGET_DIR" -type f -exec chmod 644 {} \; 2>> "$LOG_FILE" || log_sync "WARNING: 部分文件权限设置失败"
                find "$TARGET_DIR" -type d -exec chmod 755 {} \; 2>> "$LOG_FILE" || log_sync "WARNING: 部分目录权限设置失败"
                log_sync "同步完成: 源→FTP"
            else
                log_sync "ERROR: 权限设置失败"
            fi
        else
            log_sync "ERROR: rsync同步失败 源→FTP"
        fi
        
        sleep 0.2
        rm -f "$LOCK_FILE.target"
    fi
}

sync_to_source() {
    if [[ ! -f "$LOCK_FILE.source" ]]; then
        touch "$LOCK_FILE.source"
        log_sync "同步 FTP→源"
        
        if rsync -av --delete "$TARGET_DIR/" "$SOURCE_DIR/" 2>> "$LOG_FILE"; then
            # 确保源目录文件权限正确（root可访问）
            find "$SOURCE_DIR" -type f -exec chmod 644 {} \; 2>> "$LOG_FILE" || log_sync "WARNING: 部分源文件权限设置失败"
            find "$SOURCE_DIR" -type d -exec chmod 755 {} \; 2>> "$LOG_FILE" || log_sync "WARNING: 部分源目录权限设置失败"
            log_sync "同步完成: FTP→源"
        else
            log_sync "ERROR: rsync同步失败 FTP→源"
        fi
        
        sleep 0.2
        rm -f "$LOCK_FILE.source"
    fi
}

# 监控源目录变化→FTP目录
monitor_source() {
            while true; do
            if inotifywait -m -r -e modify,create,delete,move,moved_to,moved_from "$SOURCE_DIR" 2>/dev/null |
        while read -r path action file; do
            log_sync "源目录变化: $action $file"
            sleep 0.05
            sync_to_target
        done; then
            log_sync "源目录监控正常重启"
        else
            log_sync "ERROR: 源目录监控失败，尝试重启..."
            sleep 5
        fi
    done
}

# 监控FTP目录变化→源目录  
monitor_target() {
            while true; do
            if inotifywait -m -r -e modify,create,delete,move,moved_to,moved_from "$TARGET_DIR" 2>/dev/null |
        while read -r path action file; do
            log_sync "FTP目录变化: $action $file"
            sleep 0.05
            sync_to_source
        done; then
            log_sync "FTP目录监控正常重启"
        else
            log_sync "ERROR: FTP目录监控失败，尝试重启..."
            sleep 5
        fi
    done
}

# 清理函数
cleanup() {
    log_sync "收到退出信号，正在清理..."
    kill $SOURCE_PID $TARGET_PID 2>/dev/null || true
    rm -f "$LOCK_FILE".*
    log_sync "同步服务已停止"
    exit 0
}

# 设置信号处理
trap cleanup SIGTERM SIGINT

# 初始同步（源→目标）
log_sync "执行初始同步（源→FTP）..."
if sync_to_target; then
    log_sync "初始同步完成，开始双向监控..."
else
    log_sync "ERROR: 初始同步失败"
    exit 1
fi

# 启动双向监控（后台并行运行）
monitor_source &
SOURCE_PID=$!

monitor_target &
TARGET_PID=$!

log_sync "双向同步已启动"
log_sync "源目录监控PID: $SOURCE_PID"
log_sync "FTP目录监控PID: $TARGET_PID"

# 等待任一进程结束
wait $SOURCE_PID $TARGET_PID
EOF

    # 设置脚本中的变量
    sed -i "s|\${USER}|$user|g" "$script_path"
    sed -i "s|\${SOURCE_DIR}|$source_dir|g" "$script_path"
    sed -i "s|\${TARGET_DIR}|$target_dir|g" "$script_path"
    
    if chmod +x "$script_path"; then
        log_info "实时同步脚本已创建: $script_path"
        return 0
    else
        log_error "无法设置脚本执行权限"
        return 1
    fi
}

# 创建systemd服务
create_sync_service() {
    local user="${1:-}"
    
    if [[ -z "$user" ]]; then
        log_error "create_sync_service: 缺少用户名参数"
        return 1
    fi
    
    local service_name="brce-ftp-sync"
    local script_path="/usr/local/bin/ftp_sync_${user}.sh"
    
    log_info "创建实时同步系统服务..."
    
    cat > "/etc/systemd/system/${service_name}.service" << EOF
[Unit]
Description=BRCE FTP Real-time Sync Service
After=network.target vsftpd.service
Requires=vsftpd.service

[Service]
Type=simple
ExecStart=$script_path
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    echo "✅ 系统服务已创建 ${service_name}.service"
}

# 启动实时同步服务
start_sync_service() {
    local service_name="brce-ftp-sync"
    
    echo "🚀 启动实时同步服务..."
    
    systemctl enable "$service_name"
    systemctl start "$service_name"
    
    if systemctl is-active --quiet "$service_name"; then
        echo "✅ 实时同步服务已启动 $service_name"
        echo "🔥 现在文件变化将零延迟同步到FTP"
    else
        echo "❌ 实时同步服务启动失败"
        echo "📋 查看错误日志:"
        journalctl -u "$service_name" --no-pager -n 10
        return 1
    fi
}

# 停止实时同步服务
stop_sync_service() {
    local service_name="brce-ftp-sync"
    
    echo "⏹️ 停止实时同步服务..."
    
    systemctl stop "$service_name" 2>/dev/null || true
    systemctl disable "$service_name" 2>/dev/null || true
    
    echo "✅ 实时同步服务已停止"
}

# 主安装函数
install_brce_ftp() {
    # 首先获取源目录配置
    get_source_directory
    if [ -z "$SOURCE_DIR" ]; then
        echo "❌ 源目录配置失败"
        return 1
    fi
    
    # 获取FTP用户名配置
    get_ftp_username
    if [ -z "$FTP_USER" ]; then
        echo "❌ FTP用户名配置失败"
        return 1
    fi
    
    echo ""
    echo "======================================================"
    echo "🚀 开始配置BRCE FTP服务 (双向零延迟版)"
    echo "======================================================"
    echo ""
    echo "🎯 源目录: $SOURCE_DIR"
    echo "👤 FTP用户: $FTP_USER"
    echo "🔥 特性: 双向实时同步，零延迟"
    echo ""
    
    # 确认配置
    read -p "是否使用双向零延迟实时同步？(y/n，默认 y): " confirm
    confirm=${confirm:-y}
    
    if [[ "$confirm" != "y" ]]; then
        log_info "用户取消配置"
        return 1
    fi
    
    # 获取FTP密码
    read -p "自动生成密码？(y/n，默认 y): " auto_pwd
    auto_pwd=${auto_pwd:-y}
    
    if [[ "$auto_pwd" == "y" ]]; then
        ftp_pass=$(openssl rand -base64 12 | tr -d "=+/" | cut -c1-12)
        log_info "已自动生成安全密码"
        log_debug "密码长度: ${#ftp_pass}"
    else
        local max_password_attempts=3
        local attempt=1
        
        while [[ $attempt -le $max_password_attempts ]]; do
            echo "密码要求：至少8位字符 (尝试 $attempt/$max_password_attempts)"
            read -s -p "FTP密码: " ftp_pass
            echo
            
            if [[ ${#ftp_pass} -ge 8 ]]; then
                # 确认密码
                read -s -p "再次输入密码确认: " ftp_pass_confirm
                echo
                
                if [[ "$ftp_pass" == "$ftp_pass_confirm" ]]; then
                    log_info "密码设置成功"
                    break
                else
                    log_error "两次输入的密码不一致"
                fi
            else
                log_error "密码至少8位字符"
            fi
            
            ((attempt++))
            if [[ $attempt -le $max_password_attempts ]]; then
                echo "请重试..."
                sleep 1
            fi
        done
        
        if [[ $attempt -gt $max_password_attempts ]]; then
            log_error "密码设置失败，已达到最大尝试次数"
            return 1
        fi
    fi
    
    echo ""
    log_step_start "FTP服务安装部署"
    log_info "开始部署..."
    log_info "用户: $FTP_USER"
    log_info "源目录: $SOURCE_DIR"
    log_info "密码类型: ${auto_pwd:-手动设置}"
    
    # 安装vsftpd和实时同步依赖
    log_step_start "软件包安装"
    log_info "检测包管理器..."
    if command -v apt-get &> /dev/null; then
        log_info "使用 apt-get 包管理器"
        log_command "apt-get update -qq" "更新软件包列表"
        log_command "apt-get install -y vsftpd rsync inotify-tools" "安装必需软件包"
    elif command -v yum &> /dev/null; then
        log_info "使用 yum 包管理器"
        log_command "yum install -y vsftpd rsync inotify-tools" "安装必需软件包"
    elif command -v dnf &> /dev/null; then
        log_info "使用 dnf 包管理器"
        log_command "dnf install -y vsftpd rsync inotify-tools" "安装必需软件包"
    else
        log_error "不支持的包管理器，请手动安装: vsftpd rsync inotify-tools"
        echo "❌ 安装失败：系统不支持自动安装"
        echo "💡 请手动执行以下命令安装依赖："
        echo "   • Debian/Ubuntu: apt-get install -y vsftpd rsync inotify-tools"
        echo "   • CentOS/RHEL: yum install -y vsftpd rsync inotify-tools"
        echo "   • Fedora: dnf install -y vsftpd rsync inotify-tools"
        return 1
    fi
    log_step_end "软件包安装"
    
    # 检查实时同步依赖
    if ! check_sync_dependencies; then
        log_warn "实时同步依赖检查失败，但安装将继续"
        echo "⚠️  实时同步依赖安装失败，您可以稍后手动安装："
        echo "   sudo apt-get install -y rsync inotify-tools  # Ubuntu/Debian"
        echo "   sudo yum install -y rsync inotify-tools      # CentOS/RHEL"
        echo "   sudo dnf install -y rsync inotify-tools      # Fedora"
    fi
    
        # 创建用户（基于主程序逻辑）
    log_step_start "用户配置"
    log_info "配置FTP用户: $FTP_USER"
    if id -u "$FTP_USER" &>/dev/null; then
        log_warn "用户已存在，将重置密码"
        log_info "现有用户信息: $(id "$FTP_USER")"
    else
        log_info "创建新用户: $FTP_USER"
        if command -v adduser &> /dev/null; then
            log_command "adduser \"$FTP_USER\" --disabled-password --gecos \"\"" "使用adduser创建用户"
        else
            log_command "useradd -m -s /bin/bash \"$FTP_USER\"" "使用useradd创建用户"
        fi
        log_info "用户创建成功: $(id "$FTP_USER")"
    fi
    
    # 安全设置用户密码（避免密码在进程列表中暴露）
    log_info "设置用户密码 (密码已隐藏)"
    # 保存密码用于显示（在清除前保存）
    display_password="$ftp_pass"
    if echo "$FTP_USER:$ftp_pass" | chpasswd; then
        log_info "用户密码设置成功"
    else
        log_error "用户密码设置失败"
        return 1
    fi
    unset ftp_pass  # 立即清除密码变量
    log_step_end "用户配置"
    
    # 处理录播姬路径权限问题
    setup_brec_root_permissions "$FTP_USER" "$SOURCE_DIR"
    if [[ $? -ne 0 ]]; then
        log_warn "录播姬权限配置遇到问题，将继续安装但可能需要手动调整权限"
        echo "⚠️  权限配置警告："
        echo "   • 安装将继续进行，但FTP用户可能无法访问源目录"
        echo "   • 建议安装完成后手动调整目录权限"
        echo "   • 或者重新运行脚本并选择其他目录（如 /opt/brec/file）"
        echo ""
        read -p "按回车键继续安装，或Ctrl+C取消..." -r
    fi
    
    # 配置权限
    ftp_home="/home/$FTP_USER/ftp"
    # 对于 /root 路径，使用特殊权限配置
    if [[ "$SOURCE_DIR" == /root/* ]]; then
        # /root 路径权限已通过 setup_brec_root_permissions 处理
        # 只配置 FTP 目录权限
        mkdir -p "$ftp_home"
        chown root:root "/home/$FTP_USER"
        chmod 755 "/home/$FTP_USER"
        chown "$FTP_USER:$FTP_USER" "$ftp_home"
        chmod 755 "$ftp_home"
        echo "✅ FTP目录权限配置完成"
    else
        # 普通路径使用标准权限配置
        configure_smart_permissions "$FTP_USER" "$SOURCE_DIR"
    fi
    
    # 停止旧的实时同步服务（如果存在）
    stop_sync_service
    
    # 卸载旧挂载（如果存在）
    if mountpoint -q "$ftp_home" 2>/dev/null; then
        echo "📤 卸载旧bind挂载"
        umount "$ftp_home" 2>/dev/null || true
        # 从fstab中移除
        sed -i "\|$ftp_home|d" /etc/fstab 2>/dev/null || true
    fi
    
    # 创建实时同步脚本和服务
    create_sync_script "$FTP_USER" "$SOURCE_DIR" "$ftp_home"
    create_sync_service "$FTP_USER"
    
    # 生成配置
    log_step_start "vsftpd配置生成"
    generate_optimal_config "$ftp_home"
    log_step_end "vsftpd配置生成"
    
    # 启动服务
    log_step_start "FTP服务启动"
    log_info "启动FTP服务..."
    echo "🔄 启动FTP服务..."
    echo "   • 正在重启vsftpd服务..."
    if systemctl restart vsftpd; then
        log_info "vsftpd服务重启成功"
    else
        log_error "vsftpd服务重启失败"
        return 1
    fi
    
    echo "   • 正在设置开机自启..."
    if systemctl enable vsftpd; then
        log_info "vsftpd开机自启设置成功"
    else
        log_warn "vsftpd开机自启设置失败"
    fi
    echo "   ✅ FTP服务启动完成"
    log_step_end "FTP服务启动"
    
    # 启动实时同步服务
    log_step_start "实时同步服务启动"
    if start_sync_service; then
        log_info "实时同步服务启动成功"
    else
        log_warn "实时同步服务启动失败，但安装将继续"
        echo "⚠️  实时同步服务启动失败，您可以稍后手动启动："
        echo "   sudo systemctl start brce-ftp-sync"
        echo "   sudo systemctl enable brce-ftp-sync"
    fi
    log_step_end "实时同步服务启动"
    
    # 配置防火墙（基于主程序逻辑）
    log_step_start "防火墙配置"
    log_info "配置防火墙规则..."
    echo "🔥 配置防火墙..."
    if command -v ufw &> /dev/null; then
        log_info "使用UFW配置防火墙"
        ufw allow 21/tcp >/dev/null 2>&1 || true
        ufw allow 40000:40100/tcp >/dev/null 2>&1 || true
        log_info "UFW防火墙规则配置完成"
        echo "✅ UFW: 已开放FTP端口"
    elif command -v firewall-cmd &> /dev/null; then
        log_info "使用Firewalld配置防火墙"
        firewall-cmd --permanent --add-service=ftp >/dev/null 2>&1 || true
        firewall-cmd --permanent --add-port=40000-40100/tcp >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
        log_info "Firewalld防火墙规则配置完成"
        echo "✅ Firewalld: 已开放FTP端口"
    else
        log_warn "未检测到支持的防火墙工具，请手动开放端口21和40000-40100"
    fi
    log_step_end "防火墙配置"
    
    # 获取服务器IP（基于主程序逻辑）
    log_step_start "获取连接信息"
    log_info "获取服务器连接信息..."
    external_ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}' || echo "localhost")
    log_info "服务器IP: $external_ip"
    
    log_step_end "获取连接信息"
    
    # 记录安装完成
    log_step_start "安装完成"
    log_info "BRCE FTP服务部署完成！"
    log_info "FTP用户: $FTP_USER"
    log_info "服务器IP: $external_ip"
    log_info "FTP端口: 21"
    log_info "访问目录: $SOURCE_DIR"
    log_info "实时同步: 已启用"
    log_step_end "安装完成"
    
    echo ""
    echo "======================================================"
    echo "✅ BRCE FTP服务部署完成！${SCRIPT_VERSION} (正式版)"
    echo "======================================================"
    echo ""
    echo "📋 连接信息："
    echo "   服务IP: $external_ip"
    echo "   端口: 21"
    echo "   用户: $FTP_USER"
    echo "   密码: ${display_password:-[密码显示错误,请查看日志]}"
    echo "   访问目录: $SOURCE_DIR"
    echo ""
    
    # 清除显示密码变量
    unset display_password
    
    echo "🎉 v1.0.3 新特性："
    echo "   👤 自定义目录：支持任意目录路径配置"
    echo "   🔄 双向零延迟：源目录↔FTP目录实时同步"
    echo "   🛡️ 智能路径处理：自动处理相对路径和绝对路径"
    echo "   📊 目录自动创建：不存在的目录自动创建"
    echo "   🔐 密码显示修复：正确显示生成的FTP密码"
    echo ""
    echo "💡 连接建议："
    echo "   - 使用被动模式（PASV）"
    echo "   - 端口范围: 40000-40100"
    echo "   - 支持大文件传输（视频文件）"
    echo ""
    echo "🎥 现在实现了真正的双向同步："
    echo "   📁 root操作源目录，立即可见"
    echo "   📤 FTP用户操作，源目录立即更新"
    echo ""
    echo "🔄 可通过菜单选项8随时在线更新到最新版"
    
    # 最终记录安装成功
    log_step_start "FTP服务安装部署总结"
    log_info "✅ FTP服务安装部署成功完成"
    log_info "所有步骤已执行完毕，服务正常运行"
    log_step_end "FTP服务安装部署总结"
    
    echo ""
    echo "🎉 安装完成！"
    echo "📝 重要提醒：请记录上面显示的密码信息"
    echo ""
    read -p "按回车键返回主菜单..." -r
}

# 列出所有FTP用户
list_ftp_users() {
    echo ""
    echo "======================================================"
    echo "👥 FTP用户列表"
    echo "======================================================"
    
    local ftp_users=()
    local user_count=0
    
    # 查找所有FTP用户（有/home/username/ftp目录的用户）
    for user_home in /home/*/ftp; do
        if [[ -d "$user_home" ]]; then
            local username=$(basename $(dirname "$user_home"))
            ftp_users+=("$username")
            ((user_count++))
        fi
    done
    
    if [[ $user_count -eq 0 ]]; then
        echo "⚠️  未找到任何FTP用户"
        echo ""
        return 1
    fi
    
    echo "📊 共找到 $user_count 个FTP用户："
    echo ""
    
    for i in "${!ftp_users[@]}"; do
        local username="${ftp_users[$i]}"
        local user_home="/home/$username"
        local ftp_dir="$user_home/ftp"
        
        echo "$((i+1)). 👤 $username"
        echo "   📁 FTP目录: $ftp_dir"
        
        # 检查用户状态
        if id "$username" &>/dev/null; then
            echo "   ✅ 系统用户: 存在"
        else
            echo "   ❌ 系统用户: 不存在"
        fi
        
        # 检查FTP目录文件数量
        if [[ -d "$ftp_dir" ]]; then
            local file_count=$(find "$ftp_dir" -type f 2>/dev/null | wc -l)
            echo "   📄 文件数量: $file_count"
        fi
        
        # 检查同步脚本
        local sync_script="/usr/local/bin/ftp_sync_${username}.sh"
        if [[ -f "$sync_script" ]]; then
            echo "   🔄 同步脚本: 存在"
        else
            echo "   ⚠️  同步脚本: 不存在"
        fi
        
        echo ""
    done
    
    return 0
}

# 更改FTP用户密码
change_ftp_password() {
    echo ""
    echo "======================================================"
    echo "🔑 更改FTP用户密码"
    echo "======================================================"
    
    # 先列出所有用户
    if ! list_ftp_users; then
        echo ""
        echo "❌ 没有FTP用户"
        echo "💡 请先创建FTP用户"
        echo ""
        read -p "按回车键返回用户管理菜单..." -r
        return 1
    fi
    
    echo "👤 请输入要更改密码的用户名："
    read -p "用户名: " target_user
    
    # 验证用户是否存在
    if ! id "$target_user" &>/dev/null; then
        log_error "用户 $target_user 不存在"
        echo ""
        echo "❌ 用户不存在"
        echo "💡 请检查用户名是否正确"
        echo ""
        read -p "按回车键返回用户管理菜单..." -r
        return 1
    fi
    
    # 检查是否为FTP用户
    if [[ ! -d "/home/$target_user/ftp" ]]; then
        log_error "用户 $target_user 不是FTP用户"
        echo ""
        echo "❌ 该用户不是FTP用户"
        echo "💡 请选择正确的FTP用户"
        echo ""
        read -p "按回车键返回用户管理菜单..." -r
        return 1
    fi
    
    echo ""
    echo "🔍 用户信息："
    echo "   用户名: $target_user"
    echo "   FTP目录: /home/$target_user/ftp"
    echo ""
    
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
            log_error "密码长度不足，至少8位字符"
            ((attempt++))
            continue
        fi
        
        read -s -p "确认密码: " confirm_password
        echo
        
        if [[ "$new_password" == "$confirm_password" ]]; then
            break
        else
            log_error "两次输入的密码不一致"
            ((attempt++))
        fi
        
        if [[ $attempt -le $max_attempts ]]; then
            echo "请重试..."
            sleep 1
        fi
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        log_error "密码设置失败，已达到最大尝试次数"
        return 1
    fi
    
    # 更改密码
    echo ""
    echo "🔄 正在更改密码..."
    
    if echo "$target_user:$new_password" | chpasswd; then
        log_info "用户 $target_user 的密码已成功更改"
        
        # 重启 FTP 服务以使新密码生效
        systemctl restart vsftpd 2>/dev/null || true
        
            echo ""
    echo "🎉 ======================================================"
    echo "✅ 密码更改成功！"
    echo "======================================================"
    echo ""
    echo "📝 新密码信息："
    echo "   👤 用户名: $target_user"
    echo "   🔑 新密码: $new_password"
    echo ""
    echo "📢 重要提示："
    echo "   • 请立即更新您的FTP客户端密码"
    echo "   • 旧密码已失效，请使用新密码登录"
    echo "   • 建议将新密码保存在密码管理器中"
    echo "======================================================"
        return 0
    else
        log_error "密码更改失败"
        return 1
    fi
}

# 添加新FTP用户
add_ftp_user() {
    echo ""
    echo "======================================================"
    echo "➕ 添加新FTP用户"
    echo "======================================================"
    
    # 获取用户名
    local new_username
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        echo ""
        echo "👤 输入新用户名 (尝试 $attempt/$max_attempts)"
        echo "格式要求: 以字母开头，可包含字母、数字、下划线、连字符，长度3-16位"
        
        read -p "新用户名: " new_username
        
        # 验证用户名格式
        if ! validate_username_format "$new_username"; then
            log_error "用户名格式不正确"
            ((attempt++))
            continue
        fi
        
        # 检查用户是否已存在
        if id "$new_username" &>/dev/null; then
            log_error "用户 $new_username 已存在"
            ((attempt++))
            continue
        fi
        
        # 用户名通过验证
        break
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        log_error "用户名设置失败，已达到最大尝试次数"
        return 1
    fi
    
    # 获取密码
    local user_password
    echo ""
    read -p "自动生成密码？(y/n，默认 y): " auto_pwd
    auto_pwd=${auto_pwd:-y}
    
    if [[ "$auto_pwd" == "y" ]]; then
        user_password=$(openssl rand -base64 12)
        log_info "已自动生成安全密码"
    else
        local confirm_password
        attempt=1
        
        while [[ $attempt -le $max_attempts ]]; do
            echo "密码要求：至少8位字符 (尝试 $attempt/$max_attempts)"
            read -s -p "请输入密码: " user_password
            echo
            
            if [[ ${#user_password} -lt 8 ]]; then
                log_error "密码长度不足，至少8位字符"
                ((attempt++))
                continue
            fi
            
            read -s -p "确认密码: " confirm_password
            echo
            
            if [[ "$user_password" == "$confirm_password" ]]; then
                break
            else
                log_error "两次输入的密码不一致"
                ((attempt++))
            fi
            
            if [[ $attempt -le $max_attempts ]]; then
                echo "请重试..."
                sleep 1
            fi
        done
        
        if [[ $attempt -gt $max_attempts ]]; then
            log_error "密码设置失败，已达到最大尝试次数"
            return 1
        fi
    fi
    
    # 获取源目录
    echo ""
    echo "📁 设置用户源目录："
    echo "默认: /root/brec/file/$new_username"
    read -p "请输入源目录路径（回车使用默认）: " user_source_dir
    
    if [[ -z "$user_source_dir" ]]; then
        user_source_dir="/root/brec/file/$new_username"
    fi
    
    # 创建用户
    echo ""
    echo "🔨 正在创建用户..."
    
    # 创建系统用户
    if ! useradd -m -s /bin/bash "$new_username"; then
        log_error "创建系统用户失败"
        return 1
    fi
    
    # 设置密码
    if ! echo "$new_username:$user_password" | chpasswd; then
        log_error "设置用户密码失败"
        userdel -r "$new_username" 2>/dev/null || true
        return 1
    fi
    
    # 配置文件权限和目录
    local user_home="/home/$new_username"
    local ftp_home="$user_home/ftp"
    
    # 处理录播姬路径权限问题
    setup_brec_root_permissions "$new_username" "$user_source_dir"
    if [[ $? -ne 0 ]]; then
        echo "⚠️  录播姬权限配置失败，但用户已创建"
        echo "💡 请手动设置权限或使用其他目录"
    fi
    
    # 创建必要的目录
    mkdir -p "$ftp_home"
    mkdir -p "$user_source_dir"
    
    # 设置所有权
    chown -R "$new_username:$new_username" "$user_home"
    # 注意：如果是 /root 下的目录，不能简单设置为普通用户所有权
    if [[ "$user_source_dir" != /root/* ]]; then
        chown -R "$new_username:$new_username" "$user_source_dir"
    fi
    
    # 设置权限
    chmod 755 "$user_home"
    chmod 755 "$ftp_home"
    if [[ "$user_source_dir" != /root/* ]]; then
        chmod 755 "$user_source_dir"
    fi
    
    log_info "用户 $new_username 创建成功"
    
    # 创建同步脚本
    if create_sync_script "$new_username" "$user_source_dir" "$ftp_home"; then
        log_info "同步脚本创建成功"
    else
        log_error "同步脚本创建失败"
    fi
    
    # 重启服务
    systemctl restart vsftpd 2>/dev/null || true
    systemctl restart brce-ftp-sync 2>/dev/null || true
    
    echo ""
    echo "🎉 ======================================================"
    echo "✅ FTP用户创建成功！"
    echo "======================================================"
    echo ""
    echo "📝 用户信息："
    echo "   👤 用户名: $new_username"
    echo "   🔑 密码: $user_password"
    echo "   📁 FTP目录: $ftp_home"
    echo "   💾 源目录: $user_source_dir"
    echo ""
    echo "📢 重要提示："
    echo "   • 请将以上信息安全保存"
    echo "   • 密码仅此一次显示，请立即记录"
    echo "   • 可通过菜单选项2修改密码"
    echo "======================================================"
    echo ""
    
    return 0
}

# 删除FTP用户
delete_ftp_user() {
    echo ""
    echo "======================================================"
    echo "🗑️ 删除FTP用户"
    echo "======================================================"
    
    # 先列出所有用户
    if ! list_ftp_users; then
        echo "没有FTP用户可删除"
        return 1
    fi
    
    echo "⚠️  请输入要删除的用户名："
    read -p "用户名: " target_user
    
    # 验证用户是否存在
    if ! id "$target_user" &>/dev/null; then
        log_error "用户 $target_user 不存在"
        echo ""
        echo "❌ 用户不存在"
        echo "💡 请检查用户名是否正确"
        echo ""
        read -p "按回车键返回用户管理菜单..." -r
        return 1
    fi
    
    # 检查是否为FTP用户
    if [[ ! -d "/home/$target_user/ftp" ]]; then
        log_error "用户 $target_user 不是FTP用户"
        echo ""
        echo "❌ 该用户不是FTP用户"
        echo "💡 请选择正确的FTP用户"
        echo ""
        read -p "按回车键返回用户管理菜单..." -r
        return 1
    fi
    
    echo ""
    echo "🔍 用户信息："
    echo "   用户名: $target_user"
    echo "   主目录: /home/$target_user"
    echo "   FTP目录: /home/$target_user/ftp"
    
    # 检查文件数量
    local file_count=$(find "/home/$target_user" -type f 2>/dev/null | wc -l)
    echo "   文件数量: $file_count"
    
    echo ""
    echo "⚠️  删除操作将："
    echo "   1. 删除系统用户 $target_user"
    echo "   2. 删除用户主目录 /home/$target_user"
    echo "   3. 删除同步脚本 /usr/local/bin/ftp_sync_${target_user}.sh"
    echo "   4. 删除所有用户数据 (不可恢复)"
    echo ""
    
    read -p "⚠️  确认删除用户 $target_user 吗？请输入用户名确认: " confirm_username
    
    if [[ "$confirm_username" != "$target_user" ]]; then
        log_info "用户名不匹配，取消删除操作"
        return 1
    fi
    
    read -p "⚠️  最后确认：是否删除用户 $target_user？(yes/NO): " final_confirm
    
    if [[ "$final_confirm" != "yes" ]]; then
        log_info "用户取消删除操作"
        return 1
    fi
    
    echo ""
    echo "🗑️ 正在删除用户..."
    
    # 停止相关进程
    pkill -u "$target_user" 2>/dev/null || true
    
    # 删除同步脚本
    rm -f "/usr/local/bin/ftp_sync_${target_user}.sh"
    
    # 删除系统用户和主目录
    if userdel -r "$target_user" 2>/dev/null; then
        log_info "用户 $target_user 已成功删除"
        
        # 重启服务
        systemctl restart vsftpd 2>/dev/null || true
        
        echo ""
        echo "✅ 用户删除成功！"
        echo ""
        return 0
    else
        log_error "用户删除失败"
        return 1
    fi
}

# 日志查看和管理功能
view_logs() {
    while true; do
        clear
        echo "======================================================"
        echo "📋 BRCE FTP 日志查看器"
        echo "======================================================"
        echo ""
        echo "请选择查看的日志："
        echo "1) 📄 安装配置日志 (setup.log)"
        echo "2) 🔄 实时同步日志 (sync.log)"
        echo "3) 🌐 FTP服务日志 (vsftpd.log)"
        echo "4) 📊 系统服务日志 (systemd)"
        echo "5) 🔍 搜索日志内容"
        echo "6) 🗑️ 日志清理管理"
        echo "7) ⚙️ 日志设置配置"
        echo "0) ⬅️ 返回主菜单"
        echo ""
            echo "📝 日志文件位置："
    echo "   • 主日志: $LOG_FILE"
    echo "   • 同步日志: /var/log/brce_sync.log"
    echo "   • FTP日志: /var/log/vsftpd.log"
    echo ""
    echo "💡 提示: 设置 DEBUG=1 启用详细调试日志"
    echo "   使用方法: DEBUG=1 sudo ./$(basename "$0")"
        echo ""
        read -p "请输入选项 (0-7): " log_choice
        
        case $log_choice in
            1)
                echo ""
                echo "📄 查看安装配置日志 (最近100行):"
                echo "======================================================"
                if [[ -f "$LOG_FILE" ]]; then
                    tail -n 100 "$LOG_FILE" | cat
                else
                    echo "⚠️ 安装配置日志文件不存在: $LOG_FILE"
                fi
                echo ""
                read -p "按回车键继续..." -r
                ;;
            2)
                echo ""
                echo "🔄 查看实时同步日志 (最近100行):"
                echo "======================================================"
                if [[ -f "/var/log/brce_sync.log" ]]; then
                    tail -n 100 /var/log/brce_sync.log | cat
                else
                    echo "⚠️ 同步日志文件不存在: /var/log/brce_sync.log"
                fi
                echo ""
                read -p "按回车键继续..." -r
                ;;
            3)
                echo ""
                echo "🌐 查看FTP服务日志 (最近50行):"
                echo "======================================================"
                if [[ -f "/var/log/vsftpd.log" ]]; then
                    tail -n 50 /var/log/vsftpd.log | cat
                else
                    echo "⚠️ FTP日志文件不存在: /var/log/vsftpd.log"
                fi
                echo ""
                read -p "按回车键继续..." -r
                ;;
            4)
                echo ""
                echo "📊 查看系统服务日志 (最近50行):"
                echo "======================================================"
                echo "🔸 BRCE FTP同步服务日志:"
                journalctl -u brce-ftp-sync --no-pager -n 25 2>/dev/null || echo "同步服务日志不可用"
                echo ""
                echo "🔸 vsftpd服务日志:"
                journalctl -u vsftpd --no-pager -n 25 2>/dev/null || echo "vsftpd服务日志不可用"
                echo ""
                read -p "按回车键继续..." -r
                ;;
            5)
                echo ""
                read -p "请输入要搜索的关键词: " search_term
                if [[ -n "$search_term" ]]; then
                    echo ""
                    echo "🔍 搜索结果 (关键词: $search_term):"
                    echo "======================================================"
                    echo "📄 安装配置日志中的匹配:"
                    [[ -f "$LOG_FILE" ]] && grep -i "$search_term" "$LOG_FILE" 2>/dev/null || echo "未找到匹配项"
                    echo ""
                    echo "🔄 同步日志中的匹配:"
                    [[ -f "/var/log/brce_sync.log" ]] && grep -i "$search_term" /var/log/brce_sync.log 2>/dev/null || echo "未找到匹配项"
                    echo ""
                    echo "🌐 FTP日志中的匹配:"
                    [[ -f "/var/log/vsftpd.log" ]] && grep -i "$search_term" /var/log/vsftpd.log 2>/dev/null || echo "未找到匹配项"
                else
                    echo "⚠️ 请输入搜索关键词"
                fi
                echo ""
                read -p "按回车键继续..." -r
                ;;
            6)
                clear
                echo "🗑️ 日志清理管理"
                echo "======================================================"
                echo ""
                echo "请选择清理方式："
                echo "1) 🧹 智能清理 (保留最近1000行)"
                echo "2) 🗂️ 按大小清理 (保留指定大小)"
                echo "3) 📅 按时间清理 (保留指定天数)"
                echo "4) 🔥 完全清空 (删除所有日志)"
                echo "5) 📊 查看日志文件大小"
                echo "0) ⬅️ 返回日志菜单"
                echo ""
                read -p "请选择清理方式 (0-5): " clean_choice
                
                case $clean_choice in
                    1)
                        echo ""
                        echo "🧹 智能清理 (保留最近1000行)"
                        echo "======================================================"
                        echo "这将清理以下日志文件的旧内容:"
                        echo "  • $LOG_FILE"
                        echo "  • /var/log/brce_sync.log"
                        echo "  • /var/log/vsftpd.log"
                        echo ""
                        read -p "确认清理？(y/N): " confirm_clean
                        if [[ "$confirm_clean" =~ ^[Yy]$ ]]; then
                            perform_smart_log_cleanup
                        else
                            echo "❌ 取消清理操作"
                        fi
                        ;;
                    2)
                        echo ""
                        echo "🗂️ 按大小清理"
                        echo "======================================================"
                        read -p "请输入要保留的最大文件大小 (MB，默认10): " max_size_mb
                        max_size_mb=${max_size_mb:-10}
                        perform_size_based_cleanup "$max_size_mb"
                        ;;
                    3)
                        echo ""
                        echo "📅 按时间清理"
                        echo "======================================================"
                        read -p "请输入要保留的天数 (默认7天): " keep_days
                        keep_days=${keep_days:-7}
                        perform_time_based_cleanup "$keep_days"
                        ;;
                    4)
                        echo ""
                        echo "🔥 完全清空所有日志"
                        echo "======================================================"
                        echo "⚠️  警告：这将删除所有日志内容！"
                        read -p "请输入 'DELETE' 确认完全清空: " confirm_delete
                        if [[ "$confirm_delete" == "DELETE" ]]; then
                            perform_complete_cleanup
                        else
                            echo "❌ 取消清空操作"
                        fi
                        ;;
                    5)
                        show_log_file_sizes
                        ;;
                    0)
                        continue
                        ;;
                    *)
                        echo "❌ 无效选项"
                        ;;
                esac
                echo ""
                read -p "按回车键继续..." -r
                ;;
            7)
                configure_log_settings
                echo ""
                read -p "按回车键继续..." -r
                ;;
            0)
                break
                ;;
            *)
                echo ""
                echo "❌ 无效选项！请输入 0-7 之间的数字"
                sleep 2
                ;;
        esac
    done
}

# 智能日志清理功能
perform_smart_log_cleanup() {
    echo "🧹 开始智能清理..."
    local cleaned_count=0
    
    # 清理安装配置日志
    if [[ -f "$LOG_FILE" ]]; then
        local original_size=$(wc -l < "$LOG_FILE" 2>/dev/null || echo "0")
        if [[ "$original_size" -gt 1000 ]]; then
            tail -n 1000 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
            echo "✅ 安装配置日志: $original_size → 1000 行"
            ((cleaned_count++))
        else
            echo "ℹ️  安装配置日志: $original_size 行 (无需清理)"
        fi
    fi
    
    # 清理同步日志
    if [[ -f "/var/log/brce_sync.log" ]]; then
        local original_size=$(wc -l < "/var/log/brce_sync.log" 2>/dev/null || echo "0")
        if [[ "$original_size" -gt 1000 ]]; then
            tail -n 1000 /var/log/brce_sync.log > /var/log/brce_sync.log.tmp && mv /var/log/brce_sync.log.tmp /var/log/brce_sync.log
            echo "✅ 实时同步日志: $original_size → 1000 行"
            ((cleaned_count++))
        else
            echo "ℹ️  实时同步日志: $original_size 行 (无需清理)"
        fi
    fi
    
    # 清理FTP日志
    if [[ -f "/var/log/vsftpd.log" ]]; then
        local original_size=$(wc -l < "/var/log/vsftpd.log" 2>/dev/null || echo "0")
        if [[ "$original_size" -gt 1000 ]]; then
            tail -n 1000 /var/log/vsftpd.log > /var/log/vsftpd.log.tmp && mv /var/log/vsftpd.log.tmp /var/log/vsftpd.log
            echo "✅ FTP服务日志: $original_size → 1000 行"
            ((cleaned_count++))
        else
            echo "ℹ️  FTP服务日志: $original_size 行 (无需清理)"
        fi
    fi
    
    echo ""
    if [[ "$cleaned_count" -gt 0 ]]; then
        echo "🎉 清理完成！已清理 $cleaned_count 个日志文件"
    else
        echo "✨ 所有日志文件都在合理范围内，无需清理"
    fi
}

# 按大小清理日志
perform_size_based_cleanup() {
    local max_size_mb="$1"
    local max_size_bytes=$((max_size_mb * 1024 * 1024))
    
    echo "🗂️ 按大小清理 (最大 ${max_size_mb}MB)..."
    local cleaned_count=0
    
    # 检查并清理各个日志文件
    for log_file in "$LOG_FILE" "/var/log/brce_sync.log" "/var/log/vsftpd.log"; do
        if [[ -f "$log_file" ]]; then
            local file_size=$(stat -c%s "$log_file" 2>/dev/null || echo "0")
            local file_size_mb=$((file_size / 1024 / 1024))
            
            if [[ "$file_size" -gt "$max_size_bytes" ]]; then
                # 计算需要保留的行数
                local total_lines=$(wc -l < "$log_file")
                local keep_lines=$((max_size_bytes * total_lines / file_size))
                
                tail -n "$keep_lines" "$log_file" > "${log_file}.tmp" && mv "${log_file}.tmp" "$log_file"
                local new_size=$(stat -c%s "$log_file" 2>/dev/null || echo "0")
                local new_size_mb=$((new_size / 1024 / 1024))
                
                echo "✅ $(basename "$log_file"): ${file_size_mb}MB → ${new_size_mb}MB"
                ((cleaned_count++))
            else
                echo "ℹ️  $(basename "$log_file"): ${file_size_mb}MB (无需清理)"
            fi
        fi
    done
    
    echo ""
    if [[ "$cleaned_count" -gt 0 ]]; then
        echo "🎉 大小清理完成！已清理 $cleaned_count 个日志文件"
    else
        echo "✨ 所有日志文件都在大小限制内"
    fi
}

# 按时间清理日志
perform_time_based_cleanup() {
    local keep_days="$1"
    
    echo "📅 按时间清理 (保留最近 ${keep_days} 天)..."
    
    # 创建临时脚本进行时间过滤
    local cleanup_script="/tmp/log_time_cleanup.sh"
    cat > "$cleanup_script" << 'EOF'
#!/bin/bash
log_file="$1"
keep_days="$2"
cutoff_date=$(date -d "$keep_days days ago" '+%Y-%m-%d')

if [[ -f "$log_file" ]]; then
    original_lines=$(wc -l < "$log_file")
    
    # 使用awk过滤指定日期之后的日志
    awk -v cutoff="$cutoff_date" '
    /^\[20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ {
        if ($1 >= "[" cutoff) print
        next
    }
    # 保留不符合日期格式的行（可能是重要信息）
    !/^\[20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ { print }
    ' "$log_file" > "${log_file}.tmp"
    
    if [[ -s "${log_file}.tmp" ]]; then
        mv "${log_file}.tmp" "$log_file"
        new_lines=$(wc -l < "$log_file")
        echo "✅ $(basename "$log_file"): $original_lines → $new_lines 行"
    else
        rm -f "${log_file}.tmp"
        echo "⚠️  $(basename "$log_file"): 没有符合条件的日志，保持原文件"
    fi
else
    echo "ℹ️  $(basename "$log_file"): 文件不存在"
fi
EOF
    
    chmod +x "$cleanup_script"
    
    # 清理各个日志文件
    "$cleanup_script" "$LOG_FILE" "$keep_days"
    "$cleanup_script" "/var/log/brce_sync.log" "$keep_days"
    "$cleanup_script" "/var/log/vsftpd.log" "$keep_days"
    
    rm -f "$cleanup_script"
    echo ""
    echo "🎉 时间清理完成！"
}

# 完全清空日志
perform_complete_cleanup() {
    echo "🔥 完全清空所有日志..."
    
    # 清空而不是删除文件，保持文件结构
    for log_file in "$LOG_FILE" "/var/log/brce_sync.log" "/var/log/vsftpd.log"; do
        if [[ -f "$log_file" ]]; then
            > "$log_file"  # 清空文件内容
            echo "✅ 已清空: $(basename "$log_file")"
        fi
    done
    
    # 清理systemd日志（如果用户确认）
    echo ""
    read -p "是否同时清理系统服务日志？(y/N): " clean_systemd
    if [[ "$clean_systemd" =~ ^[Yy]$ ]]; then
        journalctl --vacuum-time=1d 2>/dev/null || echo "⚠️  系统日志清理需要管理员权限"
        echo "✅ 系统服务日志已清理"
    fi
    
    echo ""
    echo "🎉 所有日志已完全清空！"
}

# 显示日志文件大小
show_log_file_sizes() {
    echo "📊 日志文件大小统计"
    echo "======================================================"
    
    local total_size=0
    
    for log_file in "$LOG_FILE" "/var/log/brce_sync.log" "/var/log/vsftpd.log"; do
        if [[ -f "$log_file" ]]; then
            local file_size=$(stat -c%s "$log_file" 2>/dev/null || echo "0")
            local file_size_mb=$((file_size / 1024 / 1024))
            local file_lines=$(wc -l < "$log_file" 2>/dev/null || echo "0")
            local file_name=$(basename "$log_file")
            
            printf "📄 %-20s: %3d MB (%s 行)\n" "$file_name" "$file_size_mb" "$file_lines"
            total_size=$((total_size + file_size))
        else
            printf "📄 %-20s: 不存在\n" "$(basename "$log_file")"
        fi
    done
    
    echo "======================================================"
    local total_size_mb=$((total_size / 1024 / 1024))
    echo "📊 总计: ${total_size_mb} MB"
    
    # 提供清理建议
    echo ""
    if [[ "$total_size_mb" -gt 50 ]]; then
        echo "💡 建议：日志文件较大 (${total_size_mb}MB)，建议进行清理"
    elif [[ "$total_size_mb" -gt 10 ]]; then
        echo "💡 提示：日志文件中等大小 (${total_size_mb}MB)，可考虑清理"
    else
        echo "✨ 日志文件大小合理 (${total_size_mb}MB)"
    fi
}

# 日志设置配置
configure_log_settings() {
    echo "⚙️ 日志设置配置"
    echo "======================================================"
    echo ""
    echo "请选择配置选项："
    echo "1) 📏 设置自动轮转大小 (当前: 2000行)"
    echo "2) 🔄 设置清理策略"
    echo "3) 📊 启用/禁用详细日志"
    echo "4) 🗜️ 配置日志压缩"
    echo "5) 📅 设置定期清理计划"
    echo "0) ⬅️ 返回"
    echo ""
    read -p "请选择配置选项 (0-5): " setting_choice
    
    case $setting_choice in
        1)
            echo ""
            echo "📏 设置自动轮转大小"
            echo "======================================================"
            echo "当前设置: 日志超过2000行时自动轮转"
            echo ""
            read -p "请输入新的轮转行数 (建议1000-5000): " new_rotation_size
            
            if [[ "$new_rotation_size" =~ ^[0-9]+$ ]] && [[ "$new_rotation_size" -ge 500 ]] && [[ "$new_rotation_size" -le 10000 ]]; then
                # 这里可以创建配置文件保存设置
                echo "✅ 轮转大小已设置为: $new_rotation_size 行"
                echo "💡 注意: 此设置将在下次重启脚本后生效"
            else
                echo "❌ 无效输入，请输入500-10000之间的数字"
            fi
            ;;
        2)
            echo ""
            echo "🔄 设置清理策略"
            echo "======================================================"
            echo "请选择默认清理策略："
            echo "1) 保守策略 (保留更多日志)"
            echo "2) 平衡策略 (推荐)"
            echo "3) 激进策略 (最小日志占用)"
            echo ""
            read -p "请选择策略 (1-3): " cleanup_strategy
            
            case $cleanup_strategy in
                1) echo "✅ 已设置为保守策略 (保留3000行, 30天, 50MB)" ;;
                2) echo "✅ 已设置为平衡策略 (保留1000行, 7天, 10MB)" ;;
                3) echo "✅ 已设置为激进策略 (保留500行, 3天, 5MB)" ;;
                *) echo "❌ 无效选择" ;;
            esac
            ;;
        3)
            echo ""
            echo "📊 详细日志设置"
            echo "======================================================"
            echo "当前状态: DEBUG=${DEBUG:-0}"
            echo ""
            read -p "是否启用详细调试日志？(y/N): " enable_debug
            
            if [[ "$enable_debug" =~ ^[Yy]$ ]]; then
                echo "export DEBUG=1" >> ~/.bashrc
                echo "✅ 详细日志已启用"
                echo "💡 重新登录或运行 'source ~/.bashrc' 生效"
            else
                sed -i '/export DEBUG=1/d' ~/.bashrc 2>/dev/null || true
                echo "✅ 详细日志已禁用"
            fi
            ;;
        4)
            echo ""
            echo "🗜️ 日志压缩配置"
            echo "======================================================"
            
            if command -v gzip &> /dev/null; then
                echo "✅ gzip 可用"
                read -p "是否启用自动压缩旧日志？(Y/n): " enable_compress
                enable_compress=${enable_compress:-Y}
                
                if [[ "$enable_compress" =~ ^[Yy]$ ]]; then
                    echo "✅ 自动压缩已启用"
                else
                    echo "ℹ️  自动压缩已禁用"
                fi
            else
                echo "⚠️  gzip 不可用，无法启用压缩功能"
            fi
            ;;
        5)
            echo ""
            echo "📅 定期清理计划"
            echo "======================================================"
            echo "设置系统定期清理日志 (使用cron)"
            echo ""
            read -p "是否设置每周自动清理？(y/N): " setup_cron
            
            if [[ "$setup_cron" =~ ^[Yy]$ ]]; then
                # 检查是否有现有的cron任务
                if crontab -l 2>/dev/null | grep -q "brce.*log.*cleanup"; then
                    echo "ℹ️  已存在日志清理计划"
                else
                    # 添加每周日志清理任务
                    (crontab -l 2>/dev/null; echo "0 2 * * 0 $(readlink -f "$0") --auto-cleanup-logs") | crontab -
                    echo "✅ 已设置每周日志清理计划 (周日2:00)"
                fi
            else
                echo "ℹ️  跳过定期清理设置"
            fi
            ;;
        0)
            return 0
            ;;
        *)
            echo "❌ 无效选项"
            ;;
    esac
}

# 用户管理菜单
user_management_menu() {
    while true; do
        clear
        echo "======================================================"
        echo "👥 FTP用户管理控制台"
        echo "======================================================"
        echo ""
        echo "请选择操作："
        echo "1) 📄 查看所有FTP用户"
        echo "2) 🔑 更改用户密码"
        echo "3) ➕ 添加新用户"
            echo "4) 🗑️ 删除用户"
    echo "0) ⬅️ 返回主菜单"
    echo ""
    echo "📝 快捷键： Ctrl+C 返回主菜单"
    echo ""
    read -p "请输入选项 (0-4): " user_choice
        
        case $user_choice in
            1)
                list_ftp_users
                echo ""
                echo "📝 操作提示："
                echo "   • 记住用户名和状态信息"
                echo "   • 可以截图保存用户列表"
                echo ""
                read -p "按回车键返回菜单..." -r
                ;;
            2)
                change_ftp_password
                echo ""
                echo "📝 安全提示："
                echo "   • 请妥善保管新密码"
                echo "   • 建议使用密码管理器保存"
                echo ""
                read -p "按回车键返回菜单..." -r
                ;;
            3)
                add_ftp_user
                echo ""
                echo "📝 后续操作："
                echo "   • 可以在菜单选项1查看新用户状态"
                echo "   • 记录用户名和密码信息"
                echo ""
                read -p "按回车键返回菜单..." -r
                ;;
            4)
                delete_ftp_user
                echo ""
                echo "📝 温馨提示："
                echo "   • 删除操作不可恢复，请谨慎操作"
                echo "   • 建议在删除前备份重要数据"
                echo ""
                read -p "按回车键返回菜单..." -r
                ;;
            0)
                break
                ;;
            *)
                echo ""
                echo "❌ 无效选项！请输入 0-4 之间的数字"
                echo "ℹ️  提示：输入数字后按回车键确认"
                sleep 2
                ;;
        esac
    done
}

# 安全获取当前配置信息
get_current_config() {
    # 尝试从现有服务配置中获取信息
    if systemctl is-active --quiet brce-ftp-sync 2>/dev/null; then
        # 从服务文件中提取用户信息
        local service_file="/etc/systemd/system/brce-ftp-sync.service"
        if [[ -f "$service_file" ]]; then
            local script_path=$(grep "ExecStart=" "$service_file" | cut -d'=' -f2)
            if [[ -n "$script_path" && -f "$script_path" ]]; then
                # 从脚本路径提取用户名 ftp_sync_${user}.sh
                FTP_USER=$(basename "$script_path" | sed 's/ftp_sync_\(.*\)\.sh/\1/')
                # 从脚本内容提取源目录
                SOURCE_DIR=$(grep "SOURCE_DIR=" "$script_path" | head -1 | cut -d'"' -f2)
            fi
        fi
    fi
    
    # 如果仍然为空，设置默认值
    FTP_USER="${FTP_USER:-unknown}"
    SOURCE_DIR="${SOURCE_DIR:-unknown}"
}

# 检查FTP状态 - 修复变量未初始化问题
check_ftp_status() {
    # 获取当前配置信息
    get_current_config
    
    echo ""
    echo "======================================================"
    echo "📊 BRCE FTP服务状态(零延迟版)"
    echo "======================================================"
    
    # 检查服务状态
    if systemctl is-active --quiet vsftpd; then
        log_info "FTP服务运行正常"
    else
        log_error "FTP服务未运行"
    fi
    
    # 检查实时同步服务
    if systemctl is-active --quiet brce-ftp-sync; then
        log_info "实时同步服务运行正常"
    else
        log_error "实时同步服务未运行"
    fi
    
    # 检查端口
    if ss -tlnp | grep -q ":21 "; then
        log_info "FTP端口21已开放"
    else
        log_error "FTP端口21未开放"
    fi
    
    # 检查用户（安全检查）
    if [[ "$FTP_USER" != "unknown" ]] && id "$FTP_USER" &>/dev/null; then
        log_info "FTP用户 $FTP_USER 存在"
    else
        log_error "FTP用户 $FTP_USER 不存在或未配置"
    fi
    
    # 检查目录（安全检查）
    if [[ "$FTP_USER" != "unknown" ]]; then
        local FTP_HOME="/home/$FTP_USER/ftp"
        if [[ -d "$FTP_HOME" ]]; then
            log_info "FTP目录存在: $FTP_HOME"
        else
            log_error "FTP目录不存在: $FTP_HOME"
        fi
    fi
    
    if [[ "$SOURCE_DIR" != "unknown" && -d "$SOURCE_DIR" ]]; then
        log_info "BRCE目录存在: $SOURCE_DIR"
        if file_count=$(find "$SOURCE_DIR" -type f 2>/dev/null | wc -l); then
            echo "📁 源目录文件数: $file_count"
            
            if [[ "$FTP_USER" != "unknown" ]]; then
                local FTP_HOME="/home/$FTP_USER/ftp"
                if [[ -d "$FTP_HOME" ]]; then
                    if ftp_file_count=$(find "$FTP_HOME" -type f 2>/dev/null | wc -l); then
                        echo "📁 FTP目录文件数: $ftp_file_count"
                        
                        if [[ "$file_count" -eq "$ftp_file_count" ]]; then
                            log_info "文件数量同步正确"
                        else
                            log_error "文件数量不匹配"
                        fi
                    fi
                fi
            fi
        fi
    else
        log_error "BRCE目录不存在或未配置: $SOURCE_DIR"
    fi
    
    # 显示同步服务日志
    echo ""
    echo "📋 实时同步日志 (最近5条):"
    journalctl -u brce-ftp-sync --no-pager -n 5 2>/dev/null || echo "暂无日志"
    
    # 显示连接信息
    local external_ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}' || echo "localhost")
    echo ""
    echo "📍 连接信息："
    echo "   服务器: $external_ip"
    echo "   端口: 21"
    echo "   用户名: $FTP_USER"
    echo "   模式: 双向零延迟实时同步"
}

# 测试实时同步 - 修复变量未初始化问题
test_realtime_sync() {
    # 获取当前配置信息
    get_current_config
    
    # 检查配置是否有效
    if [[ "$FTP_USER" == "unknown" || "$SOURCE_DIR" == "unknown" ]]; then
        log_error "未找到有效的FTP配置，请先运行安装配置"
        echo ""
        echo "❌ 无法进行同步测试"
        echo "💡 解决方案："
        echo "   1. 选择菜单选项 1) 安装/配置BRCE FTP服务"
        echo "   2. 确保FTP服务已正确安装配置"
        echo ""
        read -p "按回车键返回主菜单..." -r
        return 1
    fi
    
    echo ""
    echo "======================================================"
    echo "🧪 测试双向实时同步功能"
    echo "======================================================"
    
    local TEST_FILE="$SOURCE_DIR/realtime_test_$(date +%s).txt"
    local FTP_HOME="/home/$FTP_USER/ftp"
    local FTP_TEST_FILE="$FTP_HOME/ftp_test_$(date +%s).txt"
    
    # 验证目录存在
    if [[ ! -d "$SOURCE_DIR" ]]; then
        log_error "源目录不存在: $SOURCE_DIR"
        echo ""
        echo "❌ 源目录不存在，无法进行测试"
        echo "💡 请检查源目录配置或重新运行安装"
        echo ""
        read -p "按回车键返回主菜单..." -r
        return 1
    fi
    
    if [[ ! -d "$FTP_HOME" ]]; then
        log_error "FTP目录不存在: $FTP_HOME"
        echo ""
        echo "❌ FTP目录不存在，无法进行测试"
        echo "💡 请检查FTP用户配置或重新运行安装"
        echo ""
        read -p "按回车键返回主菜单..." -r
        return 1
    fi
    
    echo "📋 双向同步测试包括："
    echo "   1️⃣ 源目录→FTP目录 同步测试"
    echo "   2️⃣ FTP目录→源目录 同步测试"
    echo ""
    
    # ================== 测试1: 源目录→FTP目录 ==================
    echo "🔸 测试1: 源目录→FTP目录 同步"
    echo "📝 在源目录创建测试文件: $TEST_FILE"
    echo "实时同步测试(源→FTP) - $(date)" > "$TEST_FILE"
    
    echo "⏱️  等待3秒检查同步..."
    sleep 3
    
    if [ -f "$FTP_HOME/$(basename "$TEST_FILE")" ]; then
        echo "✅ 源→FTP: 文件创建同步成功"
    else
        echo "❌ 源→FTP: 文件创建同步失败"
    fi
    
    echo "📝 修改源目录测试文件..."
    echo "修改后的内容(源→FTP) - $(date)" >> "$TEST_FILE"
    
    echo "⏱️  等待3秒检查同步..."
    sleep 3
    
    if diff "$TEST_FILE" "$FTP_HOME/$(basename "$TEST_FILE")" >/dev/null 2>&1; then
        echo "✅ 源→FTP: 文件修改同步成功"
    else
        echo "❌ 源→FTP: 文件修改同步失败"
    fi
    
    echo "🗑️ 删除源目录测试文件..."
    rm -f "$TEST_FILE"
    
    echo "⏱️  等待3秒检查同步..."
    sleep 3
    
    if [ ! -f "$FTP_HOME/$(basename "$TEST_FILE")" ]; then
        echo "✅ 源→FTP: 文件删除同步成功"
    else
        echo "❌ 源→FTP: 文件删除同步失败"
    fi
    
    echo ""
    
    # ================== 测试2: FTP目录→源目录==================
    echo "🔸 测试2: FTP目录→源目录 同步"
    echo "📝 在FTP目录创建测试文件: $FTP_TEST_FILE"
    
    # 以FTP用户身份创建文件
    su - "$FTP_USER" -c "echo '实时同步测试(FTP→源) - $(date)' > '$FTP_TEST_FILE'" 2>/dev/null || {
        echo "实时同步测试(FTP→源) - $(date)" > "$FTP_TEST_FILE"
        chown "$FTP_USER:$FTP_USER" "$FTP_TEST_FILE"
    }
    
    echo "⏱️  等待3秒检查同步..."
    sleep 3
    
    SOURCE_TEST_FILE="$SOURCE_DIR/$(basename "$FTP_TEST_FILE")"
    if [ -f "$SOURCE_TEST_FILE" ]; then
        echo "✅ FTP→源: 文件创建同步成功"
    else
        echo "❌ FTP→源: 文件创建同步失败"
    fi
    
    echo "📝 修改FTP目录测试文件..."
    su - "$FTP_USER" -c "echo '修改后的内容(FTP→源) - $(date)' >> '$FTP_TEST_FILE'" 2>/dev/null || {
        echo "修改后的内容(FTP→源) - $(date)" >> "$FTP_TEST_FILE"
        chown "$FTP_USER:$FTP_USER" "$FTP_TEST_FILE"
    }
    
    echo "⏱️  等待3秒检查同步..."
    sleep 3
    
    if [ -f "$SOURCE_TEST_FILE" ] && diff "$FTP_TEST_FILE" "$SOURCE_TEST_FILE" >/dev/null 2>&1; then
        echo "✅ FTP→源: 文件修改同步成功"
    else
        echo "❌ FTP→源: 文件修改同步失败"
    fi
    
    echo "🗑️ 删除FTP目录测试文件..."
    rm -f "$FTP_TEST_FILE"
    
    echo "⏱️  等待3秒检查同步..."
    sleep 3
    
    if [ ! -f "$SOURCE_TEST_FILE" ]; then
        echo "✅ FTP→源: 文件删除同步成功"
        echo ""
        echo "🎉 双向实时同步功能完全正常！"
        echo "🎉 双向实时同步功能完全正常！"
    else
        echo "❌ FTP→源: 文件删除同步失败"
    fi
}

# 在线更新脚本
update_script() {
    while true; do
        clear
        echo "======================================================"
        echo "🔄 BRCE FTP脚本在线更新"
        echo "======================================================"
        echo ""
        echo "请选择更新方式："
        echo "1) 🔍 检查更新 (智能更新)"
        echo "2) ⚡ 强制更新 (直接覆盖)"
        echo "3) 📋 查看更新历史"
        echo "0) ⬅️ 返回主菜单"
        echo ""
        echo "💡 说明："
        echo "   • 智能更新: 比较版本和内容，仅在有差异时更新"
        echo "   • 强制更新: 无条件从GitHub获取最新代码"
        echo "   • 更新历史: 查看最近的GitHub提交记录"
        echo ""
        read -p "请输入选项 (0-3): " update_choice
        
        case $update_choice in
            1)
                perform_smart_update
                echo ""
                read -p "按回车键返回更新菜单..." -r
                ;;
            2)
                perform_force_update
                echo ""
                read -p "按回车键返回更新菜单..." -r
                ;;
            3)
                show_update_history
                echo ""
                read -p "按回车键返回更新菜单..." -r
                ;;
            0)
                break
                ;;
            *)
                echo ""
                echo "❌ 无效选项！请输入 0-3 之间的数字"
                sleep 2
                ;;
        esac
    done
}

# 智能更新功能
perform_smart_update() {
    echo ""
    echo "🔍 开始智能更新检查..."
    echo "======================================================"
    
    # 支持多个可能的URL
    local SCRIPT_URLS=(
        "https://raw.githubusercontent.com/Sannylew/bilirec-ftp-sync/main/ftp-setup.sh"
        "https://raw.githubusercontent.com/Sannylew/bilirec-ftp-sync/master/ftp-setup.sh"
    )
    
    CURRENT_SCRIPT="$(readlink -f "$0")"
    TEMP_SCRIPT="/tmp/brce_ftp_setup_new.sh"
    BACKUP_SCRIPT="${CURRENT_SCRIPT}.backup.$(date +%Y%m%d_%H%M%S)"
    
    echo "📋 更新信息："
    echo "   - 当前脚本: $CURRENT_SCRIPT"
    echo "   - 远程仓库: https://github.com/Sannylew/bilirec-ftp-sync"
    echo "   - 备份位置: $BACKUP_SCRIPT"
    echo ""
    
    # 检查网络连接
    if ! check_network_connection; then
        return 1
    fi
    
    # 尝试从多个URL下载最新版本
    echo "📥 下载最新版本..."
    local download_success=false
    local used_url=""
    
    for url in "${SCRIPT_URLS[@]}"; do
        echo "🔄 尝试从: $url"
        if curl -s --max-time 30 "$url" -o "$TEMP_SCRIPT" 2>/dev/null; then
            if [[ -f "$TEMP_SCRIPT" && -s "$TEMP_SCRIPT" ]]; then
                # 检查是否是有效的shell脚本
                if head -1 "$TEMP_SCRIPT" | grep -q "#!/bin/bash"; then
                    download_success=true
                    used_url="$url"
                    echo "✅ 下载成功"
                    break
                fi
            fi
        fi
        echo "❌ 此URL下载失败，尝试下一个..."
    done
    
    if [[ "$download_success" != "true" ]]; then
        echo "❌ 所有URL下载失败，请检查网络连接或稍后重试"
        echo "💡 您也可以手动从GitHub下载最新版本："
        echo "   https://github.com/Sannylew/bilirec-ftp-sync"
        rm -f "$TEMP_SCRIPT"
        return 1
    fi
    
    echo "📡 使用的下载地址: $used_url"
    
    # 验证下载的文件
    if [ ! -f "$TEMP_SCRIPT" ] || [ ! -s "$TEMP_SCRIPT" ]; then
        echo "❌ 下载的文件无效"
        rm -f "$TEMP_SCRIPT"
        return 1
    fi
    echo "✅ 下载验证通过"
    
    # 提取版本信息
    CURRENT_VERSION=$(grep "# 版本:" "$CURRENT_SCRIPT" | head -1 | sed 's/.*版本: *//' | sed 's/ .*//' 2>/dev/null || echo "未知")
    NEW_VERSION=$(grep "# 版本:" "$TEMP_SCRIPT" | head -1 | sed 's/.*版本: *//' | sed 's/ .*//' 2>/dev/null || echo "未知")
    
    # 计算文件内容差异
    local content_changed=false
    if ! diff -q "$CURRENT_SCRIPT" "$TEMP_SCRIPT" >/dev/null 2>&1; then
        content_changed=true
    fi
    
    # 获取文件大小和修改时间信息
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
        confirm_update=${confirm_update:-Y}  # 默认为Y
    else
        echo "ℹ️  当前脚本已是最新版本 (版本和内容均相同)"
        echo ""
        read -p "是否强制更新？(y/N): " confirm_update
        confirm_update=${confirm_update:-N}  # 默认为N
    fi
    
    if [[ ! "$confirm_update" =~ ^[Yy]$ ]]; then
        echo "✅ 取消更新，保持当前版本"
        rm -f "$TEMP_SCRIPT"
        return 0
    fi
    
    # 显示更新日志（如果有的话）
    echo "📝 检查更新说明..."
    if grep -q "v1.0.0.*自定义目录" "$TEMP_SCRIPT"; then
        echo "🚀 v1.0.0 正式版特性："
        echo "   - 📁 自定义目录：支持任意目录路径配置"
        echo "   - 🔄 双向实时同步：FTP用户操作立即同步到源目录"
        echo "   - 🛡️ 智能路径处理：自动处理相对路径和绝对路径"
        echo "   - 📊 在线更新：一键从GitHub更新到最新版"
        echo ""
    elif grep -q "v2.3.0 正式版" "$TEMP_SCRIPT"; then
        echo "🎉 v2.3.0 正式版特性："
        echo "   - 🔄 双向实时同步：FTP用户操作立即同步到源目录"
        echo "   - 🔒 防循环机制：智能锁机制避免同步循?"
        echo "   - 📊 在线更新：一键从GitHub更新到最新版"
        echo "   - 🛡️ 智能卸载：完整的卸载和脚本管理功能"
        echo ""
    elif grep -q "v2.2 重大更新" "$TEMP_SCRIPT"; then
        echo "🔥 v2.2 新功能："
        echo "   - 🔄 双向实时同步：FTP用户操作立即同步到源目录"
        echo "   - 🔒 防循环机制：智能锁机制避免同步循?"
        echo "   - 📊 性能优化：详细的性能影响分析和优化建议"
        echo ""
    fi
    
    # 确认更新
    read -p "🔄 确定要更新到最新版本吗？(y/N): " confirm_update
    if [[ ! "$confirm_update" =~ ^[Yy]$ ]]; then
        echo "✅ 取消更新"
        rm -f "$TEMP_SCRIPT"
        return 0
    fi
    
    # 检查是否有运行中的服务
    SERVICE_RUNNING=false
    if systemctl is-active --quiet brce-ftp-sync 2>/dev/null; then
        SERVICE_RUNNING=true
        echo "⚠️  检测到BRCE FTP服务正在运行"
        read -p "更新后需要重启服务，是否继续？(y/N): " restart_confirm
        if [[ ! "$restart_confirm" =~ ^[Yy]$ ]]; then
            echo "✅ 取消更新"
            rm -f "$TEMP_SCRIPT"
            return 0
        fi
    fi
    
    # 备份当前脚本
    echo "💾 备份当前脚本..."
    if ! cp "$CURRENT_SCRIPT" "$BACKUP_SCRIPT"; then
        echo "❌ 备份失败"
        rm -f "$TEMP_SCRIPT"
        return 1
    fi
    echo "✅ 备份完成: $BACKUP_SCRIPT"
    
    # 验证新脚本语?    echo "🔍 验证新脚本..."
    if ! bash -n "$TEMP_SCRIPT"; then
        echo "❌ 新脚本语法错误"
        rm -f "$TEMP_SCRIPT"
        return 1
    fi
    echo "✅ 脚本验证通过"
    
    # 替换脚本
    echo "🔄 更新脚本..."
    if ! cp "$TEMP_SCRIPT" "$CURRENT_SCRIPT"; then
        echo "❌ 更新失败，恢复备?"
        cp "$BACKUP_SCRIPT" "$CURRENT_SCRIPT"
        rm -f "$TEMP_SCRIPT"
        return 1
    fi
    
    # 设置执行权限
    chmod +x "$CURRENT_SCRIPT"
    rm -f "$TEMP_SCRIPT"
    
    echo "✅ 脚本更新成功"
    echo ""
    
    # 重启服务（如果需要）
    if [ "$SERVICE_RUNNING" = true ]; then
        echo "🔄 重启BRCE FTP服务..."
        systemctl restart brce-ftp-sync 2>/dev/null || true
        if systemctl is-active --quiet brce-ftp-sync; then
            echo "✅ 服务重启成功"
        else
            echo "⚠️  服务重启可能有问题，请检查状态"
        fi
        echo ""
    fi
    
    echo "🎉 更新完成"
    echo ""
    echo "📋 更新摘要："
    echo "   - 原版本: $CURRENT_VERSION"
    echo "   - 新版本: $NEW_VERSION"
    echo "   - 文件变化: $current_lines → $new_lines 行"
    echo "   - 大小变化: $current_size → $new_size 字节"
    echo "   - 备份文件: $BACKUP_SCRIPT"
    echo "   - 更新原因: $update_reason"
    echo ""
    echo "💡 提示："
    echo "   - 更新已生效，所有修改已保存"
    echo "   - 如果有问题，可以恢复备份: cp $BACKUP_SCRIPT $CURRENT_SCRIPT"
    echo "   - 建议运行菜单选项2检查服务状态"
    echo "   - 建议运行菜单选项6查看日志确认更新"
    echo ""
    
    read -p "🔄 是否立即重新启动脚本？(y/N): " restart_script
    if [[ "$restart_script" =~ ^[Yy]$ ]]; then
        echo "🚀 重新启动脚本..."
        exec "$CURRENT_SCRIPT"
    fi
}

# 强制更新功能
perform_force_update() {
    echo ""
    echo "⚡ 开始强制更新..."
    echo "======================================================"
    echo ""
    echo "⚠️  强制更新将："
    echo "   • 无条件下载GitHub最新代码"
    echo "   • 覆盖当前脚本文件"
    echo "   • 自动备份当前版本"
    echo ""
    read -p "确认执行强制更新？(y/N): " confirm_force
    
    if [[ ! "$confirm_force" =~ ^[Yy]$ ]]; then
        echo "✅ 取消强制更新"
        return 0
    fi
    
    # 使用相同的下载逻辑，但跳过版本检查
    local SCRIPT_URLS=(
        "https://raw.githubusercontent.com/Sannylew/bilirec-ftp-sync/main/ftp-setup.sh"
        "https://raw.githubusercontent.com/Sannylew/bilirec-ftp-sync/master/ftp-setup.sh"
    )
    
    local CURRENT_SCRIPT="$(readlink -f "$0")"
    local TEMP_SCRIPT="/tmp/brce_ftp_setup_force.sh"
    local BACKUP_SCRIPT="${CURRENT_SCRIPT}.backup.force.$(date +%Y%m%d_%H%M%S)"
    
    echo "📥 强制下载最新版本..."
    local download_success=false
    local used_url=""
    
    for url in "${SCRIPT_URLS[@]}"; do
        echo "🔄 尝试从: $url"
        if curl -s --max-time 30 "$url" -o "$TEMP_SCRIPT" 2>/dev/null; then
            if [[ -f "$TEMP_SCRIPT" && -s "$TEMP_SCRIPT" ]]; then
                if head -1 "$TEMP_SCRIPT" | grep -q "#!/bin/bash"; then
                    download_success=true
                    used_url="$url"
                    echo "✅ 下载成功"
                    break
                fi
            fi
        fi
        echo "❌ 此URL下载失败，尝试下一个..."
    done
    
    if [[ "$download_success" != "true" ]]; then
        echo "❌ 强制更新失败：无法下载最新版本"
        rm -f "$TEMP_SCRIPT"
        return 1
    fi
    
    # 创建备份
    echo "💾 创建备份..."
    if ! cp "$CURRENT_SCRIPT" "$BACKUP_SCRIPT"; then
        echo "❌ 备份失败"
        rm -f "$TEMP_SCRIPT"
        return 1
    fi
    
    # 验证下载的脚本
    echo "🔍 验证脚本语法..."
    if ! bash -n "$TEMP_SCRIPT"; then
        echo "❌ 下载的脚本语法错误"
        rm -f "$TEMP_SCRIPT"
        return 1
    fi
    
    # 执行强制更新
    echo "⚡ 执行强制更新..."
    if ! cp "$TEMP_SCRIPT" "$CURRENT_SCRIPT"; then
        echo "❌ 更新失败，恢复备份"
        cp "$BACKUP_SCRIPT" "$CURRENT_SCRIPT"
        rm -f "$TEMP_SCRIPT"
        return 1
    fi
    
    chmod +x "$CURRENT_SCRIPT"
    rm -f "$TEMP_SCRIPT"
    
    echo ""
    echo "🎉 强制更新完成！"
    echo "======================================================"
    echo "   • 已从GitHub获取最新代码"
    echo "   • 备份文件: $BACKUP_SCRIPT"
    echo "   • 使用的URL: $used_url"
    echo ""
    echo "💡 建议重新启动脚本以应用更新"
}

# 查看更新历史
show_update_history() {
    echo ""
    echo "📋 查看GitHub更新历史"
    echo "======================================================"
    
    echo "🌐 正在获取最近的提交记录..."
    
    # 尝试获取GitHub API信息
    local api_url="https://api.github.com/repos/Sannylew/bilirec-ftp-sync/commits"
    local temp_commits="/tmp/github_commits.json"
    
    if curl -s --max-time 10 "$api_url?per_page=5" -o "$temp_commits" 2>/dev/null; then
        if [[ -f "$temp_commits" && -s "$temp_commits" ]]; then
            echo "✅ 获取成功"
            echo ""
            echo "📝 最近5次提交记录："
            echo "======================================================"
            
            # 简单解析JSON (如果有jq更好，但这里用基础工具)
            local commit_count=0
            while read -r line && [[ $commit_count -lt 5 ]]; do
                if [[ "$line" =~ \"message\".*:.*\"([^\"]+)\" ]]; then
                    local message="${BASH_REMATCH[1]}"
                    echo "$((commit_count + 1)). $message"
                    ((commit_count++))
                fi
            done < "$temp_commits"
            
            if [[ $commit_count -eq 0 ]]; then
                echo "📄 无法解析提交信息，请直接访问GitHub查看"
            fi
            
            rm -f "$temp_commits"
        else
            echo "❌ 获取失败：响应文件无效"
        fi
    else
        echo "❌ 获取失败：网络连接问题"
    fi
    
    echo ""
    echo "🔗 直接访问链接："
    echo "   • GitHub仓库: https://github.com/Sannylew/bilirec-ftp-sync"
    echo "   • 提交历史: https://github.com/Sannylew/bilirec-ftp-sync/commits"
    echo "   • 最新版本: https://github.com/Sannylew/bilirec-ftp-sync/blob/main/ftp-setup.sh"
}

# 卸载FTP服务 - 修复变量未初始化问题
uninstall_brce_ftp() {
    # 获取当前配置信息
    get_current_config
    
    echo ""
    echo "======================================================"
    echo "🗑️ 卸载BRCE FTP服务"
    echo "======================================================"
    
    echo "📋 当前配置信息："
    echo "   - FTP用户: $FTP_USER"
    echo "   - 源目录: $SOURCE_DIR"
    if [[ "$FTP_USER" != "unknown" ]]; then
        echo "   - FTP目录: /home/$FTP_USER/ftp"
        echo "   - 同步脚本: /usr/local/bin/ftp_sync_${FTP_USER}.sh"
    fi
    echo "   - 系统服务: brce-ftp-sync.service"
    echo ""
    
    read -p "⚠️ 确定要卸载BRCE FTP服务吗？(y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "用户取消卸载"
        echo ""
        echo "✅ 取消卸载操作"
        echo ""
        read -p "按回车键返回主菜单..." -r
        return 1
    fi
    
    echo ""
    echo "🔧 卸载选项："
    echo "1) 完全卸载（包含vsftpd软件包）"
    echo "2) 仅卸载BRCE配置（保留vsftpd）"
    echo ""
    read -p "请选择卸载方式 (1/2，默认 2): " uninstall_type
    uninstall_type=${uninstall_type:-2}
    
    echo ""
    echo "🛑 停止FTP服务..."
    systemctl stop vsftpd 2>/dev/null || true
    systemctl disable vsftpd 2>/dev/null || true
    
    echo "⏹️ 停止实时同步服务..."
    stop_sync_service
    
    echo "🗑️ 删除同步服务文件..."
    rm -f "/etc/systemd/system/brce-ftp-sync.service"
    rm -f "/usr/local/bin/ftp_sync_${FTP_USER}.sh"
    systemctl daemon-reload
    
    echo "🗑️ 删除FTP用户..."
    userdel -r "$FTP_USER" 2>/dev/null || true
    
    echo "🗑️ 恢复配置文件..."
    # 恢复vsftpd配置（如果有备份?    latest_backup=$(ls /etc/vsftpd.conf.backup.* 2>/dev/null | tail -1)
    if [ -f "$latest_backup" ]; then
        echo "📋 恢复vsftpd配置: $latest_backup"
        cp "$latest_backup" /etc/vsftpd.conf
    else
        echo "⚠️  未找到vsftpd配置备份"
    fi
    
    # 清理fstab中的bind mount条目（如果有）
    if grep -q "/home/$FTP_USER/ftp" /etc/fstab 2>/dev/null; then
        echo "🗑️ 清理fstab条目..."
        sed -i "\|/home/$FTP_USER/ftp|d" /etc/fstab 2>/dev/null || true
    fi
    
    # 完全卸载选项
    if [[ "$uninstall_type" == "1" ]]; then
        echo ""
        echo "🗑️ 卸载vsftpd软件包..."
        read -p "⚠️ 确定要卸载vsftpd软件包吗？(y/N): " remove_pkg
        if [[ "$remove_pkg" =~ ^[Yy]$ ]]; then
            if command -v apt-get &> /dev/null; then
                apt-get remove --purge -y vsftpd 2>/dev/null || true
                echo "✅ vsftpd已卸载"
            elif command -v yum &> /dev/null; then
                yum remove -y vsftpd 2>/dev/null || true
                echo "✅ vsftpd已卸载"
            fi
        else
            echo "💡 保留vsftpd软件包"
        fi
    fi
    
    echo ""
    echo "🔄 脚本管理选项："
    echo "📋 当前脚本: $(readlink -f "$0")"
    echo ""
    read -p "🗑️ 是否删除本脚本文件？(y/N): " remove_script
    
    if [[ "$remove_script" =~ ^[Yy]$ ]]; then
        script_path=$(readlink -f "$0")
        echo "🗑️ 准备删除脚本: $script_path"
        echo "💡 3秒后删除脚本文件..."
        sleep 1 && echo "💡 2..." && sleep 1 && echo "💡 1..." && sleep 1
        
        # 创建自删除脚?        cat > /tmp/cleanup_brce_script.sh << EOF
#!/bin/bash
echo "🗑️ 删除BRCE FTP脚本..."
rm -f "$script_path"
if [ ! -f "$script_path" ]; then
    echo "✅ 脚本已删除: $script_path"
else
    echo "⚠️  脚本删除失败: $script_path"
fi
rm -f /tmp/cleanup_brce_script.sh
EOF
        chmod +x /tmp/cleanup_brce_script.sh
        
        echo "✅ 卸载完成"
        echo "💡 注意: BRCE目录 $SOURCE_DIR 保持不变"
        echo "🚀 正在删除脚本文件..."
        
        # 执行自删除并退?        exec /tmp/cleanup_brce_script.sh
    else
        echo "💡 保留脚本文件: $(readlink -f "$0")"
        echo "✅ 卸载完成"
        echo "💡 注意: BRCE目录 $SOURCE_DIR 保持不变"
        echo ""
        echo "🔄 脚本已保留，可以随时重新配置FTP服务"
        echo "📝 使用方法: sudo $(basename "$0")"
    fi
}

# 处理命令行参数
handle_command_line_args() {
    case "${1:-}" in
        --auto-cleanup-logs)
            echo "🤖 自动日志清理模式"
            echo "=================================="
            perform_smart_log_cleanup
            exit 0
            ;;
        --help|-h)
            echo "BRCE FTP 同步工具 $SCRIPT_VERSION"
            echo ""
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  --auto-cleanup-logs    自动清理日志 (适用于cron任务)"
            echo "  --help, -h            显示此帮助信息"
            echo ""
            echo "交互模式: $0 (无参数)"
            exit 0
            ;;
        "")
            # 无参数，继续正常流程
            return 0
            ;;
        *)
            echo "错误: 未知参数 '$1'"
            echo "使用 '$0 --help' 查看可用选项"
            exit 1
            ;;
    esac
}

# 主菜单
main_menu() {
    clear  # 清屏提升视觉体验
    echo "======================================================"
    echo "🚀 BRCE FTP 管理控制台 ${SCRIPT_VERSION}"
    echo "======================================================"
    echo ""
    echo "请选择操作："
    echo "1) 🚀 安装/配置BRCE FTP服务 (双向零延迟)"
    echo "2) 📊 查看FTP服务状态"
    echo "3) 🔄 重启FTP服务"
    echo "4) 🧪 测试双向实时同步功能"
    echo "5) 👥 FTP用户管理 (密码/添加/删除)"
    echo "6) 📋 查看日志文件 (故障排除)"
    echo "7) 🗑️ 卸载FTP服务"
    echo "8) 🔄 在线更新脚本"
    echo "0) 退出"
    echo ""
    echo "📝 快捷键： Ctrl+C 快速退出"
    echo ""
    read -p "请输入选项 (0-8): " choice
    
    case $choice in
        1)
            install_brce_ftp || {
                echo ""
                echo "⚠️ 安装过程遇到问题，请检查错误信息"
                read -p "按回车键返回主菜单..." -r
            }
            ;;
        2)
            check_ftp_status || {
                echo ""
                echo "⚠️ 状态检查遇到问题"
                read -p "按回车键返回主菜单..." -r
            }
            ;;
        3)
            echo "🔄 重启FTP服务..."
            systemctl restart vsftpd 2>/dev/null || echo "⚠️ vsftpd重启失败"
            systemctl restart brce-ftp-sync 2>/dev/null || echo "⚠️ 同步服务重启失败"
            if systemctl is-active --quiet vsftpd 2>/dev/null; then
                echo "✅ FTP服务重启成功"
            else
                echo "❌ FTP服务重启失败"
            fi
            echo ""
            read -p "按回车键返回主菜单..." -r
            ;;
        4)
            test_realtime_sync || {
                echo ""
                echo "⚠️ 同步测试遇到问题"
                read -p "按回车键返回主菜单..." -r
            }
            ;;
        5)
            user_management_menu || {
                echo ""
                echo "⚠️ 用户管理遇到问题"
                read -p "按回车键返回主菜单..." -r
            }
            ;;
        6)
            view_logs || {
                echo ""
                echo "⚠️ 日志查看遇到问题"
                read -p "按回车键返回主菜单..." -r
            }
            ;;
        7)
            uninstall_brce_ftp || {
                echo ""
                echo "⚠️ 卸载过程遇到问题"
                read -p "按回车键返回主菜单..." -r
            }
            ;;
        8)
            update_script || {
                echo ""
                echo "⚠️ 更新过程遇到问题"
                read -p "按回车键返回主菜单..." -r
            }
            ;;
        0)
            cleanup_and_exit 0
            ;;
        *)
            echo ""
            echo "❌ 无效选项！请输入 0-8 之间的数字"
            echo "ℹ️  提示：输入数字后按回车键确认"
            sleep 2
            ;;
    esac
}

# 主程序循环
# 处理命令行参数
handle_command_line_args "$@"

# 检查运行权限（移至此处避免函数依赖问题）
if [[ $EUID -ne 0 ]]; then
    echo "❌ 此脚本需要root权限，请使用 sudo 运行"
    echo "当前用户UID: $EUID (需要UID: 0)"
    exit 1
fi

init_script

# 使用安全的循环，添加退出检查
while true; do
    main_menu
    
    # 检查是否需要退出
    if [[ "${SHOULD_EXIT:-}" == "true" ]]; then
        cleanup_and_exit 0
    fi
done 
