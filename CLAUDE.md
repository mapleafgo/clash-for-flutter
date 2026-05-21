# CLAUDE.md

这个文件为 Claude Code (claude.ai/code) 在处理这个仓库的代码时提供指导。

## 配置设置
### 默认交互语言
- **language**: `Chinese` (中文)

Claude Code 将默认使用中文与开发者进行交互，包括代码注释、文档说明和操作提示。

## 概述
Singcast 是一个支持 Windows、Linux、macOS 和 Android 的多平台代理客户端。它使用 Flutter 构建并结合了一个自定义的 sing-box 内核。

## 常用命令

### 开发
```bash
# 获取依赖
flutter pub get

# 生成 .g.dart 文件
dart run build_runner build --delete-conflicting-outputs

# 在 Linux 上运行
flutter run -d linux

# 在 Windows 上运行
flutter run -d windows

# 在 Android 上运行
flutter run -d android

# 在 macOS 上运行
flutter run -d macos
```

### 内核设置
从 https://github.com/mapleafgo/cff-core/releases/latest 下载自定义内核，并将其放置在以下路径:
```
# 桌面端 (IPC 独立进程)
windows/core/singcast-core.exe
linux/core/singcast-core
macos/Frameworks/singcast-core

# 移动端 (FFI 原生库)
android/app/libs/libsingcast.aar
ios/Frameworks/libsingcast-darwin.xcframework
```

## 架构

### 核心组件
- **Singcast 内核**: 自定义的 sing-box 内核（支持 TUN 模式）
- **Flutter UI**: 主应用界面
- **桌面端 IPC**: 通过 JSON-RPC 2.0 与 singcast-core 独立进程通信
- **移动端 FFI**: 通过 MethodChannel 调用原生库
- **内核控制**: 管理 Singcast 内核的生命周期

### 主要模块
```
lib/
├── app/                 # 主应用代码
│   ├── bean/           # 数据模型
│   ├── component/      # UI 组件
│   ├── pages/          # 应用页面（主页、代理页、日志页、连接页、订阅页、设置页）
│   ├── source/         # 数据源和服务
│   └── utils/          # 工具类
├── main.dart           # 应用入口点
└── core_control.dart   # 内核管理
```

### 关键技术栈
- Flutter 3.16+ with Dart 3.2+
- Flutter Modular (导航)
- MobX (状态管理)
- Dio (网络请求)
- Tray Manager (系统托盘)
- Window Manager (窗口控制)
- Proxy Manager (系统代理设置)
- ffi (Dart-C 接口)

## 测试
- 运行标准 Flutter 测试: `flutter test`
- UI 测试文件: `test/widget_test.dart`
