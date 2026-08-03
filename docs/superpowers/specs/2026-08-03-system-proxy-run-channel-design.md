# 系统代理运行通道设计

版本：v1.0
日期：2026-08-03
状态：已确认

## 背景与问题

Linux 桌面端开启“系统代理”时，GUI 会把 `set_system_proxy: true` 写进
mixed inbound，交给 sing-box 内核设置系统代理。sing-box 的 Linux 实现以
**进程用户**身份调用 `gsettings`/`kwriteconfig5` 写入桌面会话。

当前 core 默认以 systemd 系统服务运行（`User=singcast`），进程没有桌面用户的
D-Bus 会话环境（无 `DISPLAY`、`DBUS_SESSION_BUS_ADDRESS`、`XDG_RUNTIME_DIR`）。
实际表现为：

```text
gsettings: failed to commit changes to dconf:
无法在没有 X11 $DISPLAY 的情况下自动启动 D-Bus
```

且 `gsettings` 该场景退出码仍为 0，sing-box 认为设置成功，core 不报错，
桌面系统代理却始终没有写入。

## 目标

1. Linux 系统代理模式下，core 以 GUI 用户会话进程运行，sing-box 的
   `set_system_proxy` 能正常写入桌面代理。
2. TUN 模式保持现有 systemd 系统服务（`User=singcast`）运行。
3. 不改 sing-box 内核，不改 singcast-cli 内核侧逻辑。
4. 架构可复用到 Windows/macOS：系统代理走用户通道，TUN 走提权通道。

## 非目标

- 不做系统代理异常残留清理（还原由 sing-box Close 负责）。
- 不向系统服务注入桌面会话环境（`DISPLAY`/D-Bus），避免破坏服务隔离。
- 不做独立的桌面代理助手进程。

## 模型

**模式决定内核运行通道**：

| 模式 | 内核通道 | 系统代理 |
|---|---|---|
| 系统代理 | 用户进程（Linux 现有 direct 模式） | sing-box 自己写桌面会话 |
| TUN | systemd 系统服务（现有） | 不需要 |

## 切换流程

模式切换固定四步：

1. 停止当前通道的内核。
2. 启动目标通道的内核。
3. 重连 IPC。
4. 下发新配置。

开启系统代理时：若当前为系统服务通道，先停服务、再启动用户进程。
开启 TUN 时：若当前为用户进程通道，先停用户进程、再走现有
`elevateService()` 启动系统服务。

切换期间 GUI 状态保持 `Starting`；失败时留在原通道、回滚状态并报错。

## 测试

1. 单元测试：模式到通道的映射与切换顺序。
2. Linux 真机验证：开启系统代理后 `gsettings get org.gnome.system.proxy mode`
   为 `manual` 且 host/port 指向 mixed inbound；关闭后恢复 `none`。
3. 回归：TUN 模式仍走系统服务，IPC 重连正常，模式互斥不变。

## 涉及范围

- `singcast` GUI：`service_manager_linux.dart`、`core_config.dart` 等运行通道选择逻辑。
- `singcast-cli`：不改。
- `sing-box`：不改。
