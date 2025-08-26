---
## ⚠️🚨 **重要声明** 🚨⚠️

### 🔴 **此仓库为个人开发测试项目**
### 🔴 **仅供学习和技术研究使用**
### 🔴 **生产环境使用风险自负**

---

# BRCE FTP 同步工具

**为哔哩哔哩录播姬定制的双向零延迟FTP同步工具 v1.0.3**

一个专门为[哔哩哔哩录播姬(BililiveRecorder)](https://github.com/BililiveRecorder/BililiveRecorder)设计的专业FTP部署脚本，提供双向实时同步、完整用户管理、智能日志管理和专业级卸载功能。

## 🚀 核心特性

- **双向实时同步**：录播文件变化立即同步到FTP，支持远程实时访问
- **多用户管理**：支持添加/删除/修改密码，每个用户独立目录
- **智能日志系统**：完整的日志记录、查看、清理和配置功能
- **专业级卸载**：三种卸载模式，从标准卸载到深度清理
- **一键部署**：自动安装配置，支持主流Linux发行版
- **录播优化**：针对大文件传输和视频文件特别优化

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell Script](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-Linux-blue.svg)](https://www.linux.org/)
[![FTP Server](https://img.shields.io/badge/FTP-vsftpd-orange.svg)](https://security.appspot.com/vsftpd.html)
[![Sync](https://img.shields.io/badge/Sync-inotify+rsync-red.svg)](https://github.com/rvoicilas/inotify-tools)

## 💻 技术架构

### 🏗️ 核心组件
- **FTP服务器**：vsftpd (高性能、安全的FTP服务)
- **文件监控**：inotify-tools (Linux内核级文件事件监控)
- **同步引擎**：rsync (增量文件同步)
- **服务管理**：systemd (系统服务管理)
- **脚本语言**：Bash (跨发行版兼容)

### 🔄 同步机制
```
源目录 ←→ inotify监控 ←→ rsync同步 ←→ FTP目录
   ↓                                      ↓
录播姬文件                              FTP用户访问
```

### 📁 目录结构
```
/root/brec/file/          # 录播姬默认目录 (源目录)
├── 房间1/                # 主播房间目录
├── 房间2/                # 主播房间目录
└── ...

/home/用户名/ftp/         # FTP用户目录 (目标目录)
├── 房间1/                # 实时同步的房间目录
├── 房间2/                # 实时同步的房间目录  
└── ...
```

### 🛠️ 服务架构
- **主服务**：`brce-ftp-sync.service` (实时同步后台服务)
- **FTP服务**：`vsftpd.service` (FTP文件传输服务)
- **同步脚本**：`/usr/local/bin/ftp_sync_用户名.sh`
- **配置管理**：自动备份与恢复机制



## 📦 快速开始

### 安装使用

```bash
# 下载脚本
wget https://raw.githubusercontent.com/Sannylew/bilirec-ftp-sync/main/ftp-setup.sh

# 运行脚本
sudo chmod +x ftp-setup.sh
sudo ./ftp-setup.sh
```

### 基本配置
- **默认目录**：`/root/brec/file` （录播姬默认路径）
- **默认用户**：`sunny`
- **FTP端口**：21 + 40000-40100（被动模式）

### 主要功能
- 🚀 一键安装FTP服务
- 👥 用户管理（添加/删除/改密码）
- 📊 服务状态监控
- 🧪 双向同步功能测试
- 📝 智能日志管理（查看/清理/配置）
- 🔄 智能在线更新（检查更新/强制更新）
- 🗑️ 专业级卸载（标准/完全/深度清理）

## 📋 连接信息

安装完成后获得：
```
服务器: [你的服务器IP]
端口: 21
用户: [自定义用户名，默认sunny]
密码: [自动生成的安全密码]
目录: [自定义目录，默认/root/brec/file]
```

## 💡 核心优势

### 🚀 同步性能
- **零延迟**：文件变化立即可见，无需刷新
- **双向同步**：源目录↔FTP目录完全同步
- **智能监控**：基于inotify的文件系统事件监控
- **优化传输**：rsync增量同步，节省带宽

### 🛠️ 管理功能
- **一键配置**：全部选择默认选项即可使用
- **智能处理**：自动创建目录，处理权限
- **完整日志**：详细的安装、同步、错误日志
- **专业卸载**：多种卸载模式，彻底清理

### 🔒 安全特性
- **权限隔离**：每个FTP用户独立权限
- **用户组管理**：专用brce-ftp用户组
- **安全密码**：自动生成强密码
- **配置备份**：自动备份原始配置

## ⚡ 系统要求

- **系统**：Ubuntu/Debian/CentOS/RHEL/openSUSE/Arch Linux
- **权限**：root权限（sudo）
- **网络**：开放21端口和40000-40100端口段
- **依赖**：脚本自动安装vsftpd、rsync、inotify-tools

## 🛡️ 安全说明

- **权限处理**：使用录播姬默认路径 `/root/brec/file` 时，脚本会自动创建 `brce-ftp` 用户组并设置安全权限
- **最小权限**：FTP用户只获得读取录播文件的必要权限，不能修改 `/root` 下的其他内容
- **用户隔离**：每个FTP用户拥有独立的访问目录和权限范围
- **配置安全**：所有配置文件自动备份，支持安全恢复
- **日志审计**：完整的操作日志记录，便于安全审计

## 🔧 功能菜单

### 主菜单选项
```
====================================================
     🚀 BRCE FTP 实时同步部署工具 v1.0.3
====================================================
1) 📦 安装FTP服务和实时同步
2) 👥 FTP用户管理
3) 📊 查看FTP服务状态
4) 🧪 测试双向实时同步功能
5) 🔄 脚本更新
6) 📝 日志查看和管理
7) 🗑️ 卸载FTP服务
8) 🚪 退出脚本
```

### 日志管理功能 (选项6)
```
1) 📖 查看系统安装日志
2) 📋 查看实时同步日志  
3) 🔍 搜索日志内容
4) 🗑️ 日志清理管理
   - 智能清理 (保留最近1000行)
   - 按大小清理 (自定义大小限制)  
   - 按时间清理 (自定义天数)
   - 完全清空 (删除所有日志)
5) ⚙️ 日志设置配置
   - 配置自动轮转大小
   - 设置清理策略
   - 开启/关闭调试模式
```

### 卸载功能 (选项7)
```
1) 🚀 标准卸载 - 删除服务和用户，保留配置备份
2) 🔥 完全清理 - 删除所有相关文件和日志  
3) 🗑️ 深度清理 - 完全清理 + 卸载vsftpd软件包
```

### 更新功能 (选项5)
```
1) 🔍 检查更新 (智能更新) - 仅在内容有变化时更新
2) 🔄 强制更新 (直接覆盖) - 强制更新到最新版本
3) 📚 查看更新历史 - 显示GitHub提交记录
```

## 🔧 常用命令

```bash
# 服务状态检查
sudo systemctl status vsftpd
sudo systemctl status brce-ftp-sync

# 手动重启服务  
sudo systemctl restart vsftpd
sudo systemctl restart brce-ftp-sync

# 查看实时日志
sudo journalctl -u brce-ftp-sync -f
sudo tail -f /var/log/brce_sync.log

# 重新运行脚本
sudo ./ftp-setup.sh
```




## 🚨 故障排除

### 常见问题解决

#### 1. 同步不工作
```bash
# 检查服务状态
sudo systemctl status brce-ftp-sync
sudo systemctl status vsftpd

# 查看同步日志
sudo tail -f /var/log/brce_sync.log

# 重启服务
sudo systemctl restart brce-ftp-sync
```

#### 2. FTP连接失败  
```bash
# 检查防火墙
sudo ufw status
sudo ufw allow 21/tcp
sudo ufw allow 40000:40100/tcp

# 检查vsftpd配置
sudo systemctl status vsftpd
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
sudo ./ftp-setup.sh  # 选择选项7 -> 深度清理

# 重新下载安装
wget https://raw.githubusercontent.com/Sannylew/bilirec-ftp-sync/main/ftp-setup.sh
sudo chmod +x ftp-setup.sh
sudo ./ftp-setup.sh
```

### 📞 技术支持

- **GitHub Issues**: [提交问题](https://github.com/Sannylew/bilirec-ftp-sync/issues)
- **功能请求**: [Feature Request](https://github.com/Sannylew/bilirec-ftp-sync/issues/new)  
- **更新检查**: 脚本内置智能更新功能

## 📜 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

---

**如果这个项目对你的录播工作有帮助，请给个Star支持一下！⭐**
