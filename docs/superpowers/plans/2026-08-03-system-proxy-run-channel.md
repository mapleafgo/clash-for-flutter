# 系统代理运行通道实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Linux 系统代理模式下让 core 以 GUI 用户进程运行，TUN 模式保持 systemd 系统服务，模式切换时按「停旧内核 → 起新内核 → 重连 IPC → 下发配置」完成，失败回滚原通道。

**Architecture:** 在 `LinuxServiceManager` 增加显式运行通道状态（系统代理直跑为 intentional direct，不再是降级态），`LibCore` 新增 Linux 通道切换编排（互斥、Starting 状态、失败回滚），`core_config` 在开启系统代理/TUN 时先切换通道再下发配置。

**Tech Stack:** Flutter/Dart 3.x、signals_flutter、dart:io Process、systemd。

## Global Constraints

- 仅改 singcast GUI；不改 singcast-cli、不改 sing-box。
- Linux 系统代理通道 = GUI 用户进程（现有 direct 模式），TUN 通道 = systemd 系统服务。
- 模式切换固定四步：停止当前通道内核 → 启动目标通道内核 → 重连 IPC → 下发新配置。
- 切换期间 `stateSignal` 保持 `starting`；失败回滚到原通道并恢复原状态后抛错。
- 系统代理/TUN 不持久化，维持现有 `_saveToDisk` 行为。
- 工作区有订阅功能在途改动（`lib/domain/config.dart`、`lib/services/core_config.dart` 等已 dirty），本计划**不提交、不推送**，避免把用户改动混入本功能提交。
- 代码注释与 commit message 用中文（本计划无 commit）。
- Flutter 测试命令：`flutter test`；静态检查：`dart analyze`。

---

## File Structure

| 文件 | 操作 | 职责 |
|---|---|---|
| `lib/core/service_manager_linux.dart` | 修改 | 显式通道状态：`runMode`、`requestDirectRun()`、intentional direct 语义 |
| `lib/core/lib_core.dart` | 修改 | `switchLinuxChannel()` 编排 + 失败回滚 + `LinuxCoreRunMode` 导出 |
| `lib/services/core_config.dart` | 修改 | 开启系统代理/TUN 前先切换 Linux 通道 |
| `test/core/linux_service_manager_logic_test.dart` | 修改 | 模式→通道映射与通道状态转换测试 |

---

### Task 1: Linux 通道状态与模式映射

**Files:**
- Modify: `lib/core/service_manager_linux.dart`
- Test: `test/core/linux_service_manager_logic_test.dart`

**Interfaces:**
- Consumes: 现有 `LinuxCoreRunMode`、`markSystemRun()`、`markDirectRun()`、`isDegradedRun`、`ipcPath`。
- Produces:
  - `LinuxCoreRunMode linuxRunChannelFor({required bool tunMode})` — TUN→`system`，系统代理→`direct`。
  - `LinuxServiceManager.runMode` — 当前实际通道。
  - `LinuxServiceManager.requestDirectRun()` — 显式请求直跑，清除降级 sticky。
  - `LinuxServiceManager.markDirectRun({bool intentional = false})` — intentional 时不算降级。

- [ ] **Step 1: 写失败测试**

`test/core/linux_service_manager_logic_test.dart` 追加：

```dart
  test('linuxRunChannelFor maps TUN to system and system proxy to direct', () {
    expect(linuxRunChannelFor(tunMode: true), LinuxCoreRunMode.system);
    expect(linuxRunChannelFor(tunMode: false), LinuxCoreRunMode.direct);
  });

  test('requestDirectRun switches system channel back to direct', () {
    final sm = LinuxServiceManager('/tmp/home');
    sm.markSystemRun();
    expect(sm.runMode, LinuxCoreRunMode.system);
    expect(sm.ipcPath, kLinuxSystemIpcPath);

    sm.requestDirectRun();

    expect(sm.runMode, LinuxCoreRunMode.direct);
    expect(sm.ipcPath, ServiceManager.defaultIpcPath('/tmp/home'));
    expect(sm.isDegradedRun, isFalse);

    sm.markSystemRun();
    expect(sm.runMode, LinuxCoreRunMode.system);
    expect(sm.ipcPath, kLinuxSystemIpcPath);
  });
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/core/linux_service_manager_logic_test.dart`

Expected: FAIL（`linuxRunChannelFor` 未定义、`requestDirectRun` 未定义）。

- [ ] **Step 3: 实现**

`lib/core/service_manager_linux.dart`：

```dart
/// Linux core 实际运行通道。
enum LinuxCoreRunMode { system, direct }

/// TUN 模式走系统服务通道，系统代理走 GUI 用户进程通道。
LinuxCoreRunMode linuxRunChannelFor({required bool tunMode}) =>
    tunMode ? LinuxCoreRunMode.system : LinuxCoreRunMode.direct;
```

类内字段区新增 `runMode` getter：

```dart
  /// 当前实际运行通道。
  LinuxCoreRunMode get runMode => _runMode;
```

新增 `_directRequested` 字段并调整降级判断：

```dart
  /// 系统代理显式要求直跑；isReady 探测时不要切回 system，也不算降级。
  bool _directRequested = false;
```

```dart
  /// unit 已装但当前直跑（ACL/连接失败后的降级态）。
  /// 系统代理显式要求的直跑不算降级。
  bool get isDegradedRun =>
      _unitInstalled &&
      _runMode == LinuxCoreRunMode.direct &&
      !_directRequested;
```

调整 `markSystemRun` 并新增 `requestDirectRun`：

```dart
  /// 标记当前为系统服务运行，清除降级 sticky 与系统代理直跑标记。
  void markSystemRun() {
    _runMode = LinuxCoreRunMode.system;
    _directRequested = false;
    _degradedSticky = false;
  }

  /// 系统代理通道：显式要求直跑，isReady 不再切回 system。
  void requestDirectRun() {
    _runMode = LinuxCoreRunMode.direct;
    _directRequested = true;
    _degradedSticky = false;
  }
```

调整 `markDirectRun`：

```dart
  /// 标记当前为直跑。系统代理直跑为 intentional；否则若 unit 已装，
  /// 设置 sticky 防止 isReady 自动切回 system。
  void markDirectRun({bool intentional = false}) {
    _runMode = LinuxCoreRunMode.direct;
    if (intentional) {
      _directRequested = true;
      _degradedSticky = false;
    } else {
      _directRequested = false;
      if (_unitInstalled) _degradedSticky = true;
    }
  }
```

调整 `isReady`：

```dart
      final ready = result.exitCode == 0;
      _unitInstalled = ready;
      if (!ready) {
        _runMode = LinuxCoreRunMode.direct;
        _degradedSticky = false;
        _directRequested = false;
      } else if (_directRequested) {
        // 系统代理：unit 在也保持用户进程通道
        _runMode = LinuxCoreRunMode.direct;
      } else if (!_degradedSticky) {
        // 冷启动：unit 在且未降级过，优先系统服务
        _runMode = LinuxCoreRunMode.system;
      }
```

`uninstall` 重置 `_directRequested`：

```dart
    _unitInstalled = false;
    _runMode = LinuxCoreRunMode.direct;
    _degradedSticky = false;
    _directRequested = false;
```

`startDirect` 保留 intentional 标记：

```dart
      _directProcess = await Process.start(ServiceManager.serviceBinaryPath(), [
        'ipc',
        '--home',
        homeDir,
      ], mode: ProcessStartMode.detached);
      _directPid = _directProcess?.pid;
      markDirectRun(intentional: _directRequested);
      return true;
```

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/core/linux_service_manager_logic_test.dart`

Expected: PASS。

- [ ] **Step 5: 检查工作区（不提交）**

Run: `git status --short`

Expected: 仅新增本计划文件与后续改动文件；不执行 `git add`/`git commit`。

---

### Task 2: LibCore Linux 通道切换编排

**Files:**
- Modify: `lib/core/lib_core.dart`

**Interfaces:**
- Consumes: `LinuxServiceManager` 的 `runMode`、`requestDirectRun()`、`markSystemRun()`、`isReady()`、`setup()`、`reinstallForCurrentUser()`、`stop()`、`start()`、`ipcPath`；现有 `_exclusive`、`_rebindIpcWorker`、`_connectWithRetry`、`syncKernelState`。
- Produces:
  - `Future<void> LibCore.switchLinuxChannel(LinuxCoreRunMode target)` — 停止旧通道、启动新通道、重连 IPC；失败回滚。
  - `LinuxCoreRunMode` 通过 `lib_core.dart` 导出给 `core_config.dart` 使用。

- [ ] **Step 1: 实现导出与切换方法**

`lib/core/lib_core.dart` 导出列表改为：

```dart
export 'service_manager.dart'
    show LinuxServiceManager, UnixServiceManager, LinuxCoreRunMode, linuxRunChannelFor;
```

在 `restart()` 方法后新增：

```dart
  /// Linux 运行通道切换：停止当前内核、启动目标通道内核、重连 IPC。
  ///
  /// 切换期间 stateSignal 保持 starting；失败时回滚到原通道并恢复原状态后
  /// 重新抛出。成功后 onProcessReady 会被调用，由调用方继续下发新配置。
  Future<void> switchLinuxChannel(LinuxCoreRunMode target) async {
    final sm = _serviceManager;
    if (!Constants.isDesktop || !Platform.isLinux || sm is! LinuxServiceManager) {
      return;
    }
    await _exclusive('switch-channel', () async {
      final currentMode = sm.runMode;
      if (currentMode == target) {
        if (target == LinuxCoreRunMode.direct) {
          sm.requestDirectRun();
        }
        return;
      }
      final previousMode = currentMode;
      final previousState = stateSignal.peek();
      final sw = Stopwatch()..start();
      LogFileWriter.instance?.log(
        'switch Linux channel start: target=${target.name} '
        'current=${previousMode.name} state=$previousState',
        name: 'ipc',
      );
      stateSignal.value = kStateStarting;
      _clearRuntimeState();
      try {
        await _restartLinuxChannel(sm, target);
        await syncKernelState();
        LogFileWriter.instance?.log(
          'switch Linux channel done: target=${target.name} '
          'elapsed_ms=${sw.elapsedMilliseconds}',
          name: 'ipc',
        );
        try {
          await onProcessReady?.call();
        } catch (e) {
          LogFileWriter.instance?.log(
            'onProcessReady after channel switch failed: $e',
            level: LogLevel.warning,
            name: 'ipc',
          );
        }
      } catch (e) {
        LogFileWriter.instance?.log(
          'switch Linux channel to ${target.name} failed: $e, '
          'rolling back to ${previousMode.name}, '
          'elapsed_ms=${sw.elapsedMilliseconds}',
          level: LogLevel.error,
          name: 'ipc',
        );
        await _rollbackLinuxChannel(sm, previousMode, previousState);
        rethrow;
      }
    });
  }

  /// 停止当前通道内核、启动目标通道内核并重连 IPC（不触发配置下发）。
  Future<void> _restartLinuxChannel(
    LinuxServiceManager sm,
    LinuxCoreRunMode target,
  ) async {
    try {
      await stopCore().timeout(const Duration(seconds: 5));
    } catch (_) {}
    await _ipcWorker?.disconnect();
    await sm.stop();
    LogFileWriter.instance?.log(
      'switch Linux channel: old core stopped (mode=${sm.runMode.name})',
      name: 'ipc',
    );

    if (target == LinuxCoreRunMode.direct) {
      sm.requestDirectRun();
    } else if (!await sm.isReady()) {
      if (!await sm.setup()) {
        throw StateError('Failed to install system service');
      }
    } else if (sm.isDegradedRun) {
      if (!await sm.reinstallForCurrentUser()) {
        throw StateError('Failed to refresh system service ACL');
      }
    } else {
      sm.markSystemRun();
    }

    await _rebindIpcWorker(sm.ipcPath);
    if (!await sm.start()) {
      throw StateError('Failed to start ${target.name} core');
    }
    if (!await _connectWithRetry(attempts: 20)) {
      throw StateError('Failed to connect IPC after channel switch');
    }
    LogFileWriter.instance?.log(
      'switch Linux channel: ${target.name} core started and IPC reconnected',
      name: 'ipc',
    );
  }

  /// 切换失败后恢复原通道并重连 IPC；原状态为 running 时同步回 running。
  Future<void> _rollbackLinuxChannel(
    LinuxServiceManager sm,
    LinuxCoreRunMode previous,
    String previousState,
  ) async {
    final sw = Stopwatch()..start();
    try {
      await _ipcWorker?.disconnect();
      await sm.stop();
      if (previous == LinuxCoreRunMode.system) {
        sm.markSystemRun();
      } else {
        sm.requestDirectRun();
      }
      await _rebindIpcWorker(sm.ipcPath);
      if (!await sm.start()) {
        throw StateError('Failed to rollback to ${previous.name} core');
      }
      if (!await _connectWithRetry(attempts: 20)) {
        throw StateError('Failed to connect IPC after rollback');
      }
      await syncKernelState(fallback: previousState);
      try {
        await onProcessReady?.call();
      } catch (e) {
        LogFileWriter.instance?.log(
          'onProcessReady after rollback failed: $e',
          level: LogLevel.warning,
          name: 'ipc',
        );
      }
      LogFileWriter.instance?.log(
        'switch Linux channel rolled back to ${previous.name}, '
        'elapsed_ms=${sw.elapsedMilliseconds}',
        level: LogLevel.warning,
        name: 'ipc',
      );
    } catch (e) {
      stateSignal.value = kStateDestroyed;
      LogFileWriter.instance?.log(
        'rollback Linux channel failed: $e, '
        'elapsed_ms=${sw.elapsedMilliseconds}',
        level: LogLevel.error,
        name: 'ipc',
      );
    }
  }
```

- [ ] **Step 2: 静态检查**

Run: `dart analyze lib/core/lib_core.dart`

Expected: 无错误。

- [ ] **Step 3: 回归测试**

Run: `flutter test test/core/linux_service_manager_logic_test.dart`

Expected: PASS（Task 1 状态逻辑未回归）。

---

### Task 3: core_config 接入通道选择

**Files:**
- Modify: `lib/services/core_config.dart`

**Interfaces:**
- Consumes: `LibCore.instance.switchLinuxChannel`、`LinuxCoreRunMode`（Task 2 导出）。
- Produces: 开启系统代理/TUN 时先切换 Linux 通道，再改配置并热重载。

- [ ] **Step 1: 修改 enableSystemProxy**

```dart
Future<void> enableSystemProxy() async {
  if (!Constants.isDesktop) return;
  if (Platform.isLinux) {
    await LibCore.instance.switchLinuxChannel(
      linuxRunChannelFor(tunMode: false),
    );
  }
  _updateConfig(
    (c) => c.copyWith(systemProxy: true, tun: TunConfig(enable: false)),
  );
  await asyncProfile();
}
```

- [ ] **Step 2: 修改 _enableTunDesktop**

```dart
Future<void> _enableTunDesktop() async {
  final svc = LibCore.instance.serviceManager;
  if (Platform.isLinux) {
    // 系统代理直跑时先切到 systemd 服务通道，再下发 TUN 配置
    await LibCore.instance.switchLinuxChannel(
      linuxRunChannelFor(tunMode: true),
    );
  } else if (svc != null && !await svc.isReady()) {
    final ok = await LibCore.instance.elevateService();
    if (!ok) {
      throw TunElevationException(t.core.elevationFailed);
    }
    try {
      await LibCore.instance.restart();
    } on StateError catch (e) {
      throw TunElevationException(e.message);
    }
    // restart → onProcessReady 已用 ensureProxyMode + asyncProfile 完成重载
    return;
  }
  _applyTunConfig(true);
  asyncProfile();
}
```

删除原 Linux 专属的 `svc is LinuxServiceManager && svc.isDegradedRun` 分支（已由 `switchLinuxChannel` 内部的 reinstall 逻辑接管）。

- [ ] **Step 3: 运行确认**

Run: `flutter test test/services/core_config_test.dart`

Expected: PASS。

- [ ] **Step 4: 全量静态检查**

Run: `dart analyze`

Expected: 无错误。

---

### Task 4: 全量验证与手工验收

**Files:** 无新增。

- [ ] **Step 1: 全量测试**

Run: `flutter test`

Expected: 全部 PASS。

- [ ] **Step 2: 检查改动范围**

Run: `git diff --stat`

Expected: 仅 `lib/core/service_manager_linux.dart`、`lib/core/lib_core.dart`、`lib/services/core_config.dart`、`test/core/linux_service_manager_logic_test.dart` 与本计划文件新增/修改；订阅功能在途改动原样保留。

- [ ] **Step 3: Linux 真机验收清单（发布前执行）**

1. 开启系统代理：`gsettings get org.gnome.system.proxy mode` 为 `manual`，host/port 指向 mixed inbound（默认 `127.0.0.1:7890`）；关闭后恢复 `none`。
2. 开启系统代理期间 core 为用户进程（`ps -ef | grep singcast-core` 归属 GUI 用户），`systemctl status singcast-core` 不运行。
3. 切换 TUN：core 转 systemd 服务（`User=singcast`），IPC 重连正常，系统代理开关互斥。
4. 切换失败（如拒绝 pkexec）时 UI 报错，原通道内核仍在运行。

- [ ] **Step 4: 收尾说明**

因工作区存在订阅功能未提交改动，本计划不执行 commit/push；最终回复中给出改动清单与验证结果，提交动作等待用户确认。
