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
export fn CoreInit(homeDir: *const c_char) -> c_int          // 初始化 libbox 运行环境
export fn CoreStart(configPath: *const c_char) -> c_int      // 翻译配置 + 启动服务
export fn CoreStop() -> c_int                                 // 停止服务（不释放 libbox）
export fn CoreClose()                                         // 释放 libbox 资源

// 配置管理
export fn CoreCheckConfig(jsonContent: *const c_char) -> c_int  // 验证 sing-box JSON 合法性
export fn CoreReloadConfig() -> c_int                            // 重载当前配置（serviceReload）

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

参考 sing-box-for-android 的 libbox 实践，数据订阅通过 `CommandClient` 的 gRPC 风格接口实现：
- `CommandStatus`：流量、内存、连接数
- `CommandGroup`：代理组信息、延迟测试结果
- `CommandLog`：日志流
- `CommandClashMode`：Clash 模式变更通知

Go 桥接层封装这些订阅接口，通过 C 回调转发给 Dart：

```go
export fn CoreSetCallback(cb: extern fn(eventType: c_int, data: *const c_char))
```

```dart
typedef CoreCallback = Void Function(Int32 eventType, Pointer<Utf8> data);
// eventType: 0=流量, 1=日志, 2=连接, 3=代理组变更
```

### libbox 集成参考

基于 sing-box-for-android 的实际集成方式，Go 桥接层需要实现以下 libbox 接口：

| libbox 方法 | 用途 | 对应 FFI 导出 |
|-------------|------|--------------|
| `setup(options)` | 初始化运行环境（homeDir、cacheDir） | `CoreInit` |
| `newService(config, platformInterface)` | 从 JSON 配置创建服务 | `CoreStart` |
| `service.start()` | 启动服务 | （CoreStart 内部调用） |
| `service.close()` | 关闭服务 | `CoreStop` |
| `checkConfig(content)` | 验证 JSON 配置合法性 | `CoreCheckConfig` (FFI 导出) |
| `serviceReload()` | 重载配置 | `CoreReloadConfig` |
| `selectOutbound(group, tag)` | 切换代理选择 | `CoreSelectProxy` |
| `urlTest(group)` | 触发延迟测试 | `CoreTestDelay` |
| `setClashMode(mode)` | 切换代理模式 | `CoreSetMode` |

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

翻译器需要维护一个**内置映射表**，将常用的 GeoIP/GeoSite 名称映射到远程 rule-set URL。参考 GUI.for.SingBox 实践，使用 MetaCubeX CDN（比 SagerNet raw URL 更稳定）：

```
GEOIP,private  → geoip-private.srs
GEOIP,CN       → geoip-cn.srs
GEOSITE,private → geosite-private.srs
GEOSITE,cn     → geosite-cn.srs
GEOSITE,geolocation-!cn → geosite-geolocation-!cn.srs
GEOSITE,category-ads-all → geosite-category-ads-all.srs
```

基础 URL：`https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/`

对于映射表中不存在的名称，翻译器按 `{type}-{name}.srs` 拼接 URL 并记录警告。格式均为 `binary`，默认更新间隔 `1d`。

### 默认 sing-box 配置模板

翻译器在生成 sing-box JSON 时，需要补充 mihomo 配置中不存在的**必要结构**。以下是基于 GUI.for.SingBox 和 sing-box-for-android 两个项目的完整默认模板：

#### log

```json
{
  "level": "info",
  "timestamp": true
}
```

#### experimental

```json
{
  "clash_api": {
    "external_controller": "127.0.0.1:9090",
    "secret": "",
    "default_mode": "Rule"
  },
  "cache_file": {
    "enabled": true,
    "path": "cache.db",
    "store_fakeip": true,
    "store_dns": true
  }
}
```

> - 纯 FFI 模式下不依赖 `clash_api` 的 HTTP 端点，但保留它以兼容 libbox 内部的 Clash Mode 切换功能。
> - `store_dns` 替代旧版 `store_rdrc`（1.14.0 起更名）。`rdrc_timeout` 非标准字段，已移除。

#### inbounds

从 mihomo 全局端口配置翻译生成：

```json
[
  {
    "type": "mixed",
    "tag": "mixed-in",
    "listen": "127.0.0.1",
    "listen_port": 7890
  }
]
```

若 mihomo 配置了 `tun.enable: true`，追加 TUN inbound：

```json
{
  "type": "tun",
  "tag": "tun-in",
  "address": ["172.18.0.1/30", "fdfe:dcba:9876::1/126"],
  "mtu": 9000,
  "auto_route": true,
  "strict_route": true,
  "stack": "mixed"
}
```

若配置了 `redir-port` 或 `tproxy-port`，追加对应的 `redirect` / `tproxy` inbound。

#### outbounds

翻译 mihomo 的 `proxy-groups` 和 `proxies`。翻译器需要**额外生成**以下内置 outbound（mihomo 隐式提供，sing-box 必须显式声明）：

```json
[
  { "type": "direct", "tag": "DIRECT" },
  { "type": "block", "tag": "REJECT" },
  { "type": "dns", "tag": "dns-out" }
]
```

代理组翻译：
- `type: Select` → `{type:"selector", tag:"...", outbounds:[...], interrupt_exist_connections:true}`
- `type: URLTest` → `{type:"urltest", tag:"...", outbounds:[...], url:"...", interval:"3m", tolerance:150}`
- `type: Fallback` → `{type:"urltest", tag:"...", outbounds:[...], tolerance:999999}` (用大 tolerance 模拟)
- `type: LoadBalance` → `{type:"selector", tag:"..."}` (降级，记录警告)

#### route

翻译 mihomo 的 `rules`，并**自动注入**以下默认规则（GUI.for.SingBox 实践）：

```json
{
  "rules": [
    { "inbound": "tun-in", "action": "sniff" },
    { "protocol": "dns", "action": "hijack-dns" },
    { "ip_is_private": true, "outbound": "DIRECT" },
    ...mihomo 规则翻译结果...,
    { "network": "icmp", "outbound": "DIRECT" }
  ],
  "rule_set": [
    ...从 GEOIP/GEOSITE 规则翻译生成的远程 rule-set 引用...
  ],
  "auto_detect_interface": true,
  "final": "PROXY"
}
```

> 规则顺序至关重要：sniff → 劫持 DNS → 隐私 IP 直连 → 用户规则 → 兜底代理。

#### dns

翻译 mihomo 的 `dns:` 配置。翻译器生成双服务器架构（本地 + 远程），并处理 FakeIP。

**关键设计**：每个使用域名地址（如 HTTPS/TLS/Doh）的 DNS server 需要通过 `domain_resolver` 指定一个使用 IP 地址的 UDP resolver，避免 DNS 解析死循环。

```json
{
  "servers": [
    { "tag": "local-dns", "type": "https", "server": "223.5.5.5", "server_port": 443,
      "path": "/dns-query", "domain_resolver": "local-dns-resolver" },
    { "tag": "local-dns-resolver", "type": "udp", "server": "223.5.5.5", "server_port": 53 },
    { "tag": "remote-dns", "type": "tls", "server": "8.8.8.8", "server_port": 853,
      "detour": "PROXY", "domain_resolver": "remote-dns-resolver" },
    { "tag": "remote-dns-resolver", "type": "udp", "server": "8.8.8.8", "server_port": 53,
      "detour": "PROXY" },
    { "tag": "fakeip-dns", "type": "fakeip", "inet4_range": "198.18.0.0/15" }
  ],
  "rules": [
    { "clash_mode": "Direct", "server": "local-dns" },
    { "clash_mode": "Global", "server": "remote-dns" },
    { "rule_set": ["geosite-cn"], "server": "local-dns" },
    { "rule_set": ["geolocation-!cn"], "server": "remote-dns" },
    {
      "type": "logical", "mode": "and",
      "rules": [
        { "domain_suffix": [
          ".lan", ".localdomain", ".example", ".invalid",
          ".localhost", ".test", ".local", ".home.arpa",
          ".msftconnecttest.com", ".msftncsi.com"
        ], "invert": true },
        { "query_type": ["A", "AAAA"] }
      ],
      "server": "fakeip-dns"
    }
  ],
  "final": "remote-dns",
  "strategy": "prefer_ipv4"
}
```

> - `domain_resolver` 链：`local-dns`（HTTPS）→ 通过 `local-dns-resolver`（UDP 223.5.5.5:53）解析域名；`remote-dns`（TLS）→ 通过 `remote-dns-resolver`（UDP 8.8.8.8:53）解析域名。避免 DNS 解析死循环。
> - FakeIP 规则使用 logical AND：排除常见本地域名 + Windows 网络检测域名后，对 A/AAAA 查询走 FakeIP。

### 翻译器完整流程

```
输入：mihomo YAML 文件路径
  │
  ├─ 1. 解析 YAML
  ├─ 2. 翻译全局配置 → log + experimental + inbounds
  ├─ 3. 翻译 proxies[] → outbounds[]
  ├─ 4. 翻译 proxy-groups[] → outbounds[]（追加到 outbounds）
  ├─ 5. 注入内置 outbound（DIRECT, REJECT, dns-out）
  ├─ 6. 翻译 rules[] → route.rules + route.rule_set
  │     ├─ DOMAIN-SUFFIX → domain_suffix 规则
  │     ├─ GEOIP,x,y → rule_set 引用 + 自动生成 rule_set 定义
  │     ├─ GEOSITE,x,y → rule_set 引用 + 自动生成 rule_set 定义
  │     └─ 其他 → 对应 sing-box 规则类型
  ├─ 7. 注入默认路由规则（sniff, hijack-dns, icmp）
  ├─ 8. 翻译 dns → dns servers + rules
  │     ├─ nameserver → local-dns 服务器（HTTPS/TLS 类型需生成对应的 resolver）
  │     ├─ fallback → remote-dns 服务器（同上）
  │     ├─ domain_resolver 链：每个域名地址的 server 需指定一个 IP 地址的 UDP resolver
  │     ├─ fake-ip-range → fakeip 服务器 + logical 规则（含排除域名列表）
  │     └─ nameserver-policy → dns rules
  ├─ 9. 翻译 tun → inbound (如启用)
  ├─ 10. 组装完整 sing-box JSON
  └─ 11. 返回 JSON 字符串（传给 libbox）
```

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
| 代理模式 | 保留，映射到 `experimental.clash_api.default_mode`（libbox `setClashMode`） |
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
