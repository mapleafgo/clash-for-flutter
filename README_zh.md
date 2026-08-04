<div align="center">
  <img src="assets/logo.svg" alt="Singcast" width="120" height="120">
  <h1>Singcast</h1>
  <p><strong>基于 <a href="https://github.com/SagerNet/sing-box">sing-box</a> 高性能内核的多平台代理客户端，全面支持 Clash、sing-box 与 v2ray 订阅（导入后统一转换为 sing-box 配置运行）</strong></p>
</div>

<p align="center">
  <a href="README.md">English</a> | <a href="README_zh.md">中文</a>
</p>

<p align="center">
  <a href="https://t.me/+xcHAK5RADfY4NmZl">
    <img src="https://img.shields.io/badge/Telegram-Group-blue?logo=telegram&logoColor=white" alt="Telegram">
  </a>
</p>

Singcast 是一个基于 Flutter 开发、使用定制版 [sing-box](https://github.com/SagerNet/sing-box) 内核的开源多平台代理客户端。全面支持 Clash、sing-box 与 v2ray 订阅——无论是 yaml/yml/json/txt 配置文件，还是 v2ray base64/URI 列表订阅，导入后都会统一转换为 sing-box 配置运行，导入即用。

支持 **Windows**、**Linux**、**macOS** 和 **Android**。

**iOS** 暂不支持。

- **桌面端**：内核以独立特权进程运行，通过 JSON-RPC（IPC）与 UI 通信，确保界面稳定可靠。
- **移动端**：内核以原生库形式通过 FFI 加载，与平台 VPN 服务深度集成（暂不支持 iOS）。
- **TUN 模式**：透明代理，自动管理路由，无需手动配置系统代理。

> [使用说明](https://mapleafgo.github.io/singcast)

## 预览

![主页](./docs/images/home_page.png)

## 功能

- 全面支持 Clash、sing-box 与 v2ray 订阅及配置文件（yaml/yml/json/txt，导入后统一转 sing-box）
- 支持系统代理和 TUN 模式（全局透明代理）
- 代理节点选择与延迟测速
- 实时流量统计
- 订阅管理，支持导入和更新订阅链接
- 日志查看与导出
- 桌面端系统托盘

## 使用

### Linux

使用前请确保安装以下依赖

```bash
sudo apt-get install libayatana-appindicator3
```

### 下载

[GitHub Releases](https://github.com/mapleafgo/singcast/releases/latest)

## 构建

1. 安装 `Flutter v3.41+` 环境

   > 针对目标平台时，需要参照 Flutter 官方文档进行对应平台的环境搭建。如 Android 开发时，需要 Android SDK

2. 下载内核

   从 [singcast-cli Releases](https://github.com/mapleafgo/singcast-cli/releases/latest) 下载对应平台的内核，放置到以下路径：

   ```shell
   # 桌面端 (IPC 独立进程)
   windows/core/singcast-core.exe
   linux/core/singcast-core
   macos/Frameworks/singcast-core

   # 移动端 (FFI 原生库)
    android/app/libs/libsingcast.aar
   ```

3. 编译运行

   ```shell
   # 获取依赖
   flutter pub get
   # 生成代码
   dart run build_runner build --delete-conflicting-outputs
   # 运行
   flutter run -d linux
   ```

## 常见问题

### 订阅无法拉取 / 更新失败

如果订阅更新时一直加载或返回错误，可能是订阅服务提供方对 User-Agent 做了限制。可以尝试在 **设置 → 普通设置 → 订阅 User-Agent** 中切换为其他 UA（如 `clash-verge/v2.0.0`、`clash-meta` 等），然后重新更新订阅。

## 主要技术

- [sing-box](https://github.com/SagerNet/sing-box)
- [Flutter](https://flutter.dev)
- [signals_flutter](https://github.com/rodydavis/signals.dart)
- [go_router](https://pub.dev/packages/go_router)
- [window_manager](https://github.com/leanflutter/window_manager)
- [desktop_tray](https://pub.dev/packages/desktop_tray)
- [dart_ipc](https://pub.dev/packages/dart_ipc)
- [ffi](https://dart.dev/guides/libraries/c-interop)
