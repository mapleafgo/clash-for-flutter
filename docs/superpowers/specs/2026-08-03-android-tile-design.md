# 安卓快速设置磁贴（VPN 快捷开关）设计

版本：v1.0
日期：2026-08-03
状态：已确认

## 背景与目标

singcast 是 Flutter + Go 内核（sing-box）的多端 Clash 客户端。Android 侧已有
原生 `SingcastVpnService`（`VpnService`）负责 VPN 建连/断开，`MainActivity`
通过 MethodChannel 承接 Flutter 的启停请求。用户希望在没有 App 界面参与的情况
下，从系统的快速设置磁贴直接开/关 VPN。

目标：

1. 在通知栏快速设置上提供一个磁贴，点按直接连接 VPN，再点按断开并回到
   "完全直连"（内核停止，不复用通知栏那套回退非 VPN 代理的逻辑）。
2. 磁贴仅图标，用着色/图标切换表示 已连接 / 未连接；不显示文字。
3. 磁贴挂起时点按**不拉起 App**（首次 VPN 授权除外，见错误处理）。
4. 长按磁贴进入 App 首页（`MainActivity`）。
5. 复用现有原生 VPN 能力，不改 Flutter/Go 内核。

非目标：

- 不做磁贴自动添加（不做 `requestAddTileService`），各版本磁贴均靠用户手动加入。
- 不做设置页的"显示磁贴"开关。
- 不为磁贴新增任何 SharedPreferences 配置字段（建连要素全部从既有文件读取）。
- 不动语言（`appLocale` 已持久化在 `settings.json`，磁贴仅图标无文字）。

## 模型

磁贴是原生 `TileService`，直接驱动现有 `SingcastVpnService`。

| 项 | 取值 |
|---|---|
| 磁贴类型 | 快速设置静态磁贴（`TileService`） |
| 最低版本 | `minSdk 34`（Android 14），磁贴 API 24+ 可用，14 及以上默认可用 |
| 连接动作 | 原生读配置 → `ACTION_CONNECT` 启 `SingcastVpnService` |
| 断开动作 | 原生调 `disconnect`（内部 `stopCore` + `stopForeground`）→ `stopService` |
| 状态来源 | `SingcastVpnService.isServiceRunning` |

### 建连要素来源（不新增持久化字段）

| 要素 | 读取位置 |
|---|---|
| `configContent` | `context.filesDir/cache-tun.json`（Flutter 每次 TUN 启动时写入的专用缓存，关闭 VPN 不覆盖） |
| `ipv6` | `cache-tun.json` 的 `dns.strategy == 'prefer_ipv6'` |
| `ruleSetProxy` | `context.filesDir/settings.json` 的 `ruleSetProxy` 字段 |

## 组件

新增两个原生组件，并复用现有原生能力：

- **`SingcastTileService.kt`（新增）**：继承 `TileService`。
  - `onStartListening` / `onStopListening`：按 `SingcastVpnService.isServiceRunning`
    切换磁贴图标着色（已连接 / 未连接）。
  - `onTileAdded`：设置初始状态。
  - `onClick`：进入连接/断开逻辑（见数据流）。
  - 长按：默认进入 App（manifest 中磁贴 meta-data 声明指向 `MainActivity`）。
- **`VpnPermissionActivity.kt`（新增）**：极轻量透明 Activity，承载
  `VpnService.prepare()` 授权弹窗结果；授权成功读到配置后用 `ACTION_CONNECT`
  启动 `SingcastVpnService`，随后 `finish()`，不展示 App 界面。仅首次或授权
  被撤销时短暂出现。
- **原生配置读取封装**：读取 `cache-tun.json` 与 `settings.json` 组装建连
  参数，返回 `configContent / ipv6 / ruleSetProxy` 的纯函数，便于 JVM 单测。

## 数据流

### 连接（点按，当前未连接）

1. `onClick` 读 `SingcastVpnService.isServiceRunning`；`false` 走连接。
2. 判定 `VpnService.prepare(this)`：
   - 非 null（未授权）：启动透明 `VpnPermissionActivity` 走 `prepare` 授权弹窗；
     `RESULT_OK` 后读取配置并以 `ACTION_CONNECT` 启动 `SingcastVpnService`，
     随后 `finish()`。
   - null（已授权）：直接读取配置并以 `ACTION_CONNECT` 启动 `SingcastVpnService`。

### 断开（点按，当前已连接）

1. `onClick` 读 `isServiceRunning`；`true` 走断开。
2. 直接调 `SingcastVpnService.disconnect(reason)`（内部 `stopCore` +
   `stopForeground`，= 完全直连），再 `stopService` 收尾。

### 状态同步

- `onStartListening` / `onStopListening` 按 `isServiceRunning` 刷新磁贴着色。
- 在 App 里连接/断开后，磁贴下次下拉经 `onStartListening` 自动对齐。

## 错误处理

- **无可用配置**（`cache-tun.json` 不存在、无 `tun` inbound 或解析失败）：
  点按仅 `showToast` 提示"请先在应用内开启 VPN"，不操作 VPN。
- **VPN 授权被撤销/拒绝**：`VpnService.prepare` 返回非 null 时重新走授权中转；
  用户拒绝则直接收起磁贴面板，不反复打扰。
- **内核启动失败**：`SingcastVpnService` 建连抛错时其 `disconnect`
  （`core_start_failed`）已兜底 `stopCore`；磁贴下轮刷新回"未连接"态，出错留痕到
  `AppLog`。
- **重复点按/并发**：`SingcastVpnService.connect` 已有 `running.compareAndSet`
  幂等保护；磁贴点按先查 `isServiceRunning`，重复触发自然去重。

## 平台兼容

- `minSdk 34`（Android 14）已覆盖快速设置磁贴与 `startActivityAndCollapse(PendingIntent)` 所需最低版本。
- 静态磁贴（无需手动编辑页加入）是 Android 13+ 特性，但本设计**不做自动添加**，
  因此 12/13+ 统一要求用户在快速设置编辑页手动将磁贴加入。

## 相关改动：`ruleSetProxy` 持久化修复

现状 `ruleSetProxy` 仅存在于内存 signal（`app_config.dart`），未写入
`settings.json`——用户自定义的 rule-set 代理在重启后被重置为默认值，属于现存
bug。作为本特性的前置修复，将其按 `subUA` 的同样方式持久化：

- `AppStoredConfig` 增加 `ruleSetProxy` 字段（`app_settings_storage.dart`）。
- `initAppConfig` 从 `settings.json` 读回并赋值 `ruleSetProxy.value`
  （`app_config.dart`）。
- `_save` 写入 `ruleSetProxy`，`_startAutoSave` 的 effect 跟踪它。

该改动同时为磁贴提供 `settings.json` 中的 `ruleSetProxy` 来源。

## 测试

1. 原生 JVM 单测：`cache-tun.json` 解析出 `configContent`；
   `dns.strategy` ↔ `ipv6` 映射；`settings.json` 缺/有 `ruleSetProxy` 的取值。
2. Flutter 测试：`ruleSetProxy` 的 `initAppConfig` 读回与 `_save` 写回
   （对齐 `subUA` 既有测试写法）。
3. 真机/模拟器手动验证：点按连接、再点断开直连、首次授权弹窗、无配置点按仅
   提示、长按进应用、断开后状态图标刷新。

## 涉及范围

- `singcast` GUI：`lib/data/local/app_settings_storage.dart`、
  `lib/services/app_config.dart`（`ruleSetProxy` 持久化）。
- `singcast` Android 原生：新增 `SingcastTileService.kt`、
  `VpnPermissionActivity.kt`，扩展 `SingcastVpnService` 启停复用，修改
  `AndroidManifest.xml`，新增磁贴图标资源。
- `singcast-cli` / `sing-box`：不改。
