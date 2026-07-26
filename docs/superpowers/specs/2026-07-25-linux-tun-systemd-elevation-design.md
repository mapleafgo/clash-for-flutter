# Linux TUN 系统级 systemd 提权设计

> **实现说明（2026-07-25 更新）**：按本设计落地系统级 systemd 服务方案
> （`User=singcast` + AmbientCapabilities + polkit 放行 resolve1 set/revert +
> 本地 active 用户 start/stop/restart unit + `/run/singcast/command.sock` ACL）。
> 不以用户态 setcap 作为 Linux 主路径。

> 日期：2026-07-25
> 范围：`singcast`（GUI/打包）+ `singcast-cli`（core 服务管理）
> 状态：实现中（systemd 主路径）

## 问题

开启 TUN 时，内核在 Linux 上会串行调用：

```text
resolvectl domain <if> ~.
resolvectl default-route <if> true
resolvectl dns <if> <servers>
```

这三条分别触发 polkit：

- `org.freedesktop.resolve1.set-domains`
- `org.freedesktop.resolve1.set-default-route`
- `org.freedesktop.resolve1.set-dns-servers`

当前 `singcast-core` 以普通用户 + `cap_net_admin` 运行，且多为 detached 进程，active session 的 `auth_admin_keep` 用不上，于是连续弹三次密码。热重载/重建 TUN 会重复该过程，表现为“很多次验证密码”。

现有 Linux 提权只做了 `pkexec setcap cap_net_admin+ep`，不能覆盖 systemd-resolved 的 polkit 检查。

## 目标

1. deb / rpm / AUR 安装后，开 TUN 零密码。
2. AppImage / 解压便携包：最多首次一次 pkexec 安装服务与规则，之后零密码。
3. 与 Windows “安装版走系统服务、便携版首次提权”模型对齐。
4. macOS 现有 setuid 复制方案不改。

## 非目标

- 不默认关闭 DNS hijack（会改变 TUN DNS 行为）。
- 不把 `setcap` 继续作为 Linux 主路径（可保留为极端降级，不作为设计主线）。
- 不做 Flatpak 沙箱内的完整 TUN 提权（沙箱限制另案）。

## 决策摘要

| 项 | 选择 |
|---|---|
| 服务层级 | 系统级 unit：`/etc/systemd/system/singcast-core.service` |
| 运行身份 | 固定系统用户 `singcast`（对齐官方 sing-box） |
| 能力 | `AmbientCapabilities` / `CapabilityBoundingSet`：`CAP_NET_ADMIN`、`CAP_NET_RAW`、`CAP_NET_BIND_SERVICE` 等 |
| resolved 免密 | polkit rules：`subject.user == "singcast"` 放行三条 resolve1 action |
| 用户启停 | 额外 polkit：允许本地 active 用户 start/stop/restart `singcast-core.service` |
| IPC | 服务模式使用 `/run/singcast/command.sock` |
| 用户配置 | 仍在 `~/.local/share/cn.mapleafgo.singcast`；内容经 RPC 下发 |
| 便携包 | 首次 TUN：`pkexec singcast-core service install` |
| socket 授权 | install 时对调用 uid 写 ACL（免重登）；目录由 `RuntimeDirectory=singcast` 管理 |

## 架构

```text
GUI (用户会话)
  读用户目录配置/订阅
  ServiceManager
    setup  -> pkexec service install
    start/stop -> systemctl
        |
        | unix socket /run/singcast/command.sock
        v
systemd: singcast-core
  User=singcast
  AmbientCapabilities=...
  singcast-core ipc --home /var/lib/singcast
        |
        | resolvectl x3
        v
polkit: singcast.rules
  放行 set-domains / set-default-route / set-dns-servers / revert
```

### 组件

#### 1. singcast-cli（ipc 包）

扩展现有 `service install|uninstall` CLI（Windows 已实现，Linux 现为 stub）。

**InstallService(homeDir string)（需 root）**

1. 确保系统用户 `singcast` 存在（useradd --system 或依赖 sysusers.d 已应用）。
2. 写入 unit 到 `/etc/systemd/system/singcast-core.service`。
3. 写入 polkit rules：
   - resolved set-* 与 revert 对 `singcast` 用户 YES
   - 本地 active 用户可管理该 unit 的 start/stop/restart
4. 依赖 unit 的 `RuntimeDirectory=singcast` 与 `StateDirectory=singcast`。
5. `systemctl daemon-reload`。
6. 不强制立刻 start（由 GUI start() 触发），与 Windows 手动 start 一致。
7. 对发起 install 的真实用户 uid（SUDO_USER / pkexec 调用方）为 `/run/singcast` 预置 ACL 策略：服务每次启动后 socket 对该 uid 可连（实现上可在 unit 的 ExecStartPost 或 core listen 成功后 setfacl；计划阶段写死一种）。

**UninstallService()（需 root）**

1. `systemctl stop/disable singcast-core`（忽略未运行）。
2. 删除 unit 与本包写入的 polkit rules。
3. `daemon-reload`。
4. 默认保留系统用户 `singcast`，降低卸载副作用。

**运行**

- `ipc --home <stateDir>` 仍走现有 foreground 逻辑；由 systemd 拉起时无需 Windows 式 service 包装。
- Linux 服务 state 目录：`/var/lib/singcast`（StateDirectory=singcast）。
- 服务模式 IPC：`/run/singcast/command.sock`。

**unit 关键字段（示意）**

```ini
[Unit]
Description=Singcast core service
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=singcast
Group=singcast
StateDirectory=singcast
RuntimeDirectory=singcast
RuntimeDirectoryMode=0755
ExecStart=/usr/bin/singcast-core ipc --home /var/lib/singcast
# 实际 ExecStart 路径在 install 时按二进制真实路径写入
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
Restart=on-failure
RestartSec=2
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
```

ExecStart 的二进制路径以 install 时 `os.Executable()` 解析结果写入，兼容 `/opt/Singcast/singcast-core` 与其他前缀。

若检测到 AppImage（`APPIMAGE` 环境变量）或可执行文件位于 `/tmp/`（含 FUSE 挂载点），install 会先把 core 复制到 `/var/lib/singcast/singcast-core`，unit 的 ExecStart 写该稳定路径，避免下次挂载点变化导致服务失效。

开发态路径（`/home/...`、`/root/...`）同样强制复制：systemd 以 `User=singcast` 运行时无法穿越用户 home 的 `0700` 目录，否则会出现 `status=203/EXEC`，GUI 降级直跑后 `TUNSETIFF: operation not permitted`。

**socket 权限（写死）**

- 目录：`RuntimeDirectory=singcast`，模式 `0755` 或 `0750`。
- socket：创建后 `0660`，并对 install 记录的调用方 uid 设置 ACL `u:UID:rw`（免加入组、免重登）。
- core 在 `listenPlatform` 成功后执行 ACL（服务已是 singcast 用户时，需在 unit 里给足够权限或由 root ExecStartPost 处理）。实现计划二选一写死；优先 **unit ExecStartPost 对 socket setfacl**，避免给服务进程多余 cap。

#### 2. GUI UnixServiceManager（仅 Linux）

保持 macOS 分支不变。

| 方法 | Linux 行为 |
|---|---|
| isReady() | unit 文件存在且 systemctl 可识别该 unit |
| setup() | `pkexec <core> service install --home <userHome>`；服务实际 state 固定 `/var/lib/singcast` |
| start() | `systemctl start singcast-core`；成功后 GUI 连 `/run/singcast/command.sock` |
| stop() | `systemctl stop singcast-core` |
| startDirect() | 现有：用户态拉起 bundle core + 用户目录 socket（降级） |
| uninstall() | `pkexec <core> service uninstall` |

**LibCore 调整**

- Linux 服务模式下 IpcWorker.ipcPath 使用系统 socket，而不是 homeDir/command.sock。
- 用户目录仍用于：配置、订阅、日志展示、merged cache。
- elevateService / restart / uninstallServiceAndRestart 保持“断 IPC → 操作服务 → 重连 → onProcessReady”骨架。

**探测顺序（init）**

1. 若 unit 已安装：必要时 systemctl start，连接系统 socket。
2. 否则：尝试用户目录 socket 上已有进程（兼容旧直跑）。
3. 再否则：startDirect() 降级。

#### 3. 打包

共享产物（建议 `singcast-cli/release/linux/` 与 AUR/deb 引用）：

- singcast-core.service 模板（或由 install 命令生成）
- singcast.rules（polkit）
- singcast.sysusers

**AUR / pacman**

- depends：systemd、polkit（已有）
- install 钩子：post_install / post_upgrade 创建用户、装 unit/rules、daemon-reload
- 修复 `/usr/bin/singcast` 软链写成 pkgdir 绝对路径的 bug，改为链到 `/opt/Singcast/singcast`

**deb**

- postinst 同等逻辑；postrm/prerm 按 deb 惯例处理升级与卸载

**AppImage**

- 不预装 unit
- 首次开 TUN 走 GUI setup（一次 pkexec）

## 数据流：开 TUN

### 安装版（unit 已在）

1. 用户打开 TUN
2. isReady() == true
3. 若 core 未 running：systemctl start（polkit 放行，无密码）
4. GUI 连接 /run/singcast/command.sock
5. ensureProxyMode(true) + asyncProfile -> startWithContent（含 tun）
6. core 建 TUN -> resolvectl x3 -> polkit 对 singcast YES -> 无弹窗

### 便携版首次

1. isReady() == false
2. pkexec service install（一次密码）
3. restart/start 走系统服务
4. 之后同安装版

### 降级

install/start 失败 -> startDirect() + 用户 socket；TUN 可能仍三连弹；日志明确 Fallback。

## 错误处理

| 失败点 | 行为 |
|---|---|
| pkexec 取消 | TunElevationException，不启用 TUN |
| install 写文件失败 | 返回错误，不假装 ready |
| systemctl start 失败 | 尝试 startDirect；可提示 TUN 受限 |
| socket 权限不足 | 日志 error；走 reconnect；可提示重新 setup |
| uninstall 部分失败 | 尽量继续删剩余文件并 daemon-reload |

## 测试要点

### singcast-cli

1. unit 生成内容含 User=singcast、AmbientCapabilities、ExecStart 路径。
2. polkit rules 含 resolve1 set-* + revert 与 singcast 用户；manage-units 限 start/stop/restart。
3. 集成（需 root 或 skip）：install 后文件存在，uninstall 后消失。
4. socket ACL/权限路径有测试或文档化手工步骤。

### singcast GUI

1. Linux isReady 在无 unit / 有 unit 两种返回。
2. setup 调用参数为 service install（mock Process）。
3. 服务模式 ipcPath 为系统路径。
4. macOS setuid 路径不被误改。

### 手工验收

1. 安装 unit 后开 TUN：0 次密码，DNS/路由正常。
2. 无 unit 时开 TUN：1 次 pkexec，其后 0 次。
3. 关开 TUN、热重载：无 resolved 三连弹。
4. 关于页移除提权后降级到内置 core。

## 风险与缓解

| 风险 | 缓解 |
|---|---|
| 用户加入组需重登 | 用 ACL 授给调用 uid |
| 多用户共用一个服务 | 接受单实例；配置由当前 GUI 经 RPC 下发 |
| 包升级覆盖 unit | post_upgrade 重装并 daemon-reload |
| 与旧 setcap 残留并存 | isReady 以 systemd unit 为准 |

## 实现顺序

1. singcast-cli：Linux InstallService/UninstallService + 生成文件 + 测试
2. singcast-cli：RuntimeDirectory socket 路径与 ACL
3. GUI：Linux ServiceManager + ipcPath 分流
4. 打包：AUR 钩子 + deb postinst + 软链修复
5. 手工验收与文档

## 参考

- 上游 sing-tun：setSearchDomainForSystemdResolved
- 上游 sing-box：release/config/sing-box.service 与 sing-box.rules
- 本仓库 Windows：ipc/service_windows.go 与 GUI WindowsServiceManager
