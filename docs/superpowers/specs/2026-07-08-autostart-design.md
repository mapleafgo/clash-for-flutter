# 桌面端开机自启功能设计

## 概述

为 Singcast 桌面端（Windows / Linux / macOS）增加开机自启功能。开机后自动启动应用、恢复上次的代理模式（TUN 或系统代理）并连接代理，窗口最小化到系统托盘。用户可在设置中开关此功能。

Android 不在本次范围内。

## 背景

- `pubspec.yaml` 已引入 `launch_at_startup: ^0.5.1`（2025-04-01 发布），代码中完全未使用。
- 该包是各平台原生自启机制的薄封装：Windows 注册表、Linux `.desktop` 文件、macOS LaunchAgents。底层 OS 机制未变，包可用。
- macOS 端需要在 Xcode 项目中集成 `LaunchAtLogin` Swift 包（SPM 依赖），否则原生 channel 不可用。
- 代理开关状态（TUN / 系统代理）当前不持久化，每次启动需手动开启。代理模式选择（`tunIf`）已持久化。
- 桌面端 TUN 模式需要提权（Windows UAC / macOS 授权），系统代理模式不需要提权。

## 设计

### 数据流

```
设置开关 ON
  → setAutoStart(true) → launchAtStartup.enable()
  → 系统重启
  → OS 启动应用（附带 --autostart 参数）
  → main() 解析参数 → 窗口隐藏
  → onProcessReady 回调 → 按 tunIf 自动连接代理
  → 应用静默运行在托盘
```

### 1. 数据与状态层

**存储字段**

在 `AppStoredConfig`（`lib/data/local/app_settings_storage.dart`）新增字段：

- `bool autoStart` — 默认 `false`，持久化到 `settings.json` 的 `"auto-start"` 键。

JSON 序列化遵循现有模式：默认值时省略键（`if (!autoStart) 'auto-start': autoStart`）。

**全局 Signal**

在 `lib/services/app_config.dart` 新增：

```dart
final autoStart = signal(false);
```

- `initAppConfig()` 中从 `stored.autoStart` 加载。
- `_startAutoSave()` 的 effect 订阅列表中加入 `autoStart.value`，自动持久化。

模式与现有 `autoCheckUpdate` 完全一致。

### 2. 设置 UI

在 `lib/presentation/pages/settings_page.dart` 的"通用"分区（`sectionGeneral`）新增 `SwitchListTile`，位于 `autoCheckUpdate` 之前：

```dart
if (Constants.isDesktop)
  SwitchListTile(
    title: Text(t.settings.autoStart),
    subtitle: Text(t.settings.autoStartDesc),
    value: autoStart.value,
    onChanged: (v) async {
      await setAutoStart(v);
      autoStart.value = v;
    },
  ),
```

`onChanged` 先调用 `setAutoStart(v)` 注册/注销系统自启项，成功后更新 signal。注册失败时异常会向上传播，由调用方处理（signal 不更新，开关回弹）。

**国际化**

在 `zh.i18n.json` 和 `en.i18n.json` 的 `settings` 下新增：

| 键 | 中文 | English |
|---|---|---|
| `autoStart` | 开机自启 | Launch at Startup |
| `autoStartDesc` | 开机后自动启动并连接代理 | Automatically start and connect on boot |

### 3. 自启注册层

新增 `lib/services/startup_service.dart`：

```dart
import 'dart:io';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:singcast/utils/constants.dart';

/// 初始化 launch_at_startup。仅在桌面端执行。
/// 在 main() 中调用，用于注册自启项的 appName / appPath / args。
Future<void> initStartupService() async {
  if (!Constants.isDesktop) return;
  launchAtStartup.setup(
    appName: 'Singcast',
    appPath: Platform.resolvedExecutable,
    args: ['--autostart'],
  );
}

/// 开启或关闭开机自启。
Future<void> setAutoStart(bool enabled) async {
  if (!Constants.isDesktop) return;
  if (enabled) {
    await launchAtStartup.enable();
  } else {
    await launchAtStartup.disable();
  }
}
```

`initStartupService()` 在 `main()` 的 `Constants.isDesktop` 分支中调用，与 `initTray()` 同级。

### 4. 场景检测

**命令行参数解析**

`main()` 签名改为 `void main(List<String> arguments)`。在函数最开头检测：

```dart
final autoStartFromArgs = arguments.contains('--autostart');
```

不引入额外依赖，纯字符串匹配。

**窗口隐藏**

在 `main()` 的桌面分支 `waitUntilReadyToShow` 回调中：

```dart
await windowManager.waitUntilReadyToShow(
  const WindowOptions(...),
  () async {
    if (!autoStartFromArgs) {
      await windowManager.show();
    }
    // 自启场景：不调用 show()，窗口保持隐藏
  },
);
```

用户通过托盘图标点击恢复窗口。

### 5. 自动连接代理

**钩入点：`onProcessReady` 回调**

桌面端内核进程就绪后触发 `onProcessReady`。此时配置已加载、`selectedFile` 已就绪。

当前代码：
```dart
LibCore.instance.onProcessReady = () async {
  if (selectedFile.value != null) await asyncProfile();
};
```

改为：
```dart
LibCore.instance.onProcessReady = () async {
  if (selectedFile.value == null) return;
  if (autoStartFromArgs) {
    try {
      if (tunIf.value == true) {
        await toggleTun(true);
      } else {
        await toggleSystemProxy(true);
      }
    } catch (e) {
      // TUN 提权失败等情况：记录日志，不崩溃，保持托盘运行
      LogFileWriter.instance?.log(
        '开机自启连接代理失败: $e',
        level: LogLevel.error,
        name: 'autostart',
      );
    }
  } else {
    await asyncProfile();
  }
};
```

**TUN 提权处理**

系统重启后特权服务未运行，TUN 模式需要提权：
- Windows：触发 UAC 提示
- macOS：触发授权弹窗
- Linux：需要 pkexec 或 polkit

这是预期行为。如果用户拒绝提权或提权失败，捕获异常、记录日志、应用继续在托盘运行。不静默降级到系统代理模式——用户明确选择了 TUN，不应擅自更改。用户可从托盘菜单手动重试。

### 6. macOS 原生集成

修改 `macos/Runner/MainFlutterWindow.swift`，集成 `LaunchAtLogin` Swift 包：

1. 在 Xcode 项目中通过 SPM 添加 `LaunchAtLogin-Objective-C` 依赖（从 `https://github.com/sindresorhus/LaunchAtLogin-Objective-C`）
2. 在 `MainFlutterWindow.swift` 中添加 platform channel：

```swift
import LaunchAtLogin

// 在 awakeFromNib 中：
FlutterMethodChannel(
  name: "launch_at_startup",
  binaryMessenger: flutterViewController.engine.binaryMessenger
).setMethodCallHandler { (call, result) in
  switch call.method {
  case "launchAtStartupIsEnabled":
    result(LaunchAtLogin.isEnabled)
  case "launchAtStartupSetEnabled":
    if let args = call.arguments as? [String: Any] {
      LaunchAtLogin.isEnabled = args["setEnabledValue"] as! Bool
    }
    result(nil)
  default:
    result(FlutterMethodNotImplemented)
  }
}
```

这是 `launch_at_startup` 包文档要求的 macOS 集成步骤。

## 边界情况

| 场景 | 处理 |
|---|---|
| 开启自启但无配置文件 | 应用启动隐藏到托盘，不连接代理，用户需手动打开窗口添加配置 |
| TUN 模式提权失败 | 记录日志，应用保持托盘运行，用户手动重试 |
| 手动打开应用（无 --autostart） | 正常流程：显示窗口，不自动连接 |
| 用户卸载应用 | OS 自启项变为失效引用，Windows / macOS 自动清理，Linux `.desktop` 文件随卸载移除 |
| `launchAtStartup.isEnabled()` 与 signal 不一致 | 以 signal 为准，设置页开关反映 signal 状态 |

## 测试策略

- **单元测试**：`AppStoredConfig` 序列化/反序列化包含 `autoStart` 字段的往返测试
- **手动测试（每平台）**：
  1. 设置中开启开机自启 → 重启系统 → 验证应用自动启动、窗口隐藏、代理连接
  2. TUN 模式下重启 → 验证提权提示后代理连接
  3. 系统代理模式下重启 → 验证静默连接
  4. 托盘点击恢复窗口 → 验证窗口正常显示
  5. 关闭开机自启 → 重启系统 → 验证应用不自动启动

## 涉及文件

| 文件 | 改动 |
|---|---|
| `lib/data/local/app_settings_storage.dart` | `AppStoredConfig` 新增 `autoStart` 字段 |
| `lib/services/app_config.dart` | 新增 `autoStart` signal，加载与持久化 |
| `lib/services/startup_service.dart` | **新增** — `initStartupService()` / `setAutoStart()` |
| `lib/presentation/pages/settings_page.dart` | 新增开机自启 SwitchListTile |
| `lib/main.dart` | 参数解析、窗口隐藏、自动连接逻辑 |
| `lib/i18n/zh.i18n.json` | 新增 `autoStart` / `autoStartDesc` |
| `lib/i18n/en.i18n.json` | 同上英文 |
| `macos/Runner/MainFlutterWindow.swift` | LaunchAtLogin 原生集成 |
| `macos/Runner.xcodeproj/project.pbxproj` | SPM 依赖配置（Xcode 操作） |
