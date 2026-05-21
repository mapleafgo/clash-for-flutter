# 桌面端特权分离设计

日期: 2026-05-20

## 目标

将桌面端（Windows/macOS/Linux）的 sing-box 内核从 Flutter GUI 进程中拆出，运行在独立的特权服务进程中。GUI 始终以普通用户权限运行，特权操作（TUN 等）委托给平台原生的特权服务。

## 关键决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 服务语言 | Go（嵌入 sing-box 库） | sing-box 本身是 Go，直接 import core 包 |
| IPC 协议 | JSON-RPC 2.0 | 简单可读，调试方便 |
| IPC 传输 | Unix Socket (macOS/Linux) / Named Pipe (Windows) | 不占用网络端口，本地 IPC |
| Dart 端 IPC | dart_ipc 包 | 跨平台，支持 Named Pipe + Unix Socket |
| 服务生命周期 | 按需启动 | 用户不使用时零资源占用 |
| 代码位置 | 整合进 cff-core 项目 `cmd/service/` | 与现有 CLI/FFI/Mobile 入口并列 |

## 架构

```
┌─────────────────────────────────────┐
│  Flutter GUI（普通用户权限）          │
│  ┌─────────────────────────────┐    │
│  │ LibCore (抽象层)             │    │
│  │  ├─ IpcWorker (桌面端新)     │    │
│  │  └─ LibCoreChannel (移动端)  │    │
│  └──────────┬──────────────────┘    │
└─────────────┼───────────────────────┘
              │ IPC (JSON-RPC 2.0)
              │ Windows: Named Pipe
              │ macOS/Linux: Unix Socket
┌─────────────┼───────────────────────┐
│  singcast-service（特权进程）        │
│  ┌──────────┴──────────────────┐    │
│  │ Go Service                  │    │
│  │  ├─ IPC Server (ipc/)       │    │
│  │  ├─ core.Service 引擎管理   │    │
│  │  └─ 事件推送                │    │
│  └─────────────────────────────┘    │
└─────────────────────────────────────┘
```

## IPC 协议

### 请求方法（GUI → Service）

| 方法 | 参数 | 说明 |
|------|------|------|
| `core.start` | `{content, rule_set_proxy}` | 启动/重启内核（含配置） |
| `core.stop` | — | 停止内核（不退出服务进程） |
| `core.queryState` | — | 查询运行状态 |
| `core.queryStats` | — | 查询流量统计 |
| `core.queryProxies` | — | 查询代理组 |
| `core.queryConnections` | — | 查询活跃连接 |
| `core.queryMode` | — | 查询当前模式 |
| `core.queryRules` | — | 查询路由规则 |
| `core.urlTest` | `{tag, timeout_ms}` | 单节点延迟测试 |
| `core.testGroupDelay` | `{group_tag, timeout_ms}` | 组内全部节点延迟测试 |
| `core.selectOutbound` | `{group_tag, outbound_tag}` | 切换选中节点 |
| `core.setMode` | `{mode}` | 切换代理模式 |
| `core.closeConnection` | `{id}` | 关闭单个连接 |
| `core.closeConnections` | — | 关闭全部连接 |
| `core.setGroupExpand` | `{group_tag, expand}` | 设置组展开状态 |
| `core.flushFakeIP` | — | 清空 FakeIP 缓存 |
| `core.flushDNSCache` | — | 清空 DNS 缓存 |
| `core.flushSystemDNS` | — | 刷新系统 DNS |
| `core.resetNetwork` | — | 重置网络连接 |
| `core.triggerGC` | — | 强制 GC |

**简化说明：**
- `core.init` 移除，`home_dir` 通过 CLI 参数传入服务进程
- `core.destroy` 移除，服务进程退出时自动清理
- GUI 断开连接 → 服务自动清理内核 + 退出（非 TUN）或保持（TUN）

### 通知（Service → GUI）

| 通知方法 | 数据 | 说明 |
|----------|------|------|
| `event.log` | `{level, message, timestamp}` | 内核日志 |
| `event.urlTest` | — | URL 测试结果更新 |
| `event.modeUpdate` | `{mode}` | 代理模式变更 |
| `event.connEvent` | `{event, id, ...}` | 连接事件 |
| `event.stateUpdate` | `{state}` | 内核状态变更 |
| `event.trafficUpdate` | `{up, down, connections, ...}` | 每秒流量/连接数推送 |

## IPC 安全

### Unix Socket（macOS/Linux）

- Socket 目录：`/tmp/singcast-{uid}/`，权限 `0700`，owner 为当前用户
- Socket 文件：`singcast-service.sock`，权限 `0600`，仅 owner 可读写
- 启动前清理残留 socket 文件（上次崩溃遗留）：检查文件存在 → 尝试连接 → 无人监听则删除 → 重新绑定

### Named Pipe（Windows）

- 安全描述符 SDDL：`D:(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;IU)` — 仅 SYSTEM、Administrators、交互式用户可访问
- 使用 `PIPE_REJECT_REMOTE_CLIENTS` 标志阻止远程连接

## 版本兼容

| IPC 方法 | 参数 | 说明 |
|----------|------|------|
| `core.version` | — | 返回 `{version}`，用于调试 |

## GUI 崩溃与 TUN 保护

TUN 模式下服务退出会导致系统断网（路由规则指向已消失的 TUN 设备），必须保护：

- **非 TUN 模式**：GUI 断开 → 服务正常退出
- **TUN 模式**：GUI 断开 → **服务不退出**，保持 TUN 运行，等待 GUI 重连
- 服务判断逻辑：当前 `core.Service` 状态为 Running 且配置含 TUN → 保持运行
- 新 GUI 实例启动后重连已有服务，无需重启
- GUI 显式退出时发送 `core.stop` 停止内核，然后断开连接，服务自动退出

### GUI 重连

服务端：同一时间只允许一个 GUI 连接。旧连接断开后继续监听，等待新连接。

**关键原则**：GUI 不缓存状态作为权威数据，重连后一律从服务端重新查询。

```
GUI 启动 / 重连:
  尝试连接 IPC
  ├─ 成功 → 发现运行中的服务
  │   → core.queryState / queryStats / queryProxies 恢复 UI 状态
  │   → 服务自动恢复事件推送
  └─ 失败 → kill 旧进程（无副作用）→ 启动新服务 → 连接
      macOS/Linux: socket 文件存在但连接被拒 → 残留文件 → 删除 → 启动新服务
      Windows: Named Pipe 不存在 → StartService()
      → 等待 IPC 就绪（10秒超时，3次重试）→ 连接
```

## 各平台服务管理

### 双模式运行

| | 从未用过 TUN | 用过 TUN 后（setuid/Service 已设置） |
|---|---|---|
| **macOS** | `Process.start` 普通用户 | `Process.start` 自动以 root 运行（setuid） |
| **Linux** | `Process.start` 普通用户 | `Process.start` 自动以 root 运行（setuid） |
| **Windows** | `Process.start` 普通用户 | `StartService()` 以 SYSTEM 运行 |

- 从未用过 TUN 的用户永远不会看到任何提权弹窗
- 一旦设置过提权（setuid/Service），后续即使非 TUN 模式也以特权身份运行，setuid 不可逆
- 已有特权时切换 TUN 不需要重启服务，只需重新发送含 TUN 的 `core.start` 配置

### 统一接口

```dart
abstract class ServiceManager {
  Future<bool> isReady();      // setuid/Service 是否就绪（仅 TUN 需要）
  Future<bool> setup();        // 一次性提权设置（仅首次启用 TUN 时调用）
  Future<bool> isRunning();
  Future<bool> start();        // 启动服务进程
  Future<bool> stop();         // 停止服务进程
}
```

### 启用 TUN 时的流程（三平台统一）

```dart
// 用户开启 TUN 时
if (!await serviceManager.isReady()) {
  // 首次：需要一次性提权设置
  final ok = await serviceManager.setup();
  if (!ok) return;  // 用户拒绝，TUN 不启用
  // 提权后才需重启服务
  await serviceManager.stop();
  await serviceManager.start();
}
// 已有特权时无需重启，直接发送含 TUN 的配置
// （服务已在特权模式下运行）
sendCoreStart(tunConfig);
```

### Windows（setuid 不存在，用 Windows Service）

- **非 TUN**: `Process.start(singcast-service.exe)` 普通用户进程
- **TUN 提权**: `singcast-service.exe install` 触发一次 UAC，注册 Windows Service（demand start）
- **TUN 启动**: `StartService()` 以 SYSTEM 身份运行
- **IPC 路径**: `\\.\pipe\singcast-service`
- **Named Pipe 权限**: 安全描述符限制为 Interactive Users + SYSTEM/Admin
- **恢复策略**: `sc failure` 配置三层重启

### macOS（setuid 直接启动）

- **非 TUN**: `Process.start` 以普通用户运行
- **TUN 提权**: `osascript` 一次性执行 `chown root:admin` + `chmod +sx` 设置 setuid 位
- **TUN 启动**: `Process.start` 启动（因 setuid 自动以 root 运行）
- **IPC 路径**: `/tmp/singcast-{uid}/singcast-service.sock`
- **退出策略**: 非 TUN → 断开即退出；TUN 模式 → 保持运行等待重连

### Linux（setuid 直接启动）

- **非 TUN**: `Process.start` 以普通用户运行
- **TUN 提权**: `pkexec` 一次性执行 `chown root:root` + `chmod +sx` 设置 setuid 位
- **TUN 启动**: `Process.start` 启动（因 setuid 自动以 root 运行）
- **IPC 路径**: `/tmp/singcast-{uid}/singcast-service.sock`
- **退出策略**: 非 TUN → 断开即退出；TUN 模式 → 保持运行等待重连

## cff-core 项目结构

新增 `ipc/` 库包和 `cmd/service/` 入口，不修改现有代码：

```
cff-core/
├── ipc/                           # 库包：IPC 服务端逻辑（可独立测试）
│   ├── server.go                  # JSON-RPC 2.0 服务端
│   ├── handler.go                 # 方法路由 + core.Service 桥接
│   └── types.go                   # 方法名常量 + 请求/响应类型
├── cmd/
│   ├── singcast/                  # 现有 CLI（不动）
│   ├── lib/                       # 现有 FFI C 共享库（不动）
│   └── service/                   # 新增：薄入口，胶水代码
│       ├── main.go                # run 子命令（Windows 额外有 install/uninstall）
│       ├── service_windows.go     # Windows Service 框架
│       └── run_posix.go           # macOS/Linux 直接运行（无服务框架）
├── core/                          # 现有核心（不动）
├── translator/                    # 现有翻译器（不动）
└── mobile/                        # 现有移动端（不动）
```

`ipc/` 是库包，包含全部 IPC 逻辑，可独立编写单元测试。`cmd/service/` 是 `main` 包，只做三件事：创建 `core.Service`，创建 `ipc.Server`，把它们接上线，交给平台服务框架运行。

### 核心复用

```go
// cmd/service/main.go — 薄入口
svc := core.NewService()
srv := ipc.NewServer(svc, ipcPath)  // ipc 包负责 JSON-RPC + 事件桥接
svc.SetOnEvent(srv.OnCoreEvent)     // core 回调自动桥接为 JSON-RPC 通知
run(srv)                            // 交给平台服务框架
```

### Taskfile 构建

```yaml
service-linux-amd64:
  cmds:
    - CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -tags '{{.BUILDTAGS}}' -ldflags '{{.LDFLAGS}}' -o {{.BINDIR}}/singcast-service-linux-amd64 ./cmd/service

service-darwin-arm64: ...
service-windows-amd64: ...
```

## Dart 端 IpcWorker

替换 `FfiWorker`，实现 `LibCore` 的桌面端后端：

```dart
class IpcWorker {
  IpcClient _client;
  ServiceManager _svc;
  StreamController _events;

  Future<void> connect() async {
    try {
      await _client.connect();
    } catch (_) {
      await _svc.start();
      await _client.connect();
    }
  }

  // 对应 LibCore 方法
  Future<void> init(String homeDir);
  Future<void> startWithContent(String content);
  Future<void> stop();
  Future<void> destroy();
  Future<String> queryState();

  // 事件流（替代现有 _handleWorkerCallback + _poll）
  Stream<LogEvent> get onLog;
  Stream<UrlTestEvent> get onUrlTest;
  Stream<StateUpdate> get onStateUpdate;
  Stream<TrafficUpdate> get onTrafficUpdate;
}
```

**关键变化：**
- 移除 isolate 模型（IPC 本身异步，不需要 isolate 隔离 FFI）
- 移除 `_poll()` 轮询，改为服务端每秒推送 `trafficUpdate`
- `LibCore` 公开 API 保持不变，上层代码零改动
- 连接事件单一来源（服务端推送），不再有双数据源

## IPC 传输层

### 消息帧格式

NDJSON（换行分隔 JSON）：每条 JSON-RPC 消息一行，以 `\n` 结尾。双方按行读写，无需解析 Content-Length 头。

```
{"jsonrpc":"2.0","method":"core.start","params":{"content":"..."},"id":1}\n
{"jsonrpc":"2.0","result":{"state":"running"},"id":1}\n
{"jsonrpc":"2.0","method":"event.trafficUpdate","params":{"up":1234,"down":5678}}\n
```

### 请求超时

| 操作类型 | 超时 | 示例 |
|---------|------|------|
| 普通 | 5s | queryState, queryStats, selectOutbound, setMode |
| 重量级 | 30s | core.start, core.stop, urlTest, testGroupDelay |

超时后 GUI 侧直接报错，用户手动触发重连。

### 服务无响应处理

请求超时且服务进程仍在时，kill 旧进程 → 启动新服务 → 重新连接。

## 迁移策略

1. 纯 IPC 模式，完全移除桌面端 FFI 路径
2. 移动端不变，继续用 `LibCoreChannel`（MethodChannel）
3. 移除 `lib/core/ffi_worker.dart`、`lib/core/ffi_bindings.dart`
4. 移除 `cmd/lib/` FFI 入口（桌面端不再需要，移动端用 mobile/）
5. 移除 `lib/core/win_elevation.dart`、`lib/core/tun_elevation.dart`（提权逻辑转移到 ServiceManager）
6. 内核二进制随应用包分发，无独立更新机制

## 服务生命周期

### 非 TUN 模式（三平台统一）

```
GUI 启动:
  Process.start(singcast-service, ["run", "--home-dir", "~/.singcast", "--ipc-path", ...])
  → 以普通用户身份运行 → 等待 IPC 就绪 → 连接 → 发送 core.start(config)

GUI 退出:
  断开 IPC 连接 → 服务自动清理内核 → 自行退出
```

### 首次启用 TUN

```
用户开启 TUN:
  检查提权状态 → 未就绪 → 弹窗请求提权
    macOS: osascript → chown root + chmod +sx
    Linux: pkexec → chown root + chmod +sx
    Windows: UAC → singcast-service.exe install → 注册 Service
  → 停止当前普通服务 → 以特权模式重启服务
  → 发送含 TUN 配置的 core.start → TUN 生效
```

### 后续启动（TUN 已设置过）

```
macOS/Linux:
  Process.start(singcast-service) → setuid 自动以 root 运行 → TUN 直接可用

Windows:
  StartService() → SYSTEM 身份运行 → TUN 直接可用
```
