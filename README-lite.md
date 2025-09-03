# BRCE FTP 精简版

**为哔哩哔哩录播姬定制的轻量级FTP服务 v1.0.0**

一个专门为[哔哩哔哩录播姬(BililiveRecorder)](https://github.com/BililiveRecorder/BililiveRecorder)设计的轻量级FTP部署脚本，使用文件映射技术，提供零延迟的文件访问体验。

## 🚀 核心特性

- **⚡ 实时文件访问**：使用只读bind mount实现零延迟文件访问
- **🔄 内核级映射**：基于Linux内核的文件系统映射，无需同步
- **🔒 只读保护**：只读模式保护录播文件，避免与录播姬冲突
- **📁 轻量级设计**：无需复杂的同步机制，直接映射源目录
- **👥 多用户管理**：支持添加/删除/修改密码，每个用户独立访问
- **🚀 一键部署**：自动安装配置，支持主流Linux发行版
- **🎥 录播优化**：完全兼容录播姬，零干扰，实时可见

## 💻 技术架构

### 🏗️ 核心组件
- **FTP服务器**：vsftpd (高性能、安全的FTP服务)
- **文件映射**：bind mount (Linux内核级文件系统映射)
- **服务管理**：systemd (系统服务管理)
- **脚本语言**：Bash (跨发行版兼容)

### 🔄 映射机制
```
源目录 (/opt/brec/file) ←→ 只读bind mount ←→ FTP用户目录
   ↓                                      ↓
录播姬文件                              FTP用户访问
   (可写)                                (只读)
```

### 📁 目录结构
```
/opt/brec/file/          # 录播姬源目录 (默认路径)
├── 房间1/                # 主播房间目录
├── 房间2/                # 主播房间目录
└── ...

/home/用户名/ftp/         # FTP用户映射目录
├── 房间1/                # 直接映射的房间目录
├── 房间2/                # 直接映射的房间目录  
└── ...
```

## 📦 快速开始

### 安装使用

```bash
# 下载精简版脚本
wget https://raw.githubusercontent.com/Sannylew/bilirec-ftp-sync/main/ftp-setup-lite.sh

# 运行脚本
sudo chmod +x ftp-setup-lite.sh
sudo ./ftp-setup-lite.sh
```

### 基本配置
- **默认目录**：`/opt/brec/file` （录播姬路径）
- **默认用户**：`sunny`
- **FTP端口**：21 + 40000-40100（被动模式）

## 🎮 主要功能

### 主菜单选项
```
======================================================
🚀 BRCE FTP 精简版管理控制台 v1.0.0
======================================================
1) 🚀 安装/配置FTP服务 (文件映射版)
2) 📊 查看FTP服务状态
3) 🔄 重启FTP服务
4) ⏹️ 停止FTP服务
5) 👥 FTP用户管理
6) 🧪 实时性测试
7) 🗑️ 卸载FTP服务
0) 退出
```

### 用户管理功能 (选项5)
```
1) 📄 查看FTP用户
2) 🔑 更改用户密码
3) ➕ 添加新用户
4) 🗑️ 删除用户
0) ⬅️ 返回主菜单
```

## 📋 连接信息

安装完成后获得：
```
服务器: [你的服务器IP]
端口: 21
用户: [自定义用户名，默认sunny]
密码: [自动生成的安全密码]
目录: /opt/brec/file
被动端口: 40000-40100
```

## 💡 核心优势

### 🚀 性能优势
- **⚡ 零延迟**：文件变化立即可见，无需同步等待
- **🔄 直接映射**：基于bind mount，无额外I/O开销
- **📡 实时访问**：录播文件写入后立即可通过FTP访问
- **💾 资源节省**：无需同步进程，节省CPU和内存
- **🧪 可测试**：内置实时性测试功能，验证零延迟特性

### 🛠️ 管理优势
- **一键配置**：全部选择默认选项即可使用
- **智能处理**：自动创建目录，处理权限
- **简单维护**：无复杂同步逻辑，易于故障排除
- **轻量卸载**：快速清理，不留残留

### 🔒 安全特性
- **权限隔离**：每个FTP用户独立权限
- **只读映射**：默认只读访问，保护源文件
- **安全密码**：自动生成强密码
- **配置备份**：自动备份原始配置

## ⚡ 系统要求

- **系统**：Ubuntu/Debian/CentOS/RHEL/openSUSE/Arch Linux
- **权限**：root权限（sudo）
- **网络**：开放21端口和40000-40100端口段
- **依赖**：脚本自动安装vsftpd

## 🛡️ 安全说明

### 🔒 路径安全优势
- **避免root权限问题**：使用 `/opt/brec/file` 路径，避免 `/root` 目录的复杂权限配置
- **标准系统目录**：符合FHS规范，系统管理员更容易理解和维护
- **权限隔离**：不会影响 `/root` 目录下的其他敏感文件

### 🛡️ 安全配置
- **最小权限原则**：FTP用户只获得读取文件的必要权限
- **目录遍历保护**：自动配置父目录权限，防止目录遍历攻击
- **用户隔离**：每个FTP用户拥有独立的访问目录
- **只读映射**：默认只读访问，保护源文件不被修改
- **配置备份**：所有配置文件自动备份，支持安全恢复

### ⚠️ 安全注意事项
- **定期检查权限**：建议定期检查目录权限设置
- **监控访问日志**：通过vsftpd日志监控异常访问
- **防火墙配置**：确保只开放必要的FTP端口
- **密码安全**：使用强密码，定期更换

## 🔧 常用命令

### 基础管理
```bash
# 服务状态检查
sudo systemctl status vsftpd

# 手动重启服务  
sudo systemctl restart vsftpd

# 查看挂载状态
mount | grep ftp

# 重新运行脚本
sudo ./ftp-setup-lite.sh
```

### 安全检查
```bash
# 检查目录权限
ls -la /opt/brec/file
ls -la /home/用户名/ftp

# 检查挂载点
mount | grep bind

# 查看FTP访问日志
sudo tail -f /var/log/vsftpd.log

# 检查防火墙状态
sudo ufw status
```

### 权限验证
```bash
# 验证FTP用户权限
sudo -u 用户名 ls /home/用户名/ftp

# 检查目录遍历保护
sudo -u 用户名 ls /home/用户名/ftp/../

# 查看系统权限
stat /opt/brec/file
stat /home/用户名/ftp
```

## 🚨 故障排除

### 常见问题解决

#### 1. FTP连接失败  
```bash
# 检查防火墙
sudo ufw status
sudo ufw allow 21/tcp
sudo ufw allow 40000:40100/tcp

# 检查vsftpd状态
sudo systemctl status vsftpd
```

#### 2. 文件映射异常
```bash
# 检查挂载状态
mount | grep ftp

# 重新挂载
sudo mount --bind /opt/brec/file /home/用户名/ftp
```

#### 3. 权限问题
```bash
# 重新设置权限
sudo chown -R 用户名:用户名 /home/用户名/ftp
sudo chmod -R 755 /home/用户名/ftp
```

#### 4. 完全重新安装
```bash
# 使用卸载功能完全清理
sudo ./ftp-setup-lite.sh  # 选择选项6

# 重新下载安装
wget https://raw.githubusercontent.com/Sannylew/bilirec-ftp-sync/main/ftp-setup-lite.sh
sudo chmod +x ftp-setup-lite.sh
sudo ./ftp-setup-lite.sh
```

## 📊 与完整版对比

| 特性 | 精简版 | 完整版 |
|------|--------|--------|
| 文件访问方式 | 直接映射 | 实时同步 |
| 资源占用 | 极低 | 中等 |
| 安装复杂度 | 简单 | 复杂 |
| 录播兼容性 | 完全兼容 | 需要保护模式 |
| 功能丰富度 | 基础功能 | 高级功能 |
| 适用场景 | 简单文件分享 | 双向同步需求 |

## 📜 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

---

**如果这个项目对你的录播工作有帮助，请给个Star支持一下！⭐**
