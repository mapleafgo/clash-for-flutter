# Singcast 架构说明

## 平台差异概览

Singcast 是一款跨平台代理客户端，针对不同平台采用不同的内核部署策略：

| 平台 | 内核位置 | 通信方式 | 说明 |
|------|---------|---------|------|
| **Desktop** (macOS/Windows/Linux) | 独立进程 (`singcast-cli`) | Unix Domain Socket / Named Pipe (RPC) | 内核以独立进程运行，主 App 通过 IPC 连接 |
| **iOS** | Network Extension 进程 | App Group Socket (RPC) + MethodChannel | 内核跑在 `NEPacketTunnelProvider`，主 App 是纯 RPC 客户端 |
| **Android** | 本进程 (FFI) | Dart FFI 直接调用 | 内核以共享库形式嵌入主 App 进程 |

---

## iOS 架构详解

### 双进程模型

```
┌─────────────────────────────────────┐
│         Main App Process            │
│  ┌───────────┐    ┌──────────────┐  │
│  │  Flutter   │    │  AppDelegate │  │
│  │    UI      │◄──►│  (Method     │  │
│  └───────────┘    │   Channel)   │  │
│                   └──────┬───────┘  │
│                          │          │
│                   ┌──────▼───────┐  │
│                   │ IosVpnBridge │  │
│                   └──────┬───────┘  │
│                          │          │
│                   ┌──────▼───────┐  │
│                   │  IpcWorker   │  │
│                   │  (RPC Client)│  │
│                   └──────┬───────┘  │
└──────────────────────────┼──────────┘
                           │ App Group Socket
                           │ (command.sock)
                           ▼
┌─────────────────────────────────────┐
│   Network Extension Process         │
│  ┌──────────────────────────────┐   │
│  │  ExtensionProvider           │   │
│  │  (NEPacketTunnelProvider)    │   │
│  │                              │   │
│  │  ┌────────┐  ┌───────────┐  │   │
│  │  │ sing-  │  │ IPC Server│  │   │
│  │  │ box    │◄─┤ (RPC)     │  │   │
│  │  │ Kernel │  └───────────┘  │   │
│  │  └────────┘                 │   │
│  └──────────────────────────────┘   │
└─────────────────────────────────────┘
```

### 职责划分

#### 主 App 进程（AppDelegate）
- **VPN 生命周期管理**：通过 `NETunnelProviderManager` 启动/停止隧道
- **App Group 路径暴露**：提供共享容器路径供 Dart 层连接 RPC
- **配置重载转发**：将 `reloadCore` 请求转发到 Extension（`sendProviderMessage`）

#### Extension 进程（ExtensionProvider）
- **内核初始化**：设置 `home_dir`（日志/缓存/FakeIP 持久化目录）
- **RPC Server**：随内核 init 启动，监听 App Group socket
- **TUN fd 管理**：从 `packetFlow` 提取 fd 并传递给内核
- **热重载**：本地执行 `SetTunFd` + `StartWithContent`，避免裸 RPC 重启导致 fd 失效

#### Dart 层（LibCore + IosVpnBridge）
- **IosVpnBridge**：桥接 VPN 生命周期方法到 `IpcWorker`
  - `connectVpn/disconnectVpn/isVpnRunning` → MethodChannel
  - `startCoreWithContent` → Extension 本地重载
- **IpcWorker**：统一 RPC 客户端接口
  - 查询代理/连接/模式
  - 切节点/测延迟/切模式
  - 日志/内存/DNS 刷新

### 关键设计决策

#### 1. 为什么 reload 不走裸 RPC？

**问题**：iOS Extension 中，内核的 TUN fd 是一次性消费的。如果直接在主 App 通过 RPC 调用 `core.startWithContent`，内核会尝试重新消费已失效的 fd，导致失败。

**解决**：通过 `NETunnelProviderSession.sendProviderMessage` 让 Extension 本地执行：
```swift
// ExtensionProvider.swift
override func handleAppMessage(_ messageData: Data, ...) {
    // 1. 提取当前 TUN fd
    if let tunFd = extractTunFd() ?? getTunnelFileDescriptor() {
        singcast.setTunFd(dup(tunFd))
    }
    // 2. 本地重启内核
    try singcast.startWithContent(configContent, ruleSetProxy: ruleSetProxy)
    // 3. 回传结果给主 App
    completionHandler?(encodeReloadResult(error: nil))
}
```

#### 2. RPC 连接时序

**iOS Network Extension 进程生命周期**：
- **进程启动** = `startTunnel()` 被调用（用户开启 VPN）
- **进程销毁** = `stopTunnel()` 或系统杀死
- **关键限制**：Extension 进程与 VPN 隧道**同生命周期**，无法独立存在

**应用启动流程**（VPN 未开启）：
```
LibCore.init()
  ├─ 创建 IosVpnBridge
  ├─ 获取 App Group socket 路径
  ├─ 创建 IpcWorker (RPC client)
  └─ ❌ 不连接 RPC（Extension 尚未启动）
```

**首次开启 VPN 场景**：
```
LibCore.connectVpn()
  ├─ MethodChannel 'connectVpn' → 启动隧道
  ├─ 系统启动 Extension 进程（异步，~1-3 秒）
  ├─ ExtensionProvider.startTunnel
  │   ├─ singcast.init_(home_dir)
  │   ├─ singcast.startIpcServer(socketPath)  ← RPC server 启动
  │   └─ singcast.startWithContent(config)
  └─ connectIpc() → 连接 RPC socket（带重试）
      └─ syncKernelState()
```

**冷启动恢复场景**（App 被杀后重新启动，VPN 仍在运行）：
```
main.dart _initApp()
  ├─ isVpnRunning() → true (隧道在跑)
  ├─ connectIpc() → 连接已存在的 RPC socket
  └─ syncKernelState() → 同步内核状态
```

**关键点**：
- **RPC socket 生命周期 = Extension 进程生命周期 = VPN 隧道生命周期**
- **必须在 connectVpn() 后才连接 RPC**（此时 Extension 才启动）
- **重试机制**：`_connectWithRetry()` 使用指数退避（100ms → 200ms → ... → 3000ms），总超时 10 秒，等待 Extension 启动
- **无法在不开启 VPN 的情况下使用 RPC**（这是 iOS 系统限制）

#### 3. 资源清理

**内核生命周期与 Extension 进程完全绑定**：

```swift
// startTunnel: 每次 VPN 开启，系统创建新的 ExtensionProvider 实例
override func startTunnel(options: [String: NSObject]?) async throws {
    // singcast 是新创建的，状态永远是 "created"
    try singcast.init_(homeDir)
    try singcast.startIpcServer(rpcPath)
    try singcast.startWithContent(config)
}

// stopTunnel: VPN 停止 → 内核 destroy（彻底释放资源）
override func stopTunnel(with reason: NEProviderStopReason) async {
    singcast.destroy()  // ← 不可逆销毁，释放所有资源
}
```

**关键点**：
- **每次 `startVPNTunnel()` 系统都会创建新的 `ExtensionProvider` 实例**
- **不会复用 provider 实例**，因此不需要幂等检查（如 `if state == "created"`）
- **`singcast` 也是新创建的**，每次都是全新的内核实例

**为什么用 `destroy()` 而非 `stop()`**：
- **`stop()`**：停止服务但保留实例，可再次 `startWithContent` 重启
- **`destroy()`**：彻底销毁实例，释放所有资源（goroutine、内存、文件句柄等）
- **Extension 进程销毁后不会复用**：每次 VPN 开启都是全新的 Extension 实例，因此应该用 `destroy()` 确保资源完全释放

**主 App 断开处理**：移动端不自动重连（`_attemptReconnect` 提前返回），等待用户手动开关 VPN

---

## Android 架构

Android 平台采用单进程 FFI 方案，内核以 `.so` 形式嵌入主 App：

```
┌─────────────────────────────────────┐
│         Main App Process            │
│  ┌───────────┐    ┌──────────────┐  │
│  │  Flutter   │    │ LibCore      │  │
│  │    UI      │◄──►│ Channel      │  │
│  └───────────┘    └──────┬───────┘  │
│                          │          │
│                   ┌──────▼───────┐  │
│                   │  Dart FFI    │  │
│                   └──────┬───────┘  │
│                          │          │
│                   ┌──────▼───────┐  │
│                   │ libclash.so  │  │
│                   │ (sing-box)   │  │
│                   └──────────────┘  │
└─────────────────────────────────────┘
```

特点：
- 无进程间通信开销
- 无需处理 fd 传递问题
- 内核生命周期与 App 进程绑定

---

## Desktop 架构

桌面端采用独立进程 + IPC 方案：

```
┌──────────────────────┐       ┌──────────────────────┐
│   Main App Process   │       │  Core Process        │
│                      │       │  (singcast-cli)      │
│  ┌────────────────┐  │       │                      │
│  │  Flutter UI    │  │ IPC   │  ┌────────────────┐  │
│  └──────┬─────────┘  │◄─────►│  │  sing-box      │  │
│         │            │       │  │  Kernel        │  │
│  ┌──────▼─────────┐  │       │  └────────────────┘  │
│  │  IpcWorker     │  │       │  ┌────────────────┐  │
│  │  (RPC Client)  │  │       │  │  IPC Server    │  │
│  └────────────────┘  │       │  └────────────────┘  │
└──────────────────────┘       └──────────────────────┘
```

特点：
- 内核以独立进程运行（支持特权模式/TUN）
- 通过 Unix Domain Socket (macOS/Linux) 或 Named Pipe (Windows) 通信
- 支持崩溃自动重启（`_attemptReconnect`）

---

## 核心模块

### LibCore

平台无关的内核抽象层，提供统一 API：

```dart
class LibCore {
  // 查询
  Future<String> queryProxies();
  Future<String> queryConnections();
  Future<String> queryMode();

  // 控制
  Future<void> selectProxy(String group, String tag);
  Future<void> setMode(String mode);
  Future<Map<String, int>> testGroupDelay(String group, {int timeoutMs});

  // VPN
  Future<void> connectVpn(String config, {String? ruleSetProxy, bool? ipv6});
  Future<void> disconnectVpn();
  Future<bool> isVpnRunning();

  // 维护
  Future<void> flushFakeIP();
  Future<void> flushDNSCache();
  Future<void> triggerGC();
}
```

内部根据平台选择不同实现：
- Desktop/iOS: `_platform = _ipcWorker!` (RPC)
- Android: `_platform = channel` (FFI)

### IpcWorker

统一的 RPC 客户端实现：

```dart
class IpcWorker implements LibCorePlatform {
  final String ipcPath;

  // iOS 专属钩子（桌面/Android 为 null）
  Future<void> Function(String config, {...})? connectVpnImpl;
  Future<void> Function()? disconnectVpnImpl;
  Future<bool> Function()? isVpnRunningImpl;
  Future<void> Function(String content, {...})? startCoreWithContentImpl;

  Future<void> connect();
  Future<dynamic> _call(String method, [Map<String, dynamic>? params]);
}
```

### IosVpnBridge

iOS 专属桥接层，将 VPN 生命周期方法注入 `IpcWorker`：

```dart
class IosVpnBridge {
  static const _channel = MethodChannel('cn.mapleafgo/singcast');

  Future<String> appGroupSocketPath();
  void wireInto(IpcWorker worker, {required void Function() onVpnDisconnected});
}
```

---

## 数据流示例

### 切换代理节点

```
User clicks proxy
  → Flutter UI calls LibCore.selectProxy(group, tag)
  → IpcWorker._call('proxy.select', {group, tag})
  → RPC over App Group socket
  → Extension's sing-box kernel updates selection
  → Response back to Dart
  → UI updates
```

### 开启 VPN (iOS)

```
User toggles VPN on
  → LibCore.connectVpn(config)
  → IosVpnBridge._connectVpn() via MethodChannel
  → AppDelegate.connectVpn
  → NETunnelProviderManager.loadAllFromPreferences
  → session.startVPNTunnel()
  → System launches ExtensionProvider
  → ExtensionProvider.startTunnel
    ├─ singcast.init_(home_dir)
    ├─ singcast.startIpcServer(socketPath)
    ├─ singcast.setTunFd(fd)
    └─ singcast.startWithContent(config)
  → Back in main app: connectIpc()
  → IpcWorker.connect() to App Group socket
  → syncKernelState()
  → UI shows connected
```

---

## 常见问题

### Q: 为什么 iOS 不直接用 FFI？

A: iOS 系统要求 VPN 功能必须在 `NEPacketTunnelProvider` Extension 中实现，主 App 无法直接创建 TUN 设备。这是苹果的安全沙箱限制。

### Q: App Group socket 会不会被系统杀死？

A: App Group 是苹果官方提供的进程间通信机制，只要 Extension 进程存活，socket 就可用。系统在内存紧张时可能杀死 Extension，此时主 App 会通过 `onVpnDisconnected` 回调感知并更新 UI。

### Q: 为什么桌面端要独立进程？

A: 独立进程有以下优势：
1. 崩溃隔离：内核崩溃不影响主 App UI
2. 权限分离：TUN 模式需要管理员权限，独立进程可单独提权
3. 资源清理：进程退出时系统自动回收所有资源
