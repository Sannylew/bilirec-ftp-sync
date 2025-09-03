# BRCE FTP 精简版

**为哔哩哔哩录播姬 + openlist 定制的轻量级FTP服务 v1.1.0**

一个专门为[哔哩哔哩录播姬(BililiveRecorder)](https://github.com/BililiveRecorder/BililiveRecorder)和[openlist](https://github.com/openlist-project/openlist)文件列表程序设计的轻量级FTP部署脚本，使用文件映射技术，实现录播文件的实时访问和Web化管理。

> **注**：openlist是[Alist](https://github.com/alist-org/alist)的一个分支，继承了Alist的所有功能特性。

## 🎯 项目目标

为哔哩哔哩录播姬录制的文件提供Web化访问和管理，通过openlist实现实时文件展示和分享。

## 🚀 核心特性

- **⚡ 实时访问**：录播文件生成后立即可见
- **🔒 权限控制**：支持只读、删除、读写三种模式
- **🚀 一键部署**：自动安装配置
- **🌐 openlist集成**：完美兼容openlist的FTP存储驱动

## 💻 技术架构

```
哔哩哔哩录播姬 → /opt/brec/file → bind mount → FTP服务 → openlist → Web访问
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



## 🎮 主要功能

### 主菜单选项
```
======================================================
🚀 BRCE FTP 精简版管理控制台 v1.1.0
======================================================
1) 🚀 安装/配置FTP服务 (文件映射版)
2) 📊 查看FTP服务状态
3) 🔄 重启FTP服务
4) ⏹️ 停止FTP服务
5) 👥 FTP用户管理
6) 🧪 实时性测试
7) 🔗 挂载文件映射
8) 🔒 权限管理 (只读/删除权限)
9) 🔄 检查脚本更新
10) 🗑️ 卸载FTP服务
0) 退出
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

## 🌐 openlist配置指南

### 在openlist中添加FTP存储

1. **登录openlist管理界面**
2. **进入存储管理** → **添加存储**
3. **选择存储类型**：FTP
4. **填写配置信息**：
   ```
   存储名称: 哔哩哔哩录播文件
   地址: [你的服务器IP]
   端口: 21
   用户名: [FTP用户名]
   密码: [FTP密码]
   根目录: /
   缓存过期时间: 0 (实时访问)
   ```

### 权限模式选择建议

- **只读模式**：适合纯展示，保护录播文件安全
- **删除权限模式**：适合需要清理旧文件，但不想修改文件内容
- **读写权限模式**：适合需要上传或修改文件的场景




## ⚡ 系统要求

- **系统**：主流Linux发行版
- **权限**：root权限
- **网络**：开放21端口和40000-40100端口段









## 📜 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

---

## 🙏 致谢

感谢以下开源项目：
- [哔哩哔哩录播姬(BililiveRecorder)](https://github.com/BililiveRecorder/BililiveRecorder) - 优秀的录播工具
- [openlist](https://github.com/openlist-project/openlist) - 强大的文件列表程序（Alist分支）
- [Alist](https://github.com/alist-org/alist) - 原始的文件列表程序
- [vsftpd](https://security.appspot.com/vsftpd.html) - 高性能FTP服务器

**如果这个项目对你的录播工作和openlist集成有帮助，请给个Star支持一下！⭐**
