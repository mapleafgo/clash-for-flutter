# FFI 通信层迁移设计

## 目标

将 clash-for-flutter 前端从 HTTP REST + WebSocket 通信模式迁移到纯 FFI 直连 cff-core 内核。仅替换通信层，UI 和页面结构不变。

## 架构概览

```
之前：UI → Service → ClashApi(Dio HTTP) → Rust后端 → Clash内核
      UI → Service → WsStreams(WebSocket) → Rust后端 → Clash内核

之后（桌面端）：
  UI → Service → LibCore(FFI) → cff-core(.so/.dll/.dylib)
  UI → Service → Signal 监听 ← LibCore 回调桥接 ← cff-core 回调

之后（移动端）：
  UI → Service → LibCore(MethodChannel) → Native(Kotlin/Swift) → gomobile AAR/xcframework → Go Core
  移动端 TUN：Native 层创建 TUN fd → 实现 PlatformInterface.OpenTun() → sing-box gVisor 读写 fd
```

### 平台架构差异

| | 桌面端 | 移动端 |
|---|---|---|
| 核心通信 | Dart FFI 直连 .so/.dll/.dylib | MethodChannel → Native → gomobile API |
| TUN 实现 | 内核直接创建 TUN 设备 | Native 层创建 fd，注入 PlatformInterface |
| 构建产物 | c-shared .so/.dll/.dylib | gomobile AAR / xcframework |
| 权限提权 | setuid / UAC | VpnService / NEPacketTunnelProvider |

## 文件结构

```
lib/
├── core/
│   ├── ffi_bindings.dart          # ffigen 自动生成的 C FFI 绑定
│   ├── lib_core.dart              # LibCore 门面类
│   └── lib_core_exception.dart    # 自定义异常
│
├── services/                      # 修改依赖引用
├── presentation/                  # 不变
└── domain/                        # 不变
```

### 删除的文件

- `lib/data/api/clash_api.dart`
- `lib/data/api/ws_streams.dart`
- `lib/core_control.dart`
- `lib/clash_generated_bindings.dart`
- `lib/data/api/` 目录（变空后整个删除）

### 删除的依赖/代码

- Rust 后端相关代码（`startRust()`、`rustAddr`、随机端口分配等）
- `dio` 中与 ClashApi 相关的实例，但保留用于订阅文件下载的 HTTP 能力（可提取为简单工具函数）
- 旧的 FFI 绑定（`clash_generated_bindings.dart`）
- 移动端旧的 MethodChannel VPN 逻辑改为调用 gomobile API（非删除，是重写）

## FFI 绑定层

使用 ffigen 从 cff-core 的 C 头文件自动生成绑定。

### ffigen 配置

```yaml
ffigen:
  name: CffCoreBindings
  output: 'lib/core/ffi_bindings.dart'
  headers:
    entry-points:
      - '../cff-core/ffi/ffi.h'
  functions:
    include:
      - CoreInit
      - CoreStart
      - CoreStop
      - CoreClose
      - CoreCheckConfig
      - CoreReloadConfig
      - CoreQueryProxies
      - CoreQueryTraffic
      - CoreQueryLogs
      - CoreQueryConnections
      - CoreSelectProxy
      - CoreSetMode
      - CoreCloseConnection
      - CoreCloseAllConnections
      - CoreTestDelay
      - CoreGetVersion
      - CoreSetCallback
      - CoreTranslateConfig
      - CoreFreeString
```

### 绑定特征

- 所有函数返回 `Pointer<Utf8>`（对应 C 的 `char*`）
- 字符串参数接收 `Pointer<Utf8>`
- 回调类型生成为 `NativeFunction` typedef
- 需手动处理 `Utf8` ↔ `String` 转换和内存释放

### 回调线程安全

**桌面端**：cff-core 的 C 回调从 Go 线程触发。使用 `Pointer.fromFunction` 注册回调，Dart VM 会处理跨线程的 Signal 值更新。如遇线程问题，可降级为 `NativeCallable.listener`（Dart 3.3+）。

**移动端**：Native 层通过 `EventChannel` 推送事件到 Flutter。`LibCoreChannel` 监听 EventChannel，更新对应的 Signal。不涉及 C 回调。

## Domain 模型适配

Domain 模型的 `fromJson` 工厂方法改为适配 cff-core 的 JSON 格式，不再兼容旧 Clash API。

主要影响：
- `ProxyGroup`：适配 cff-core 的 `{Tag, Type, Selectable, Selected, Items: [{Tag, Type, Delay}]}` 格式
- `TrafficSnapshot`：适配 `{Up, Down, UpTotal, DownTotal, Memory, Goroutines, ConnsIn, ConnsOut}` 格式
- `LogEntry`：适配 `{Level, Message}` 格式
- `ConnectionEventSnapshot`：适配 cff-core 的连接事件格式
- 涉及文件：`lib/domain/` 下所有模型文件

由于旧 Clash API 不再使用，无需做格式映射，直接让 domain 模型匹配 cff-core 即可。

## LibCore 门面类

LibCore 对外提供统一的 Dart API，内部根据平台选择不同的实现。

### 平台抽象

```dart
class LibCore {
  static final LibCore instance = LibCore._();
  LibCore._();

  late final LibCorePlatform _platform;

  Future<void> init() async {
    if (Constants.isDesktop) {
      _platform = LibCoreFFI();
    } else {
      _platform = LibCoreChannel();
    }
    await _platform.init();
  }
}

abstract class LibCorePlatform {
  Future<void> init();
  // ... 所有核心方法
}
```

### 桌面端实现（LibCoreFFI）— 直接 FFI

```dart
class LibCoreFFI implements LibCorePlatform {
  late final CffCoreBindings _ffi;
  late final DynamicLibrary _lib;

  @override
  Future<void> init() async {
    _lib = DynamicLibrary.open(_platformLibPath);
    _ffi = CffCoreBindings(_lib);
  }

  String get _platformLibPath {
    if (Platform.isLinux) return 'lib/core/libsingcast-linux.so';
    if (Platform.isMacOS) return 'lib/core/libsingcast-darwin.dylib';
    if (Platform.isWindows) return 'lib/core/libsingcast-windows.dll';
    throw UnsupportedError('Unsupported platform');
  }
}
```

### 移动端实现（LibCoreChannel）— MethodChannel + gomobile

移动端通过 MethodChannel 调用 Native 层，Native 层调用 gomobile 生成的 API（Android: AAR Java 接口，iOS: xcframework Swift 接口）。

```dart
class LibCoreChannel implements LibCorePlatform {
  static const _channel = MethodChannel('cn.mapleafgo/singcast');

  @override
  Future<void> init() async {
    // 无需额外初始化，gomobile 库由 native 层加载
  }

  @override
  Future<void> initCore(String homeDir) =>
      _channel.invokeMethod('initCore', {'homeDir': homeDir});

  @override
  Future<void> startCore(String configPath, {String? ruleSetProxy}) =>
      _channel.invokeMethod('startCore', {
        'configPath': configPath,
        'ruleSetProxy': ruleSetProxy,
      });

  // ... 其他方法同理
}
```

### 移动端 Native 层职责

**Android（Kotlin）：**
1. 实现 `VpnService` 子类，在 `OpenTun()` 中调用 `VpnService.Builder.establish()` 获取 fd
2. 实现 gomobile 生成的 `PlatformInterface`，注入到 Singcast.Init
3. 通过 MethodChannel 暴露 `initCore`/`startCore`/`stopCore` 等方法给 Flutter
4. 参考 sing-box-for-android 的 VpnService 实现

**iOS（Swift）：**
1. 创建 `NEPacketTunnelProvider` 扩展（独立 target）
2. 实现 `PlatformInterface`，在 `OpenTun()` 中提取 fd
3. 通过 MethodChannel 触发 `startTunnel()`/`stopTunnel()`
4. 参考 sing-box-for-apple 的 NetworkExtension 实现

### 通用调用模式

```dart
Future<T> _call<T>(
  Pointer<Utf8> Function() fn,
  T Function(Map<String, dynamic>) parser,
) async {
  final ptr = fn();
  try {
    final json = jsonDecode(ptr.toDartString());
    if (json is Map && json.containsKey('error')) {
      throw LibCoreException(json['error']);
    }
    return parser(json);
  } finally {
    _ffi.CoreFreeString(ptr);
  }
}
```

所有返回 `char*` 的 FFI 调用都必须通过 `CoreFreeString` 释放。统一检查 `error` 字段，抛出 `LibCoreException`。

### 方法映射 — 生命周期

| LibCore 方法 | FFI 调用 | 说明 |
|---|---|---|
| `initCore(String homeDir)` | `CoreInit` | 初始化内核运行时 |
| `startCore(String configPath, {String? ruleSetProxy})` | `CoreStart` | 启动代理服务 |
| `stopCore()` | `CoreStop` | 停止服务 |
| `closeCore()` | `CoreClose` | 关闭释放资源 |
| `reloadConfig()` | `CoreReloadConfig` | 重载配置 |

### 方法映射 — 查询

| LibCore 方法 | FFI 调用 | 返回类型 |
|---|---|---|
| `queryProxies()` | `CoreQueryProxies` | `List<ProxyGroup>` |
| `queryTraffic()` | `CoreQueryTraffic` | `TrafficSnapshot` |
| `queryLogs()` | `CoreQueryLogs` | `List<LogEntry>` |
| `queryConnections()` | `CoreQueryConnections` | `ConnectionsSnapshot` |

### 方法映射 — 控制

| LibCore 方法 | FFI 调用 | 说明 |
|---|---|---|
| `selectProxy(String group, String tag)` | `CoreSelectProxy` | 选择代理 |
| `testDelay(String name)` | `CoreTestDelay` | 测速，返回 JSON 中包含 delay 数值（ms），0 表示超时 |
| `setMode(String mode)` | `CoreSetMode` | 设置路由模式 |
| `closeConnection(String id)` | `CoreCloseConnection` | 关闭连接 |
| `closeAllConnections()` | `CoreCloseAllConnections` | 关闭所有连接 |
| `checkConfig(String jsonContent)` | `CoreCheckConfig` | 校验配置 |
| `translateConfig(String yaml, {String? ruleSetProxy})` | `CoreTranslateConfig` | YAML→JSON 翻译 |
| `getVersion()` | `CoreGetVersion` | 获取版本 |

## 回调 → Signal 桥接

### 事件类型映射

| 事件 | C eventType | Signal | 类型 |
|---|---|---|---|
| 流量 | 0 | `trafficSignal` | `TrafficSnapshot?` |
| 日志 | 1 | `logsSignal` | `List<LogEntry>` |
| 连接 | 2 | `connectionsSignal` | `ConnectionsSnapshot?` |
| 代理更新 | 3 | `proxiesSignal` | `List<ProxyGroup>` |
| 模式更新 | 4 | `modeSignal` | `String` |

### 实现

C 回调必须是静态/顶级函数（Dart FFI 限制）。通过单例访问 Signal。

```dart
class LibCore {
  final trafficSignal = signal<TrafficSnapshot?>(null);
  final logsSignal = signal<List<LogEntry>>([]);
  final connectionsSignal = signal<ConnectionsSnapshot?>(null);
  final proxiesSignal = signal<List<ProxyGroup>>([]);
  final modeSignal = signal<String>('rule');

  void _setupCallback() {
    final callback = Pointer.fromFunction<CoreCallback>(_onCoreEvent, 0);
    _ffi.CoreSetCallback(callback);
  }

  static void _onCoreEvent(int eventType, Pointer<Utf8> data) {
    final json = jsonDecode(data.toDartString());
    final instance = LibCore.instance;
    switch (eventType) {
      case 0: instance.trafficSignal.value = TrafficSnapshot.fromJson(json);
      case 1: instance.logsSignal.value = (json as List).map((e) => LogEntry.fromJson(e)).toList();
      case 2: instance.connectionsSignal.value = ConnectionsSnapshot.fromJson(json);
      case 3: instance.proxiesSignal.value = (json as List).map((e) => ProxyGroup.fromJson(e)).toList();
      case 4: instance.modeSignal.value = json['current_mode'];
    }
  }
}
```

回调中的 JSON 字符串由 Go 侧管理，Dart 不需要释放。Signal 天然去重，值相同时不触发重建。

### 日志累积策略

LibCore 内部维护一个环形缓冲区（最近 1000 条日志），EventLogs 回调时追加新日志到缓冲区，再整体赋值给 `logsSignal`：

```dart
class LibCore {
  static const _maxLogs = 1000;
  final _logBuffer = <LogEntry>[];

  // 在 _onCoreEvent 的 case 1 中：
  static void _onLogs(List<dynamic> items) {
    final newLogs = items.map((e) => LogEntry.fromJson(e)).toList();
    final buf = instance._logBuffer;
    buf.addAll(newLogs);
    if (buf.length > _maxLogs) {
      buf.removeRange(0, buf.length - _maxLogs);
    }
    instance.logsSignal.value = List.unmodifiable(buf);
  }
}
```

## ruleSetProxy 配置

- cff-core 内核通过 `ruleSetProxy` 参数下载 rule-set 资源（GeoIP/GeoSite 等）
- 前端提供代理地址配置，默认值 `https://gh-proxy.org`
- 传入 `CoreStart` 和 `CoreTranslateConfig` 的 `ruleSetProxy` 参数
- 前端无需单独下载 MMDB 等资源，内核自行处理

## TUN 模式适配（延后 — 内核侧仍在处理）

### sing-box TUN 架构

sing-box 的 TUN 在不同平台走不同路径：

**桌面端**：Go 核心直接创建 TUN 设备（需要管理员/root 权限）

**移动端**：通过 PlatformInterface 路径，Native 层创建 fd 后注入 Go 核心
```
Native 层创建 TUN fd
  → 实现 PlatformInterface.OpenTun() 返回 fd
  → sing-box 用 gVisor netstack 读写 fd

Android: VpnService.Builder.establish() → ParcelFileDescriptor → fd → Go
iOS:     NEPacketTunnelProvider → 私有 API 提取 fd → Go
```

### 桌面端 TUN — 按需提权

参考 FlClash 设计，应用正常启动不需要管理员权限，只有用户第一次打开 TUN 开关时才请求提权。

| 平台 | 提权方式 |
|---|---|
| **Linux** | 弹出密码输入框，`sudo -S chown root:root corePath && chmod +sx corePath` 设置 setuid 位，重启核心 |
| **macOS** | `osascript -e 'do shell script ... with administrator privileges'` 设置 setuid 位，重启核心 |
| **Windows** | 通过 UAC 提权重启应用（`ShellExecuteW runas`） |

关键点：
- `tunIf` signal 记录用户偏好（持久化），`coreElevated` signal 记录核心是否以提权模式运行
- 只有 `tunIf == true && coreElevated == false` 时才触发提权流程
- 提权成功后调用 `LibCore.instance.stopCore()` + `LibCore.instance.startCore()` 重启核心
- 关闭 TUN 不需要提权，直接修改配置并重载

### 移动端 TUN — Native VpnService / NetworkExtension

移动端 TUN 由 Native 层管理，Flutter 通过 MethodChannel 触发：

```
Flutter (Dart)
  → MethodChannel('vpn').invokeMethod('connect', {'configPath': path})
  → Native 层：
      Android: 启动 VpnService → 创建 fd → 注入 PlatformInterface → 启动 Go 核心
      iOS:     启动 NEPacketTunnelProvider → 创建 fd → 注入 PlatformInterface → 启动 Go 核心
```

Android 实现要点：
1. 创建 `VpnService` 子类
2. 实现 gomobile 生成的 `PlatformInterface`，在 `OpenTun()` 中调用 `VpnService.Builder.establish()` 返回 fd
3. `Singcast.Init` 时注入 PlatformInterface
4. 参考 sing-box-for-android 的 VpnService 实现

iOS 实现要点：
1. 创建 `NEPacketTunnelProvider` 扩展（独立 target）
2. 实现 `PlatformInterface`，在 `OpenTun()` 中提取 fd
3. 参考 sing-box-for-apple 的 NetworkExtension 实现

### Go 层改造需求

当前 `core/platform.go` 的 `PlatformIO` 是硬编码的（桌面端返回 `os.ErrInvalid`），需要改为可注入：

```go
// 移动端需要 native 层注入自定义 PlatformInterface
func InitWithPlatform(homeDir string, platform PlatformInterface) error {
    // 注入包含真实 OpenTun 的 PlatformInterface
}
```

构建标签需要添加 `with_gvisor`（移动端 TUN 依赖 gVisor netstack）。

### 配置变更流程

TUN 开关修改源 YAML 配置中的 `tun.enable` 字段，重新翻译并重载：

```
toggleTun(enable)
  → 桌面端：如需提权则先提权流程
  → 移动端：如需开启则通过 MethodChannel 启动 VpnService/NetworkExtension
  → 读取当前 YAML 配置文件
  → 修改 tun.enable = enable
  → 写回 YAML 文件
  → LibCore.instance.translateConfig(yaml, ruleSetProxy)
  → 保存翻译后的 JSON 到 homeDir/singbox-config.json
  → LibCore.instance.reloadConfig()
```

### LibCore 新增方法

| 方法 | 说明 |
|---|---|
| `toggleTun(bool enable)` | 桌面端处理提权 → 移动端触发 VpnService → 修改配置 → 翻译并重载 |

### 保留的 UI 和状态

- `_TunSwitch` 组件（HomePage）保持不变
- `tunIf` signal（AppConfig）保持不变，持久化用户偏好
- TUN 开关仍然通过 `CoreConfig.openTun()` / `closeTun()` 调用，内部改为调用 `LibCore.instance.toggleTun()`

## Service 层适配

改动很小，本质是替换依赖引用。

### AppConfig 服务

| 改动点 | 之前 | 之后 |
|---|---|---|
| 初始化内核 | `CoreControl.startRust(rustAddr)` | `LibCore.instance.initCore(homeDir)` |
| 切换配置 | `ClashApi.changeConfig(path)` | 翻译 YAML → `LibCore.instance.startCore(jsonPath)` |
| 删除 | `Constants.rustAddr` | 不再需要 |
| 订阅下载 | `ClashApi` 内 Dio 实例 | 提取为独立工具函数（如 `downloadSubscription(url)`） |

### CoreConfig 服务

| 改动点 | 之前 | 之后 |
|---|---|---|
| 更新模式 | `ClashApi.patchConfig({'mode': mode})` | `LibCore.instance.setMode(mode)` |
| 监听模式变化 | 轮询/无 | `LibCore.instance.modeSignal.watch(context)` |
| TUN 控制 | `ClashApi.patchConfig` + MethodChannel VPN | `LibCore.instance.toggleTun(enable)` |
| 移动端 VPN | `CoreControl.startVpn()`/`stopVpn()` | 保留 MethodChannel，改为调用 Native gomobile API |

### 页面层

| 页面 | 之前 | 之后 |
|---|---|---|
| HomePage（流量） | `WsStreams.traffic().listen(...)` | `Watch((_) => LibCore.instance.trafficSignal.value)` |
| LogsPage | `WsStreams.logs(level).listen(...)` | `Watch((_) => LibCore.instance.logsSignal.value)` |
| ConnectionsPage | `WsStreams.connections().listen(...)` | `Watch((_) => LibCore.instance.connectionsSignal.value)` |
| ProxiesPage | `ClashApi.getProxies()` + 定时刷新 | `Watch((_) => LibCore.instance.proxiesSignal.value)` |

### 无需改动的部分

- `data/local/` 存储层
- 路由、导航

### 系统代理（适配 sing-box inbound 端口）

桌面端的系统代理设置（`openProxy()`/`closeProxy()`）通过 `proxy_manager` 包设置系统 HTTP/SOCKS 代理。迁移后：
- 系统代理指向 cff-core sing-box 配置中的 mixed inbound 端口（HTTP+SOCKS5）
- 端口号来自 Mihomo YAML 配置，翻译后体现在 sing-box JSON 的 inbound 配置中
- LibCore 从翻译后的 JSON 配置中读取 mixed inbound 端口，暴露为 `proxyPort` 属性
- `openProxy()` 调用 `proxy_manager` 设置 `127.0.0.1:{proxyPort}`

### 托盘服务适配

TrayService 需要从 LibCore 获取状态：
- 代理状态：监听 `LibCore.instance.trafficSignal` 判断是否在运行
- 当前模式：监听 `LibCore.instance.modeSignal`
- 切换模式：调用 `LibCore.instance.setMode()`
- 启停控制：调用 `LibCore.instance.startCore()` / `stopCore()`

### `coreElevated` signal 归属

`coreElevated` signal 放在 AppConfig 服务中，与 `tunIf` 并列，持久化用户提权状态。不放入 LibCore（LibCore 不关心应用层状态）。

## 启动流程

### 新流程

```
main()
  → LibCore.instance.init()             // 加载动态库
  → LibCore.instance.initCore(homeDir)   // 初始化内核运行时
  → LibCore.instance._setupCallback()    // 注册事件回调
  → LibCore.instance.startCore(configPath, ruleSetProxy: proxy) // 启动代理服务
  // Signal 自动推送，无需手动连接
```

### 配置文件工作流

```
用户选择 YAML 配置文件
  → LibCore.instance.translateConfig(yaml, ruleSetProxy: proxy)
  → 保存 sing-box JSON 到 homeDir/singbox-config.json
  → LibCore.instance.startCore(jsonPath: homeDir/singbox-config.json, ruleSetProxy: proxy)
```

翻译后的 JSON 统一保存在 `homeDir/singbox-config.json`。翻译过程对用户透明。

## 生命周期

| 阶段 | LibCore 调用 |
|---|---|
| 应用启动 | `init()` → `initCore(homeDir)` → `setupCallback()` |
| 开始代理 | `startCore(configPath, ruleSetProxy)` |
| 切换配置 | `stopCore()` → `translateConfig()` → `startCore(newPath)` |
| 重载配置 | `reloadConfig()` |
| 应用退出 | `stopCore()` → `closeCore()` |
