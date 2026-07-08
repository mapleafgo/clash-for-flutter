# 桌面端开机自启功能 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为桌面端（Windows / Linux / macOS）增加开机自启功能，开机后自动启动应用、恢复上次代理模式并连接，窗口隐藏到托盘。

**Architecture:** 通过 `launch_at_startup` 包注册系统自启项（附带 `--autostart` 参数）。启动时解析参数判断是否自启场景，据此隐藏窗口并在内核就绪后自动连接代理。`autoStart` 布尔设置持久化到 `settings.json`，信号化管理与现有设置一致。

**Tech Stack:** Flutter, launch_at_startup 0.5.1, signals_flutter, slang i18n, Swift (macOS LaunchAtLogin)

## Global Constraints

- 仅桌面端（`Constants.isDesktop` = Windows / macOS / Linux）执行，Android 不受影响
- `launch_at_startup` 已在 `pubspec.yaml` 声明（`^0.5.1`），无需新增依赖
- 现有 `main()` 签名为 `void main() async`，无 `arguments` 参数；`Platform.resolvedExecutable` 可用于获取可执行文件路径
- slang 基础语言为 `zh`（`build.yaml` 中 `base_locale: zh`），翻译文件在 `lib/i18n/` 目录
- 修改 `.i18n.json` 后须运行 `dart run build_runner build --delete-conflicting-outputs` 重新生成
- 代理模式选择 `tunIf`（`true` = TUN，`false` = 系统代理）已持久化
- 桌面端 TUN 需要提权，系统代理不需要提权
- `toggleTun(bool)` 和 `toggleSystemProxy(bool)` 定义在 `lib/services/core_config.dart`

---

## File Structure

| 文件 | 操作 | 职责 |
|---|---|---|
| `lib/data/local/app_settings_storage.dart` | 修改 | `AppStoredConfig` 新增 `autoStart` 字段 |
| `lib/services/app_config.dart` | 修改 | 新增 `autoStart` signal，加载与自动保存 |
| `lib/services/startup_service.dart` | 新建 | `initStartupService()` / `setAutoStart()` |
| `lib/i18n/zh.i18n.json` | 修改 | 新增 `autoStart` / `autoStartDesc` |
| `lib/i18n/en.i18n.json` | 修改 | 同上英文 |
| `lib/presentation/pages/settings_page.dart` | 修改 | 设置页新增开机自启开关 |
| `lib/main.dart` | 修改 | 参数解析、窗口隐藏、自动连接 |
| `macos/Runner/MainFlutterWindow.swift` | 修改 | LaunchAtLogin platform channel |
| `test/settings_storage_test.dart` | 新建 | `AppStoredConfig` 序列化测试 |

---

### Task 1: AppStoredConfig 新增 autoStart 字段

**Files:**
- Modify: `lib/data/local/app_settings_storage.dart`
- Test: `test/settings_storage_test.dart`

**Interfaces:**
- Produces: `AppStoredConfig.autoStart` (bool, 默认 false)，JSON 键 `"auto-start"`

- [ ] **Step 1: 编写失败的序列化测试**

创建 `test/settings_storage_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:singcast/data/local/app_settings_storage.dart';

void main() {
  group('AppStoredConfig autoStart', () {
    test('fromJson 默认值为 false', () {
      final config = AppStoredConfig.fromJson({});
      expect(config.autoStart, false);
    });

    test('fromJson 正确读取 auto-start', () {
      final config = AppStoredConfig.fromJson({'auto-start': true});
      expect(config.autoStart, true);
    });

    test('toJson 在 autoStart=true 时写入 auto-start', () {
      final config = AppStoredConfig.empty().copyWith(autoStart: true);
      final json = config.toJson();
      expect(json['auto-start'], true);
    });

    test('toJson 在 autoStart=false 时省略 auto-start', () {
      final config = AppStoredConfig.empty();
      final json = config.toJson();
      expect(json.containsKey('auto-start'), false);
    });

    test('copyWith 保留原值', () {
      final config = AppStoredConfig.empty().copyWith(autoStart: true);
      final copied = config.copyWith();
      expect(copied.autoStart, true);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/settings_storage_test.dart`
Expected: 编译失败，`autoStart` 字段不存在

- [ ] **Step 3: 实现 autoStart 字段**

在 `lib/data/local/app_settings_storage.dart` 的 `AppStoredConfig` 类中：

1. 在字段列表中（`locale` 之后）添加：

```dart
  final bool autoStart;
```

2. 在构造函数中（`this.locale,` 之后）添加：

```dart
    this.autoStart = false,
```

3. 在 `fromJson` 中（`locale: json['locale'] as String?,` 之后）添加：

```dart
        autoStart: json['auto-start'] as bool? ?? false,
```

4. 在 `toJson` 中（`if (locale != null) 'locale': locale,` 之后）添加：

```dart
        if (autoStart) 'auto-start': autoStart,
```

5. 在 `copyWith` 参数列表中（`String? locale,` 之后）添加：

```dart
    bool? autoStart,
```

6. 在 `copyWith` 的 `AppStoredConfig(` 构造中（`locale: locale ?? this.locale,` 之后）添加：

```dart
        autoStart: autoStart ?? this.autoStart,
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/settings_storage_test.dart`
Expected: 5 tests PASS

- [ ] **Step 5: 提交**

```bash
git add lib/data/local/app_settings_storage.dart test/settings_storage_test.dart
git commit -m "feat: AppStoredConfig 新增 autoStart 字段"
```

---

### Task 2: autoStart signal 与持久化

**Files:**
- Modify: `lib/services/app_config.dart`

**Interfaces:**
- Consumes: `AppStoredConfig.autoStart`（Task 1）
- Produces: `final autoStart = signal(false)` — 全局信号，供设置页和 startup service 使用

- [ ] **Step 1: 添加 autoStart signal**

在 `lib/services/app_config.dart` 中，`final autoCheckUpdate = signal(true);` 之后添加：

```dart
/// 开机自启动设置（仅桌面端有效）。
final autoStart = signal(false);
```

- [ ] **Step 2: 在 initAppConfig 中加载**

在 `initAppConfig()` 函数中，`autoCheckUpdate.value = stored.autoCheckUpdate;` 之后添加：

```dart
  autoStart.value = stored.autoStart;
```

- [ ] **Step 3: 在自动保存 effect 中订阅**

在 `_startAutoSave()` 的 `effect(() { ... })` 中，`autoCheckUpdate.value;` 之后添加：

```dart
    autoStart.value;
```

- [ ] **Step 4: 在 _save 中持久化**

在 `_save()` 函数中，`AppStoredConfig(` 构造参数中，`autoCheckUpdate: autoCheckUpdate.value,` 之后添加：

```dart
    autoStart: autoStart.value,
```

- [ ] **Step 5: 提交**

```bash
git add lib/services/app_config.dart
git commit -m "feat: autoStart signal 加载与持久化"
```

---

### Task 3: 启动服务 startup_service.dart

**Files:**
- Create: `lib/services/startup_service.dart`

**Interfaces:**
- Produces: `Future<void> initStartupService()` — 在 main 中调用，设置 launch_at_startup 的 appName/appPath/args
- Produces: `Future<void> setAutoStart(bool enabled)` — 开启或关闭系统自启项

- [ ] **Step 1: 创建 startup_service.dart**

创建 `lib/services/startup_service.dart`：

```dart
import 'dart:io';

import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:singcast/utils/constants.dart';

/// 初始化 launch_at_startup 插件，注册 appName / appPath / args。
///
/// 仅桌面端执行，在 main() 中调用一次。
/// args 携带 `--autostart` 标记，启动时用于判断是否为自启场景。
Future<void> initStartupService() async {
  if (!Constants.isDesktop) return;
  launchAtStartup.setup(
    appName: 'Singcast',
    appPath: Platform.resolvedExecutable,
    args: ['--autostart'],
  );
}

/// 开启或关闭开机自启。
///
/// 由设置页开关调用，实际注册/注销系统自启项。
/// 不修改 [autoStart] signal，调用方负责更新信号。
Future<void> setAutoStart(bool enabled) async {
  if (!Constants.isDesktop) return;
  if (enabled) {
    await launchAtStartup.enable();
  } else {
    await launchAtStartup.disable();
  }
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/services/startup_service.dart
git commit -m "feat: 新增 startup_service 管理开机自启注册"
```

---

### Task 4: 国际化文案

**Files:**
- Modify: `lib/i18n/zh.i18n.json`
- Modify: `lib/i18n/en.i18n.json`

**Interfaces:**
- Produces: `t.settings.autoStart` / `t.settings.autoStartDesc`

- [ ] **Step 1: 在 zh.i18n.json 中添加中文文案**

在 `lib/i18n/zh.i18n.json` 中，找到第 107 行 `"sectionAppearance": "外观",` 的前面（即第 106 行 `"autoCheckUpdateDesc": "应用启动时自动检查新版本",` 之后）插入两行：

```
    "autoStart": "开机自启",
    "autoStartDesc": "开机后自动启动并连接代理",
```

- [ ] **Step 2: 在 en.i18n.json 中添加英文文案**

在 `lib/i18n/en.i18n.json` 中，找到 `"autoCheckUpdateDesc": "Automatically check for new versions on startup",` 之后、`"sectionAppearance": "Appearance",` 之前，插入两行：

```
    "autoStart": "Launch at Startup",
    "autoStartDesc": "Automatically start and connect on boot",
```

- [ ] **Step 3: 重新生成 i18n 代码**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: 成功生成 `lib/i18n/strings.g.dart`，包含 `autoStart` / `autoStartDesc` 的 getter

- [ ] **Step 4: 验证生成结果**

Run: `grep -n "autoStart" lib/i18n/strings_zh.g.dart lib/i18n/strings_en.g.dart`
Expected: 两个文件中都包含 `autoStart` 和 `autoStartDesc` 的 getter

- [ ] **Step 5: 提交**

```bash
git add lib/i18n/zh.i18n.json lib/i18n/en.i18n.json lib/i18n/strings.g.dart lib/i18n/strings_zh.g.dart lib/i18n/strings_en.g.dart
git commit -m "i18n: 新增开机自启文案"
```

---

### Task 5: 设置页开关

**Files:**
- Modify: `lib/presentation/pages/settings_page.dart`

**Interfaces:**
- Consumes: `autoStart` signal（Task 2）
- Consumes: `setAutoStart()`（Task 3）
- Consumes: `t.settings.autoStart` / `t.settings.autoStartDesc`（Task 4）

- [ ] **Step 1: 添加 import**

在 `lib/presentation/pages/settings_page.dart` 的 import 区域，`import 'package:singcast/services/app_config.dart';` 之后添加：

```dart
import 'package:singcast/services/startup_service.dart';
```

- [ ] **Step 2: 在 sectionGeneral 分区添加开关**

在 `build` 方法的 ListView 中，找到 `_Section(t.settings.sectionGeneral)` 之后、`const _UaTile()` 之前。在该位置（`_Section` 之后第一个子组件之前）插入：

```dart
          if (Constants.isDesktop)
            l10nBuilder((context) {
              return SwitchListTile(
                title: Text(t.settings.autoStart),
                subtitle: Text(t.settings.autoStartDesc),
                value: autoStart.value,
                onChanged: (v) async {
                  try {
                    await setAutoStart(v);
                    autoStart.value = v;
                  } catch (e) {
                    // 注册失败，signal 不更新，开关回弹
                  }
                },
              );
            }),
```

注意：`Constants` 和 `autoStart` 已在文件顶部 import 的模块中可用（`Constants` 来自 `package:singcast/utils/constants.dart`，已导入；`autoStart` 来自 `package:singcast/services/app_config.dart`，已导入）。

- [ ] **Step 3: 验证编译**

Run: `flutter analyze lib/presentation/pages/settings_page.dart`
Expected: 无错误

- [ ] **Step 4: 提交**

```bash
git add lib/presentation/pages/settings_page.dart
git commit -m "feat: 设置页新增开机自启开关"
```

---

### Task 6: main.dart 参数解析与窗口隐藏

**Files:**
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: `initStartupService()`（Task 3）
- Produces: `autoStartFromArgs` 布尔值（传递给 Task 7 的自动连接逻辑）

- [ ] **Step 1: 修改 main 签名并解析参数**

将 `lib/main.dart` 第 22 行的函数签名：

```dart
void main() async {
```

改为：

```dart
void main(List<String> arguments) async {
```

在 `WidgetsFlutterBinding.ensureInitialized();` 之后添加：

```dart
  autoStartFromArgs = arguments.contains('--autostart');
```

注意：`autoStartFromArgs` 是文件级 `late` 变量（Step 1a 声明），因为 `_initApp()` 是独立函数，需要跨函数访问该值。

- [ ] **Step 1a: 添加文件级 autoStartFromArgs 变量**

在 `lib/main.dart` 中，`void main` 函数之前（`_log` 函数定义附近）添加：

```dart
/// 标记应用是否通过开机自启启动（命令行携带 --autostart 参数）。
late bool autoStartFromArgs;
```
```

- [ ] **Step 2: 在桌面分支调用 initStartupService 并条件隐藏窗口**

在 `main()` 函数中，`if (Constants.isDesktop) {` 分支内，将 `waitUntilReadyToShow` 回调：

```dart
      () async {
        await windowManager.show();
      },
```

改为：

```dart
      () async {
        if (!autoStartFromArgs) {
          await windowManager.show();
        }
        // 自启场景：不 show()，窗口保持隐藏到托盘
      },
```

- [ ] **Step 3: 调用 initStartupService**

在 `main()` 中找到第二个 `if (Constants.isDesktop)` 块（包含 `await initTray();` 的那个），在 `await initTray();` 之后添加：

```dart
    await initStartupService();
```

并在文件顶部添加 import：

```dart
import 'package:singcast/services/startup_service.dart';
```

- [ ] **Step 4: 验证编译**

Run: `flutter analyze lib/main.dart`
Expected: 无错误

- [ ] **Step 5: 提交**

```bash
git add lib/main.dart
git commit -m "feat: main.dart 参数解析、窗口隐藏与自启服务初始化"
```

---

### Task 7: 自动连接代理逻辑

**Files:**
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: `autoStartFromArgs`（Task 6）
- Consumes: `toggleTun(bool)` / `toggleSystemProxy(bool)` — 定义在 `lib/services/core_config.dart`（已导入）
- Consumes: `tunIf` signal — 定义在 `lib/services/app_config.dart`（已导入）
- Consumes: `LogLevel` — 定义在 `lib/domain/enums.dart`

- [ ] **Step 1: 修改桌面端 onProcessReady 回调**

在 `lib/main.dart` 的 `_initApp()` 函数中，找到 `else` 分支（桌面端）的 `onProcessReady` 赋值：

```dart
    LibCore.instance.onProcessReady = () async {
      if (selectedFile.value != null) await asyncProfile();
    };
```

替换为：

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

- [ ] **Step 2: 确认 LogLevel 已导入**

检查 `lib/main.dart` 顶部是否有 `import 'package:singcast/domain/enums.dart';`。如果没有，添加：

```dart
import 'package:singcast/domain/enums.dart';
```

注意：`tunIf` 和 `toggleTun` / `toggleSystemProxy` 来自已导入的 `app_config.dart` 和 `core_config.dart`，无需额外 import。

- [ ] **Step 3: 验证编译**

Run: `flutter analyze lib/main.dart`
Expected: 无错误

- [ ] **Step 4: 提交**

```bash
git add lib/main.dart
git commit -m "feat: 开机自启时自动连接上次代理模式"
```

---

### Task 8: macOS 原生 LaunchAtLogin 集成

**Files:**
- Modify: `macos/Runner/MainFlutterWindow.swift`
- Modify: `macos/Runner.xcodeproj/project.pbxproj`（通过 Xcode SPM 操作）

**Interfaces:**
- 无 Dart 层接口变更，此任务使 `launch_at_startup` 包的 macOS platform channel 正常工作

- [ ] **Step 1: 修改 MainFlutterWindow.swift**

将 `macos/Runner/MainFlutterWindow.swift` 的完整内容替换为：

```swift
import Cocoa
import FlutterMacOS
import LaunchAtLogin
import window_manager

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController.init()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    FlutterMethodChannel(
      name: "launch_at_startup",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    .setMethodCallHandler { (_ call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "launchAtStartupIsEnabled":
        result(LaunchAtLogin.isEnabled)
      case "launchAtStartupSetEnabled":
        if let arguments = call.arguments as? [String: Any] {
          LaunchAtLogin.isEnabled = arguments["setEnabledValue"] as! Bool
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }
}
```

- [ ] **Step 2: 在 Xcode 中添加 LaunchAtLogin SPM 依赖**

此步骤需要在 macOS 环境下使用 Xcode 操作：

1. 用 Xcode 打开 `macos/Runner.xcodeproj`
2. 选中 `Runner` 项目 → `Package Dependencies` 标签页
3. 点击 `+`，输入 URL：`https://github.com/sindresorhus/LaunchAtLogin-Objective-C`
4. 版本规则选择 `Up to Next Major`，最小版本 `1.2.0`
5. Add Package 后，将 `LaunchAtLogin` 产品添加到 `Runner` target

- [ ] **Step 3: 验证 macOS 构建（需 macOS 环境）**

Run: `flutter build macos`
Expected: 构建成功，无编译错误

- [ ] **Step 4: 提交**

```bash
git add macos/Runner/MainFlutterWindow.swift macos/Runner.xcodeproj/project.pbxproj
git commit -m "feat: macOS 集成 LaunchAtLogin 原生模块"
```

---

### Task 9: 全量验证

**Files:**
- 无文件改动

- [ ] **Step 1: 运行全部测试**

Run: `flutter test`
Expected: 全部通过

- [ ] **Step 2: 运行静态分析**

Run: `flutter analyze`
Expected: 无错误

- [ ] **Step 3: 手动验证（在 Linux 开发机上）**

1. `flutter run -d linux` 启动应用
2. 进入 设置 → 通用 → 开机自启，打开开关
3. 检查 `~/.config/autostart/` 下是否生成了 `.desktop` 文件
4. 关闭开关，确认文件被删除
5. 重新打开应用（不附带 `--autostart`），确认窗口正常显示、代理不自动连接

- [ ] **Step 4: 验证 --autostart 参数行为**

Run: 修改应用的运行配置，添加 `--autostart` 程序参数后启动
Expected: 窗口不显示，应用在后台运行；有配置文件时自动连接代理

- [ ] **Step 5: 最终提交（如有修复）**

```bash
git add -A
git commit -m "fix: 全量验证修复" || echo "无需修复"
```
