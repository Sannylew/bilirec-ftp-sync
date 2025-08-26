---
## ⚠️🚨 **重要声明** 🚨⚠️

### 🔴 **此仓库为个人开发测试项目**
### 🔴 **仅供学习和技术研究使用**
### 🔴 **生产环境使用风险自负**

---

# BRCE FTP Realtime

**为哔哩哔哩录播姬定制的双向零延迟FTP同步工具 v1.0.3**

一个专门为[哔哩哔哩录播姬(BililiveRecorder)](https://github.com/BililiveRecorder/BililiveRecorder)设计的专业FTP部署脚本，提供双向实时同步、完整用户管理和自定义配置功能。

## 🚀 核心特性

- **双向实时同步**：录播文件变化立即同步到FTP，支持远程实时访问
- **多用户管理**：支持添加/删除/修改密码，每个用户独立目录
- **一键部署**：自动安装配置，支持主流Linux发行版
- **录播优化**：针对大文件传输和视频文件特别优化

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell Script](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-Linux-blue.svg)](https://www.linux.org/)
[![FTP Server](https://img.shields.io/badge/FTP-vsftpd-orange.svg)](https://security.appspot.com/vsftpd.html)
[![Sync](https://img.shields.io/badge/Sync-inotify+rsync-red.svg)](https://github.com/rvoicilas/inotify-tools)

## 💻 技术实现

**核心组件**：vsftpd + inotify + rsync + systemd
**部署方式**：Bash脚本一键安装
**同步原理**：实时文件监控 + 双向rsync同步



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
- 🧪 同步功能测试
- 🔄 在线更新

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

- **零延迟**：文件变化立即可见，无需刷新
- **双向同步**：root操作↔FTP操作完全同步
- **一键配置**：全部选择默认选项即可使用
- **智能处理**：自动创建目录，处理权限

## ⚡ 系统要求

- **系统**：Ubuntu/Debian/CentOS/RHEL/openSUSE/Arch Linux
- **权限**：root权限（sudo）
- **网络**：开放21端口和40000-40100端口段
- **依赖**：脚本自动安装vsftpd、rsync、inotify-tools

## 🛡️ 安全说明

- **权限处理**：使用录播姬默认路径 `/root/brec/file` 时，脚本会自动创建 `brec-ftp` 用户组并设置安全权限
- **最小权限**：FTP用户只获得读取录播文件的必要权限，不能修改 `/root` 下的其他内容
- **用户隔离**：每个FTP用户拥有独立的访问目录和权限范围

## 🔧 常用命令

```bash
# 服务状态检查
sudo systemctl status vsftpd
sudo systemctl status brce-ftp-sync

# 重启服务
sudo ./ftp-setup.sh  # 选择菜单选项3

# 查看日志
sudo journalctl -u brce-ftp-sync -f
```





## 📜 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

---

**如果这个项目对你的录播工作有帮助，请给个Star支持一下！⭐**
