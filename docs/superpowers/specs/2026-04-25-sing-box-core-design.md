# sing-box 内核迁移设计

**日期**: 2026-04-25
**状态**: 草稿
**影响范围**: 内核引擎、FFI 层、配置系统、全平台

## 背景

clash-for-flutter 当前使用 cff-core，基于原版 Dreamacro/Clash (v1.18.0)。该内核**不支持** VLESS、REALITY、Hysteria2 等现代代理协议。当用户导入仅包含 VLESS+REALITY 节点的订阅时，内核会静默跳过所有代理节点，导致 proxy-groups 引用不存在的条目，最终触发 400 错误。

## 决策

用 sing-box 替换 cff-core 作为代理引擎。sing-box 支持所有现代协议（VLESS、REALITY、Hysteria2、TUIC 等），并提供 `libbox` —— 一个可直接嵌入的 FFI 库。

## 架构

### FlClash 风格纯 FFI

参照 FlClash 的成熟架构：Flutter 与 Go 内核之间**仅通过 FFI 调用通信**，不使用 HTTP REST API。所有数据以 JSON 字符串形式通过 FFI 函数调用传递。

```
┌─────────────────────────────────────────────┐
│                  Flutter UI                  │
│       (Signals 状态管理、Widgets、Pages)       │
└──────────────┬──────────────────────────────┘
               │ dart:ffi (JSON 字符串)
               ▼
┌─────────────────────────────────────────────┐
│             Go 桥接层 (hub.go)               │
│  ┌───────────────────────────────────────┐   │
│  │          配置翻译器                     │   │
│  │   mihomo YAML ──► sing-box JSON        │   │
│  └───────────────────────────────────────┘   │
│  ┌───────────────────────────────────────┐   │
│  │      sing-box 引擎 (libbox)            │   │
│  └───────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

### 为什么选纯 FFI 而非 HTTP REST

| 维度 | 纯 FFI | HTTP REST |
|------|--------|-----------|
| 延迟 | 零延迟（进程内调用） | 网络开销 |
| 可靠性 | 无端口冲突 | 依赖端口可用性 |
| 复杂度 | 单次 FFI 调用 | HTTP 服务器生命周期管理 |
| 验证 | FlClash 已验证此方案 | mihomo 使用此方案 |
| 移动端适配 | 无需 socket | 需要 localhost 绑定 |

## FFI 接口

### 导出函数（Go → C）

```go
// 生命周期
export fn CoreInit(homeDir: *const c_char) -> c_int
export fn CoreStart(configPath: *const c_char) -> c_int
export fn CoreStop() -> c_int
export fn CoreClose()

// 配置管理
export fn CoreLoadConfig(yamlPath: *const c_char) -> c_int   // 自动检测并翻译
export fn CoreReloadConfig() -> c_int

// 查询（返回 JSON 字符串，调用方负责释放内存）
export fn CoreQueryProxies() -> *const c_char                  // 所有代理组和节点
export fn CoreQueryConnections() -> *const c_char              // 当前连接列表
export fn CoreQueryTraffic() -> *const c_char                  // 流量增量快照
export fn CoreQueryLogs() -> *const c_char                     // 最近日志条目

// 操作
export fn CoreSelectProxy(group: *const c_char, tag: *const c_char) -> c_int
export fn CoreCloseConnection(id: *const c_char) -> c_int
export fn CoreCloseAllConnections() -> c_int
export fn CoreTestDelay(name: *const c_char, url: *const c_char) -> c_int  // 毫秒，-1 表示错误
export fn CoreGetVersion() -> *const c_char
```

### Dart 侧

```dart
class CoreControl {
  static DynamicLibrary? _lib;

  static Future<void> init(String homeDir) async { ... }
  static Future<void> start(String configPath) async { ... }
  static Future<void> stop() async { ... }
  static Future<String> queryProxies() async { ... }
  static Future<void> selectProxy(String group, String tag) async { ... }
}
```

### 流式数据

流量、日志和连接数据使用 Go→Dart 回调模式。Go 桥接层自行实现事件循环——订阅 sing-box/libbox 的内部事件接口，通过注册的 C 函数指针将数据转发给 Flutter。

```go
export fn CoreSetCallback(cb: extern fn(eventType: c_int, data: *const c_char))
```

```dart
typedef CoreCallback = Void Function(Int32 eventType, Pointer<Utf8> data);
// eventType: 0=流量, 1=日志, 2=连接
```

> 注：libbox 的具体订阅机制（通过 `box.PlatformInterface` 还是直接 channel 订阅）将在 Phase 1 实现阶段检查 libbox API 后确定。

## 配置翻译器

### 策略

Go 桥接层自动检测配置格式并进行翻译：

1. **mihomo YAML** → 使用 `gopkg.in/yaml.v3` 解析 → 翻译 → 输出 sing-box JSON → 传给 libbox
2. **sing-box JSON** → 直接透传，不做处理
3. **格式检测**：先尝试解析为 JSON，若失败则视为 YAML

翻译器是**单向管道**：mihomo YAML → sing-box JSON，不做反向翻译。

### 映射参考

所有字段级别的映射已记录在 `docs/mihomo-singbox-config-mapping.md`（版本基线：mihomo v1.19.24 ↔ sing-box v1.13.11）。

核心翻译规则：
- `name` → `tag`（代理、分组、DNS 规则）
- `port` → `server_port`
- `cipher` → `method`（Shadowsocks）
- `type: ss` → `type: "shadowsocks"`
- `type: vmess` → `type: "vmess"`（不变）
- 秒数（int） → Go Duration 字符串（`"30s"`）
- `skip-cert-verify: true` → `insecure: true`
- 代理组：`type: Select` → `type: "selector"`、`type: URLTest` → `type: "urltest"`
- 规则：`DOMAIN-SUFFIX,google.com,Proxy` → `{ "domain_suffix": ["google.com"], "outbound": "Proxy" }`

### 不支持字段的降级处理

当 mihomo 字段在 sing-box 中无对应项时（如 Snell 协议、`authentication`、`tunnels`）：
- 翻译时记录警告日志
- 优雅跳过该字段
- **不得**导致整个配置加载失败

## Flutter 侧变更

### 需要改动的组件

| 组件 | 改动前 | 改动后 |
|------|--------|--------|
| `core_control.dart` | FFI 调用 cff-core | FFI 调用 sing-box 桥接层 |
| `clash_api.dart` | HTTP REST 客户端（Dio） | 通过 CoreControl 调用 FFI |
| `ws_streams.dart` | WebSocket 流 | FFI 回调 |
| `app_config.dart` | HTTP PATCH 配置 | FFI CoreReloadConfig |
| `clash_generated_bindings.dart` | cff-core 绑定 | sing-box 桥接层绑定 |

### 保持不变的组件

| 组件 | 原因 |
|------|------|
| UI 页面 | 视觉设计不变 |
| Signals 状态管理 | 仍用于响应式 UI |
| 订阅管理 | 基于文件、格式无关 |
| 订阅下载 | YAML 下载逻辑不变 |
| 设置页面 | 大部分设置可映射到 sing-box 对应项 |

### ClashApi 重构

`ClashApi` 从 HTTP 客户端变为 FFI 调用的薄封装层：

```dart
class ClashApi {
  Future<void> hello() async => CoreControl.init(homeDir);

  Future<Map<String, dynamic>> getProxies() async {
    final json = CoreControl.queryProxies();
    return jsonDecode(json);
  }

  Future<bool> selectProxy({required String group, required String tag}) async {
    return CoreControl.selectProxy(group, tag) == 0;
  }
}
```

保留 `ClashApi` 类名以减少代码变动量，但移除所有 HTTP 内部实现。

## 平台支持

全平台通过 gomobile 交叉编译支持：

| 平台 | 产物 | 路径 |
|------|------|------|
| Linux | `libclash.so` | `linux/core/` |
| Windows | `libclash.dll` | `windows/core/` |
| macOS | `libclash.dylib` | `macos/Frameworks/` |
| Android | `libclash.aar` | `android/app/libs/` |
| iOS | `libclash.xcframework` | `ios/Frameworks/` |

## 构建流程

```
Go 源码 (hub.go + 翻译器)
    │
    ├─ gomobile bind ──► .aar / .xcframework（移动端）
    ├─ go build -buildmode=c-shared ──► .so / .dll / .dylib（桌面端）
    │
    ▼
Flutter 资源 ──► 各平台指定路径
```

## 迁移阶段

### Phase 1: 内核与配置
- Go 桥接层 + 配置翻译器
- Dart FFI 绑定
- CoreControl 重写
- 基本生命周期（初始化、启动、停止）

### Phase 2: 数据层
- ClashApi → FFI 封装
- WebSocket 流 → FFI 回调
- 代理、连接、日志、流量数据

### Phase 3: UI 集成
- 代理页（分组选择、延迟测试）
- 连接页
- 日志页
- 设置页（验证所有字段可用）

### Phase 4: 平台与完善
- 跨平台构建
- TUN 模式配置
- 边界情况与错误处理
- 测试

## 风险与缓解

| 风险 | 缓解措施 |
|------|----------|
| 配置翻译遗漏 | 完整映射文档 + 降级日志 |
| FFI 内存管理 | Go 分配，Dart 通过显式 free() 释放 |
| 平台特定 TUN | 按平台条件化配置字段 |
| gomobile ABI 稳定性 | 锁定 sing-box 版本，逐平台测试 |
| 影响现有用户 | 翻译器兼容所有 mihomo YAML 配置 |
