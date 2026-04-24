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

### 资源文件翻译策略

mihomo 配置中的 `GEOIP`/`GEOSITE` 规则不引用外部文件，直接使用内置 GeoData。sing-box 没有内置 GeoData，必须通过 rule-set 引用。

翻译器需要维护一个**内置映射表**，将常用的 GeoIP/GeoSite 名称映射到远程 rule-set URL：

```
GEOIP,CN      → rule_set: {tag:"geoip-cn", type:"remote", format:"binary",
                           url:"https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs"}
GEOSITE,google → rule_set: {tag:"geosite-google", type:"remote", format:"binary",
                            url:"https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-google.srs"}
```

对于映射表中不存在的名称，翻译器应生成一条警告并跳过该规则。

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
| 系统代理管理 | 已有 `proxy_manager` 逻辑，sing-box 不管理此部分 |

### 设置页面变更

| 功能 | 处理方式 |
|------|----------|
| 端口配置（Mixed/Redir/TProxy） | 保留，映射到 sing-box inbound |
| 允许局域网 | 保留，映射到 inbound `listen` 地址 |
| IPv6 | 保留，映射到 DNS strategy |
| 代理模式 | 保留，映射到 sing-box route default mode |
| 日志等级 | 保留，直接映射 |
| MMDB URL / 刷新 MMDB | **移除**，sing-box 不使用 MMDB |
| 延迟测试 URL | 保留 |
| 订阅 User-Agent | 保留，订阅下载不受内核影响 |

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

## 内核差异要点

以下两个内核在运行时行为上存在**结构性差异**，不仅限于配置字段名不同。翻译器和 Flutter 端必须正确处理这些差异。

### 资源文件体系

| 维度 | mihomo | sing-box |
|------|--------|----------|
| GeoIP | `Country.mmdb`（MaxMind 格式），必须预置 | **不需要独立文件**，GeoIP 编译进 `.srs` rule-set |
| GeoSite | `geosite.dat`（v2ray protobuf），必须预置 | **不需要独立文件**，GeoSite 编译进 `.srs` rule-set |
| 规则二进制 | `.mrs` 格式（Mihomo Rule Set） | `.srs` 格式（Sing-box Rule Set），**完全不兼容** |
| 缓存 | 各资源独立存储 | 统一缓存在 `cache.db` |

**对 Flutter 端的影响**：
- 设置页的"刷新 MMDB"功能**移除**，替换为"更新 rule-set"或直接移除（sing-box 通过远程 URL 自动下载和缓存 rule-set）
- 翻译器需要将 mihomo 的 `GEOIP,CN,Proxy` / `GEOSITE,google,Proxy` 规则转换为 sing-box 的 rule-set 引用
- 翻译器需要在生成的 sing-box JSON 配置中内置默认的 rule-set 远程 URL 列表（geoip-cn、geosite-cn 等常用集）

### 配置热重载

mihomo 通过 `PUT /configs?force=true&path=...` 实现热重载。sing-box 的 Clash API **不支持此端点**。

**纯 FFI 方案下的解决方式**：
- Go 桥接层调用 libbox 的 `StartOrReloadService(configContent, options)` 传入新配置字符串
- 切换订阅文件时：Go 层读取新 YAML → 翻译为 sing-box JSON → 调用 `StartOrReloadService`
- 不需要 HTTP 端点参与

### 系统代理管理

mihomo 内部自动设置系统代理（Windows 注册表、macOS networksetup 等）。sing-box **不自动管理**系统代理。

**影响**：
- Flutter 端继续使用 `proxy_manager` 包自行管理系统代理
- 当前项目已有此逻辑（`app_config.dart` 中的 `openProxy`/`closeProxy`），**无需额外改动**
- libbox 提供 `SetSystemProxyEnabled()` 接口，但实际系统代理设置由宿主应用负责

### FakeIP 配置格式

mihomo 在 DNS 全局配置中用 `fake-ip-range` + `fake-ip-filter` 列表。sing-box 把 FakeIP 作为独立的 DNS 服务器类型，通过 DNS 路由规则控制。

**翻译逻辑**：
```
mihomo:
  dns:
    fake-ip-range: 198.18.0.0/15
    fake-ip-filter: ["*.lan", "*.localhost"]

→ sing-box:
  dns.servers[] += {type:"fakeip", tag:"fakeip", inet4_range:"198.18.0.0/15"}
  dns.rules[] += {query_type:["A","AAAA"], action:"route", server:"fakeip"}
  dns.rules[] += 对 fake-ip-filter 中的排除域名设置 action:"route", server:"dns-direct"
```

### TUN 模式

mihomo 的 TUN 是全局配置段（`tun:`）。sing-box 的 TUN 是 `inbounds[]` 中的一个 inbound 条目。

**翻译逻辑**：
```
mihomo:
  tun: {enable:true, stack:"mixed", dns-hijack:[any:53]}

→ sing-box:
  inbounds[] += {
    type:"tun", tag:"tun-in",
    address:["10.0.0.1/24"],
    auto_route:true, stack:"mixed"
  }
```

平台特定字段（如 `auto_redirect` 仅 Linux、UID/包名过滤仅 Android）由翻译器按目标平台条件化输出。

### DNS 配置结构差异

mihomo 把 DNS 作为全局配置段，包含 `nameserver`、`fallback`、`nameserver-policy` 等。sing-box 的 DNS 由 `servers[]` + `rules[]` 构成，逻辑更接近路由系统。

**翻译逻辑**：
```
mihomo:
  dns:
    nameserver: [114.114.114.114, 8.8.8.8]
    fallback: [tls://1.1.1.1, tls://8.8.8.8]
    nameserver-policy: {"+.example.com": "https://dns.example.com"}

→ sing-box:
  dns.servers[] = [
    {tag:"ns", address:"114.114.114.114"},
    {tag:"fb", address:"tls://1.1.1.1"},
    {tag:"ns-policy", address:"https://dns.example.com"}
  ]
  dns.rules[] = [
    {domain_suffix:["example.com"], server:"ns-policy"},
    {outbound:"any", server:"ns"}     // fallback 的条件路由
  ]
```

### 代理组类型差异

| mihomo 类型 | sing-box 类型 | 说明 |
|-------------|--------------|------|
| `Select` | `selector` | 手动选择 |
| `URLTest` | `urltest` | 自动选择最低延迟 |
| `Fallback` | 无直接对应 | 需用 `urltest` 模拟（tolerance 设大值） |
| `LoadBalance` | 无直接对应 | 翻译时降级为 `selector`，记录警告 |

### 规则格式差异

mihomo 用单行字符串规则：`DOMAIN-SUFFIX,google.com,Proxy`。sing-box 用 JSON 对象数组。

**翻译逻辑**：
```
mihomo: DOMAIN-SUFFIX,google.com,Proxy
→ sing-box: {domain_suffix:["google.com"], outbound:"Proxy"}

mihomo: GEOIP,CN,DIRECT
→ sing-box: {rule_set:["geoip-cn"], outbound:"DIRECT"}

mihomo: GEOSITE,google,Proxy
→ sing-box: {rule_set:["geosite-google"], outbound:"Proxy"}
```

GEOIP/GEOSITE 规则翻译时需要翻译器自动生成对应的 rule-set 引用（远程 URL），并添加到 `route.rule_set[]` 中。

## 风险与缓解

| 风险 | 缓解措施 |
|------|----------|
| 配置翻译遗漏 | 完整映射文档 + 降级日志 |
| FFI 内存管理 | Go 分配，Dart 通过显式 free() 释放 |
| 平台特定 TUN | 按平台条件化配置字段 |
| gomobile ABI 稳定性 | 锁定 sing-box 版本，逐平台测试 |
| 影响现有用户 | 翻译器兼容所有 mihomo YAML 配置 |
| MMDB → rule-set 迁移 | 翻译器内置默认 rule-set URL 列表，设置页移除 MMDB 刷新功能 |
| Fallback/LoadBalance 组类型 | 降级为 urltest/selector，记录警告 |
| GEOIP/GEOSITE 规则翻译 | 翻译器维护内置的 rule-set 名称→URL 映射表 |
