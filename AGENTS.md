# Repository Guidelines

## Project Structure & Module Organization

- `lib/`：Flutter 源码。`core/` 为内核控制与 IPC，`data/local/` 为本地存储（`settings.json`、`config.json`），`domain/` 为领域模型，`presentation/` 为页面与组件，`services/` 为订阅、配置合并、托盘等应用服务，`utils/` 为常量与工具。
- `test/`：单元测试，按 `domain/services/utils/presentation` 分层组织。
- `android/`、`ios/`、`linux/`、`macos/`、`windows/`：各平台原生工程与内核二进制目录。
- `assets/`：图标与静态资源。

## Build, Test, and Development Commands

```bash
flutter pub get                                    # 安装依赖
dart run build_runner build --delete-conflicting-outputs  # 生成 .g.dart 等代码
flutter analyze                                   # 静态检查
flutter test                                      # 运行全部测试
dart format lib/ test/                            # 格式化 Dart 代码
flutter run -d linux                              # 本地运行 Linux 桌面版
```

桌面端内核放在 `linux/core/`、`windows/core/`、`macos/Frameworks/`；移动端对应 `android/app/libs/`、`ios/Frameworks/`。

## Coding Style & Naming Conventions

- 使用 Dart 默认 2 空格缩进，提交前运行 `dart format lib/ test/`。
- 类名用 `PascalCase`，文件、变量、函数用 `lowerCamelCase`，常量沿用现有 `Constants.xxx` 风格。
- 代码注释、文档、commit message 使用中文；变量名、函数名等标识符使用英文。
- 改动后必须通过 `flutter analyze`。

## Testing Guidelines

- 测试框架为 `flutter_test`，测试文件与 `test/` 分层对应。
- 用例名用中文描述行为，例如 `test('toJson 在默认值时也写入 rule-set-proxy', ...)`。
- 行为变更必须补充对应测试，本地全量验证使用 `flutter test`。

## Commit & Pull Request Guidelines

- 遵循 Conventional Commits，历史示例：`fix(storage): ...`、`feat(android): ...`、`docs: ...`、`ci: ...`。
- PR 说明改动目的、验证方式与影响范围；UI 改动附截图；涉及 issue 时用链接关联。

## 配置持久化规范

- `settings.json` 由 `lib/data/local/app_settings_storage.dart` 的 `AppStoredConfig.toJson` 序列化。
- `toJson` 必须无条件写入全部字段，包括 `null` 和默认值；禁止按“等于默认值”省略字段，也禁止对配置序列化使用 omitempty。
- 新增配置字段时必须同步补齐：`fromJson` 默认值、`toJson` 全字段写入、`copyWith`、`initAppConfig`/`_save` 消费链路，并在 `test/settings_storage_test.dart` 补默认值与非默认值用例。
