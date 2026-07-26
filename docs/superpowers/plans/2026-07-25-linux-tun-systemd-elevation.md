# Linux TUN systemd 提权实现计划

> **状态（2026-07-25）**：systemd 主路径已恢复实现；polkit 额外放行 `resolve1.revert`，manage-units 限 start/stop/restart。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Linux 开 TUN 时 `resolvectl` 三连弹窗消失——安装包预装 systemd 服务 + polkit 规则，便携包首次一次 pkexec 安装，之后零密码。

**Architecture:** singcast-cli 新增 Linux `service install/uninstall`（写 systemd unit + polkit rules + sysusers + tmpfiles），服务以系统用户 `singcast` 跑、带 AmbientCapabilities；GUI 的 `UnixServiceManager` Linux 分支改为 `systemctl` 启停 + 连接 `/run/singcast/command.sock`；macOS 分支不动。

**Tech Stack:** Go 1.26 (singcast-cli), systemd, polkit, Flutter/Dart (singcast GUI), shell (packaging)

## Global Constraints

- singcast-cli build tags：`with_clash_api,with_utls,with_quic,with_gvisor`（不可省略）
- Go 测试：`go test -tags 'with_clash_api,with_utls,with_quic,with_gvisor' ./ipc/...`
- singcast-cli go.mod 路径：`github.com/mapleafgo/singcast`
- 服务名常量：`singcast-core`（unit 名 `singcast-core.service`）
- 系统用户：`singcast`，state 目录 `/var/lib/singcast`，runtime 目录 `/run/singcast`
- 系统 IPC socket 路径：`/run/singcast/command.sock`
- macOS 分支（setuid 复制方案）保持不变，本计划不修改任何 `Platform.isMacOS` 分支
- 文档/注释用中文，代码标识符用英文
- 每个任务结束 commit

---

## File Structure

### singcast-cli（Go）

| 文件 | 操作 | 职责 |
|---|---|---|
| `ipc/service_linux_assets.go` | 新建 | 纯函数：生成 unit / polkit rules / sysusers 文本内容 |
| `ipc/service_linux_assets_test.go` | 新建 | 验证生成内容 |
| `ipc/service_linux.go` | 新建 | `InstallService` / `UninstallService` Linux 实现 |
| `ipc/service_posix.go` | 修改 | build constraint 改为 `darwin`（排除 linux） |
| `ipc/server.go` | 修改 | `IpcPath()` 支持 env 覆盖 |
| `ipc/listen_posix.go` | 修改 | listen 后按 GUI uid 写 ACL |
| `ipc/service_linux_test.go` | 新建 | install 文件列表 + 集成测试（无 root skip） |
| `release/linux/singcast.sysusers` | 新建 | sysusers 静态产物（打包引用） |

### singcast（Dart GUI）

| 文件 | 操作 | 职责 |
|---|---|---|
| `lib/core/service_manager.dart` | 修改 | Linux 分支改为 systemd |
| `test/services/service_manager_test.dart` | 新建 | Linux isReady / setup 逻辑测试 |
| `lib/core/lib_core.dart` | 修改 | 服务模式 ipcPath 分流 |

### 打包

| 文件 | 操作 | 职责 |
|---|---|---|
| `aurpkg/singcast/PKGBUILD`（外部） | 修改 | install 钩子 + 软链修复 |
| `aurpkg/singcast/singcast.install` | 新建 | post_install / post_upgrade / pre_remove |
| `linux/packaging/deb/scripts/` | 新建 | postinst / prerm |

---

### Task 1: Linux 资产生成器（纯函数 + 测试）

**Files:**
- Create: `singcast-cli/ipc/service_linux_assets.go`
- Test: `singcast-cli/ipc/service_linux_assets_test.go`

**Interfaces:**
- Produces: `linuxInstallFiles(execPath, stateDir, guiUID string) []linuxFile`、`linuxUninstallPaths() []string`、类型 `linuxFile{Path, Content string; Mode os.FileMode}`

- [ ] **Step 1: 编写失败的测试**

创建 `ipc/service_linux_assets_test.go`：

```go
//go:build linux

package ipc

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestLinuxInstallFiles_ContainsUnit(t *testing.T) {
	files := linuxInstallFiles("/opt/Singcast/singcast-core", "/var/lib/singcast", "1000")
	unit := findFile(t, files, "/etc/systemd/system/singcast-core.service")
	require.Contains(t, unit.Content, "User=singcast")
	require.Contains(t, unit.Content, "Group=singcast")
	require.Contains(t, unit.Content, "AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE")
	require.Contains(t, unit.Content, "ExecStart=/opt/Singcast/singcast-core ipc --home /var/lib/singcast")
	require.Contains(t, unit.Content, "RuntimeDirectory=singcast")
	require.Contains(t, unit.Content, "StateDirectory=singcast")
}

func TestLinuxInstallFiles_ContainsPolkitRules(t *testing.T) {
	files := linuxInstallFiles("/opt/Singcast/singcast-core", "/var/lib/singcast", "1000")
	rules := findFile(t, files, "/usr/share/polkit-1/rules.d/singcast.rules")
	require.Contains(t, rules.Content, "org.freedesktop.resolve1.set-domains")
	require.Contains(t, rules.Content, "org.freedesktop.resolve1.set-default-route")
	require.Contains(t, rules.Content, "org.freedesktop.resolve1.set-dns-servers")
	require.Contains(t, rules.Content, `subject.user == "singcast"`)
	// 用户启停该 unit 的规则
	require.Contains(t, rules.Content, "singcast-core.service")
}

func TestLinuxInstallFiles_ContainsSysusers(t *testing.T) {
	files := linuxInstallFiles("/opt/Singcast/singcast-core", "/var/lib/singcast", "1000")
	conf := findFile(t, files, "/usr/lib/sysusers.d/singcast.conf")
	require.Contains(t, conf.Content, "u singcast")
	require.Contains(t, conf.Content, "/var/lib/singcast")
}

func TestLinuxInstallFiles_GUIUIDInUnitEnv(t *testing.T) {
	files := linuxInstallFiles("/opt/Singcast/singcast-core", "/var/lib/singcast", "1000")
	unit := findFile(t, files, "/etc/systemd/system/singcast-core.service")
	require.Contains(t, unit.Content, "SINGCAST_GUI_UID=1000")
	require.Contains(t, unit.Content, "SINGCAST_IPC_PATH=/run/singcast/command.sock")
}

func TestLinuxUninstallPaths(t *testing.T) {
	paths := linuxUninstallPaths()
	require.Contains(t, paths, "/etc/systemd/system/singcast-core.service")
	require.Contains(t, paths, "/usr/share/polkit-1/rules.d/singcast.rules")
	require.Contains(t, paths, "/usr/lib/sysusers.d/singcast.conf")
}

func findFile(t *testing.T, files []linuxFile, path string) linuxFile {
	t.Helper()
	for _, f := range files {
		if f.Path == path {
			return f
		}
	}
	t.Fatalf("file not found: %s, got: %s", path, pathsOf(files))
	return linuxFile{}
}

func pathsOf(files []linuxFile) string {
	var ss []string
	for _, f := range files {
		ss = append(ss, f.Path)
	}
	return strings.Join(ss, ", ")
}
```

- [ ] **Step 2: 运行测试验证失败**

Run: `cd /home/mapleafgo/Projects/OpenProject/singcast-cli && go test -tags 'with_clash_api,with_utls,with_quic,with_gvisor' ./ipc/ -run TestLinuxInstallFiles -v`
Expected: FAIL（函数未定义，编译错误）

- [ ] **Step 3: 实现资产生成器**

创建 `ipc/service_linux_assets.go`：

```go
//go:build linux

package ipc

import "os"

// linuxFile 描述 install 时要写入的一个文件。
type linuxFile struct {
	Path    string
	Content string
	Mode    os.FileMode
}

// systemdUnit 生成 singcast-core.service 内容。execPath 为二进制真实路径，
// stateDir 为服务 state 目录，guiUID 为发起 install 的 GUI 用户 uid（用于 socket ACL）。
func systemdUnit(execPath, stateDir, guiUID string) string {
	const tpl = `[Unit]
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
WorkingDirectory=__STATE_DIR__
Environment=SINGCAST_IPC_PATH=/run/singcast/command.sock
Environment=SINGCAST_GUI_UID=__GUI_UID__
ExecStart=__EXE__ ipc --home __STATE_DIR__
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
Restart=on-failure
RestartSec=2
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
`
	out := tpl
	out = replaceAll(out, "__EXE__", execPath)
	out = replaceAll(out, "__STATE_DIR__", stateDir)
	out = replaceAll(out, "__GUI_UID__", guiUID)
	return out
}

// polkitRules 生成放行 resolved 三条 action（对 singcast 用户）
// 以及允许本地 active 用户启停 singcast-core.service 的 polkit 规则。
func polkitRules() string {
	return `polkit.addRule(function(action, subject) {
    if ((action.id == "org.freedesktop.resolve1.set-domains" ||
         action.id == "org.freedesktop.resolve1.set-default-route" ||
         action.id == "org.freedesktop.resolve1.set-dns-servers") &&
        subject.user == "singcast") {
        return polkit.Result.YES;
    }
});

polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.systemd1.manage-units" &&
        subject.active == true && subject.local == true &&
        action.lookup("unit") == "singcast-core.service") {
        return polkit.Result.YES;
    }
});
`
}

// sysusersConf 生成系统用户声明（打包 postinst 兜底用）。
func sysusersConf() string {
	return `u singcast - "Singcast core service" /var/lib/singcast
`
}

// linuxInstallFiles 返回 install 时要写入的全部文件。
func linuxInstallFiles(execPath, stateDir, guiUID string) []linuxFile {
	return []linuxFile{
		{Path: "/etc/systemd/system/singcast-core.service", Content: systemdUnit(execPath, stateDir, guiUID), Mode: 0o644},
		{Path: "/usr/share/polkit-1/rules.d/singcast.rules", Content: polkitRules(), Mode: 0o644},
		{Path: "/usr/lib/sysusers.d/singcast.conf", Content: sysusersConf(), Mode: 0o644},
	}
}

// linuxUninstallPaths 返回 uninstall 时要删除的文件路径。
func linuxUninstallPaths() []string {
	return []string{
		"/etc/systemd/system/singcast-core.service",
		"/usr/share/polkit-1/rules.d/singcast.rules",
		"/usr/lib/sysusers.d/singcast.conf",
	}
}

func replaceAll(s, old, new string) string {
	out := ""
	for {
		i := indexOf(s, old)
		if i < 0 {
			break
		}
		out += s[:i] + new
		s = s[i+len(old):]
	}
	return out + s
}

func indexOf(s, sub string) int {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}
```

> 注：`replaceAll`/`indexOf` 用 `strings` 包即可（原则四：优先标准库）。Step 3 实际代码用 `strings.ReplaceAll`，这里为展示逻辑手写。最终代码用标准库版本。

- [ ] **Step 4: 运行测试验证通过**

Run: `cd /home/mapleafgo/Projects/OpenProject/singcast-cli && go test -tags 'with_clash_api,with_utls,with_quic,with_gvisor' ./ipc/ -run TestLinux -v`
Expected: PASS

- [ ] **Step 5: commit**

```bash
cd /home/mapleafgo/Projects/OpenProject/singcast-cli
git add ipc/service_linux_assets.go ipc/service_linux_assets_test.go
git commit -m "feat(ipc): 添加 Linux systemd 资产生成器"
```

---

### Task 2: Linux InstallService / UninstallService 实现

**Files:**
- Create: `singcast-cli/ipc/service_linux.go`
- Modify: `singcast-cli/ipc/service_posix.go`（build constraint 改为 darwin）
- Test: `singcast-cli/ipc/service_linux_test.go`

**Interfaces:**
- Consumes: `linuxInstallFiles` / `linuxUninstallPaths`（Task 1）
- Produces: `InstallService(homeDir string) error`、`UninstallService() error`（Linux 实现，替换 posix stub）

- [ ] **Step 1: 修改 service_posix.go 的 build constraint**

将 `ipc/service_posix.go` 第一行从 `//go:build !windows` 改为：

```go
//go:build darwin
```

这样 Linux 不再走 stub，改由 `service_linux.go` 提供。

- [ ] **Step 2: 编写失败的集成测试**

创建 `ipc/service_linux_test.go`：

```go
//go:build linux

package ipc

import (
	"os"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestInstallService_RequiresRoot(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("this test verifies non-root rejection; run as non-root")
	}
	err := InstallService("/var/lib/singcast")
	require.Error(t, err, "non-root install must fail")
}

func TestInstallService_AsRoot(t *testing.T) {
	if os.Geteuid() != 0 {
		t.Skip("requires root; run with: sudo -E go test ...")
	}
	require.NoError(t, os.MkdirAll("/var/lib/singcast", 0o755))

	require.NoError(t, InstallService("/var/lib/singcast"))

	// 验证文件存在
	for _, p := range linuxUninstallPaths() {
		_, err := os.Stat(p)
		require.NoError(t, err, "expected file after install: %s", p)
	}

	// 清理
	require.NoError(t, UninstallService())
	for _, p := range linuxUninstallPaths() {
		_, err := os.Stat(p)
		require.True(t, os.IsNotExist(err), "expected removed after uninstall: %s", p)
	}
}
```

- [ ] **Step 3: 运行测试验证失败**

Run: `go test -tags '...' ./ipc/ -run TestInstallService_AsRoot -v`
Expected: 非 root 环境 skip；root 环境因函数未实现 FAIL

- [ ] **Step 4: 实现 InstallService / UninstallService**

创建 `ipc/service_linux.go`：

```go
//go:build linux

package ipc

import (
	"errors"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"os/user"
	"strconv"
	"strings"
)

// LinuxServiceName 是 systemd unit 的名称（不含 .service 后缀）。
const LinuxServiceName = "singcast-core"

// serviceStateDir 是服务固定的 state 目录（StateDirectory=singcast）。
const serviceStateDir = "/var/lib/singcast"

// InstallService 在 Linux 上安装 systemd 服务、polkit 规则和系统用户声明。
// 必须以 root 运行；由 GUI 通过 pkexec 或打包 postinst 调用。
func InstallService(_ string) error {
	if os.Geteuid() != 0 {
		return errors.New("service install requires root (run via pkexec or package postinst)")
	}

	exe, err := os.Executable()
	if err != nil {
		return fmt.Errorf("get executable path: %w", err)
	}
	exe, err = filepath.EvalSymlinks(exe)
	if err != nil {
		return fmt.Errorf("resolve executable symlink: %w", err)
	}

	guiUID := effectiveCallerUID()

	if err := ensureServiceUser(); err != nil {
		return fmt.Errorf("ensure singcast user: %w", err)
	}
	if err := os.MkdirAll(serviceStateDir, 0o755); err != nil {
		return fmt.Errorf("create state dir: %w", err)
	}

	for _, f := range linuxInstallFiles(exe, serviceStateDir, guiUID) {
		if err := os.MkdirAll(dirOf(f.Path), 0o755); err != nil {
			return fmt.Errorf("create dir for %s: %w", f.Path, err)
		}
		if err := os.WriteFile(f.Path, []byte(f.Content), f.Mode); err != nil {
			return fmt.Errorf("write %s: %w", f.Path, err)
		}
		slog.Info("installed file", "path", f.Path)
	}

	if err := runCmd("systemctl", "daemon-reload"); err != nil {
		return fmt.Errorf("daemon-reload: %w", err)
	}
	return nil
}

// UninstallService 在 Linux 上停止、禁用并删除服务及 polkit 规则。
// 必须以 root 运行。系统用户 singcast 保留（降低卸载副作用）。
func UninstallService() error {
	if os.Geteuid() != 0 {
		return errors.New("service uninstall requires root")
	}

	// 停止/禁用，忽略未安装错误
	_ = runCmd("systemctl", "stop", LinuxServiceName+".service")
	_ = runCmd("systemctl", "disable", LinuxServiceName+".service")

	for _, p := range linuxUninstallPaths() {
		if err := os.Remove(p); err != nil && !errors.Is(err, os.ErrNotExist) {
			slog.Warn("remove install file", "path", p, "error", err)
		}
	}

	if err := runCmd("systemctl", "daemon-reload"); err != nil {
		return fmt.Errorf("daemon-reload: %w", err)
	}
	return nil
}

// ensureServiceUser 确保系统用户 singcast 存在。
func ensureServiceUser() error {
	if _, err := user.Lookup("singcast"); err == nil {
		return nil
	}
	return runCmd("useradd", "--system", "--no-create-home",
		"--home-dir", serviceStateDir,
		"--shell", "/usr/sbin/nologin",
		"singcast")
}

// effectiveCallerUID 返回发起 install 的真实用户 uid。
// pkexec 下 SUDO_USER 有值；打包 postinst 下 PKEXEC_UID 或直接当前 uid。
func effectiveCallerUID() string {
	for _, key := range []string{"PKEXEC_UID", "SUDO_UID"} {
		if v := os.Getenv(key); v != "" {
			return v
		}
	}
	if name := os.Getenv("SUDO_USER"); name != "" {
		if u, err := user.Lookup(name); err == nil {
			return u.Uid
		}
	}
	return strconv.Itoa(os.Geteuid())
}

func runCmd(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("%s %s: %w (%s)", name, strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return nil
}

func dirOf(path string) string {
	idx := strings.LastIndex(path, "/")
	if idx <= 0 {
		return "."
	}
	return path[:idx]
}
```

> 注：需要 `import "path/filepath"`，添加到 import 块。

- [ ] **Step 5: 运行测试验证通过**

Run: `go test -tags 'with_clash_api,with_utls,with_quic,with_gvisor' ./ipc/ -run TestInstallService -v`
Expected: 非 root skip 通过；root 环境 install → 验证文件 → uninstall → 验证删除，PASS

- [ ] **Step 6: commit**

```bash
cd /home/mapleafgo/Projects/OpenProject/singcast-cli
git add ipc/service_linux.go ipc/service_linux_test.go ipc/service_posix.go
git commit -m "feat(ipc): 实现 Linux systemd InstallService/UninstallService"
```

---

### Task 3: IPC 路径 env 覆盖 + socket ACL

**Files:**
- Modify: `singcast-cli/ipc/server.go`（`IpcPath()` 支持 env 覆盖）
- Modify: `singcast-cli/ipc/listen_posix.go`（listen 后按 GUI uid 写 ACL）

**Interfaces:**
- Produces: `IpcPath()` 在 `SINGCAST_IPC_PATH` 设置时返回该值

- [ ] **Step 1: 修改 IpcPath() 支持 env 覆盖**

在 `ipc/server.go` 的 `IpcPath()` 函数开头加入 env 检查：

```go
func IpcPath() string {
	// 服务模式（systemd）通过环境变量指定固定 socket 路径
	if p := os.Getenv("SINGCAST_IPC_PATH"); p != "" {
		return p
	}
	if runtime.GOOS == "windows" {
		return `\\.\pipe\singcast`
	}
	homeDir, err := os.Getwd()
	if err != nil {
		homeDir = "."
	}
	return filepath.Join(homeDir, "command.sock")
}
```

- [ ] **Step 2: 修改 listen_posix.go 加入 ACL 授权**

在 `listen_posix.go` 的 `chmod` 之后、`chown` 逻辑之前，加入 ACL 写入：

```go
	// 服务模式：允许 GUI 用户 uid 通过 ACL 连接 socket（免加入组、免重登）
	if guiUID := os.Getenv("SINGCAST_GUI_UID"); guiUID != "" {
		aclCmd := exec.CommandContext(ctx_unused, "setfacl", "-m", "u:"+guiUID+":rw", s.ipcPath)
		if out, err := aclCmd.CombinedOutput(); err != nil {
			slog.Warn("setfacl for GUI uid", "uid", guiUID, "error", err, "output", string(out))
		} else {
			slog.Info("socket ACL granted", "uid", guiUID)
		}
	}
```

> 注：`listen_posix.go` 当前无 context，ACL 用 `exec.Command`（非 Context 版）即可。import 加 `"os/exec"`。

实际修改点：在现有 `os.Chmod(s.ipcPath, 0o600)` 之后、`dirInfo, err := os.Stat(...)` 之前插入上述 ACL 块。

- [ ] **Step 3: 编译验证**

Run: `go build -tags 'with_clash_api,with_utls,with_quic,with_gvisor' ./ipc/`
Expected: 编译成功

- [ ] **Step 4: 运行全部 ipc 测试**

Run: `go test -tags 'with_clash_api,with_utls,with_quic,with_gvisor' ./ipc/ -v`
Expected: 全部 PASS（无回归）

- [ ] **Step 5: commit**

```bash
cd /home/mapleafgo/Projects/OpenProject/singcast-cli
git add ipc/server.go ipc/listen_posix.go
git commit -m "feat(ipc): IPC 路径支持 env 覆盖 + 服务模式 socket ACL"
```

---

### Task 4: GUI UnixServiceManager Linux 分支

**Files:**
- Modify: `singcast/lib/core/service_manager.dart`
- Test: `singcast/test/services/service_manager_test.dart`

**Interfaces:**
- Produces: `UnixServiceManager` 的 Linux `isReady`/`setup`/`start`/`stop`/`uninstall` 改为 systemd

- [ ] **Step 1: 编写失败的测试**

创建 `test/services/service_manager_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:singcast/core/service_manager.dart';

void main() {
  group('UnixServiceManager Linux systemd', () {
    test('ipcPath in service mode is /run/singcast/command.sock', () {
      // Linux 服务模式 ipcPath 为固定系统路径
      expect(ServiceManager.defaultIpcPath('/tmp/home'), '/tmp/home/command.sock');
      // 系统路径常量
      expect(LinuxSystemIpcPath, '/run/singcast/command.sock');
    });

    test('service name constant', () {
      expect(LinuxServiceUnitName, 'singcast-core.service');
    });
  });
}
```

- [ ] **Step 2: 运行测试验证失败**

Run: `cd /home/mapleafgo/Projects/OpenProject/singcast && flutter test test/services/service_manager_test.dart`
Expected: FAIL（`LinuxSystemIpcPath` / `LinuxServiceUnitName` 未定义）

- [ ] **Step 3: 修改 service_manager.dart**

在 `UnixServiceManager` 类中，把 Linux 分支从 setcap 改为 systemd。关键改动：

在文件顶部添加常量：

```dart
/// Linux 服务模式固定 IPC socket 路径。
const String LinuxSystemIpcPath = '/run/singcast/command.sock';

/// Linux systemd unit 名称。
const String LinuxServiceUnitName = 'singcast-core.service';
```

`isReady()` Linux 分支改为：

```dart
      if (Platform.isLinux) {
        final result = await Process.run('systemctl', ['cat', LinuxServiceUnitName]);
        return result.exitCode == 0;
      }
```

`setup()` Linux 分支改为：

```dart
      if (Platform.isLinux) {
        final svcPath = ServiceManager.serviceBinaryPath();
        final result = await Process.run('pkexec', [
          svcPath, 'service', 'install', '--home', homeDir,
        ]);
        return result.exitCode == 0;
      }
```

`start()` Linux 分支改为：

```dart
      if (Platform.isLinux) {
        final result = await Process.run('systemctl', ['start', LinuxServiceUnitName]);
        return result.exitCode == 0;
      }
```

`stop()` Linux 分支改为：

```dart
      if (Platform.isLinux) {
        final result = await Process.run('systemctl', ['stop', LinuxServiceUnitName]);
        return result.exitCode == 0;
      }
      // macOS 保留现有 _directProcess?.kill() 逻辑
```

`uninstall()` Linux 分支改为：

```dart
    if (Platform.isLinux) {
      try {
        final svcPath = ServiceManager.serviceBinaryPath();
        await Process.run('pkexec', [svcPath, 'service', 'uninstall']);
      } catch (_) {}
      return;
    }
```

新增 getter，服务模式下 ipcPath 为系统路径：

```dart
  @override
  String get ipcPath {
    if (Platform.isLinux) {
      return LinuxSystemIpcPath;
    }
    return ServiceManager.defaultIpcPath(homeDir);
  }
```

> 注意：`startDirect()` 保持现有逻辑（用户目录 socket），降级时用。`stop()` 中 macOS 的 `_directProcess?.kill()` 需保留在 `else` 分支。

**ACL 刷新策略与额外方法**：

包预装后 `isReady()` 恒为 true，但 `post_install` 以 root 跑，socket ACL 的 guiUID fallback 到 root，不含当前 GUI 用户 uid，导致首次连接系统 socket 被拒。解法：`UnixServiceManager` 新增 `refreshCallerUid()`，在连接失败时补一次幂等 install 刷新 uid。

```dart
  /// Linux: 幂等刷新调用方 uid 的 socket ACL。
  /// 在 GUI 连接系统 socket 被拒时由 lib_core 调用。
  Future<bool> refreshCallerUid() async {
    if (!Platform.isLinux) return true;
    try {
      final svcPath = ServiceManager.serviceBinaryPath();
      final result = await Process.run(
        'pkexec', [svcPath, 'service', 'install', '--home', homeDir]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
```

- [ ] **Step 4: 运行测试验证通过**

Run: `flutter test test/services/service_manager_test.dart`
Expected: PASS

- [ ] **Step 5: commit**

```bash
cd /home/mapleafgo/Projects/OpenProject/singcast
git add lib/core/service_manager.dart test/services/service_manager_test.dart
git commit -m "feat(service_manager): Linux 分支改为 systemd 启停"
```

---

### Task 5: GUI LibCore 服务模式 ipcPath 分流

**Files:**
- Modify: `singcast/lib/core/lib_core.dart`

**Interfaces:**
- Consumes: `UnixServiceManager.ipcPath`（Task 4 已改为服务模式系统路径）

- [ ] **Step 1: 确认 ipcPath 取值链路**

检查 `lib_core.dart` 中 `IpcWorker` 初始化：

```dart
_ipcWorker = IpcWorker(ipcPath: _serviceManager!.ipcPath);
```

Task 4 已让 `UnixServiceManager.ipcPath` 在 Linux 返回系统路径。确认 `init()` 中探测顺序：先连系统 socket（服务模式），失败再连用户目录（直跑模式），最后 startDirect。

**Linux 服务模式连接失败 → 刷新 ACL**：

包预装后首次连接，socket ACL 可能不含当前 uid。在 `_connectWithRetry` 全部失败后、`startDirect` 前，对 Linux 补一次 ACL 刷新：

```dart
  Future<bool> _connectWithRetry({...}) async {
    ...
    // Linux 服务模式：连接失败时补一次 ACL 刷新（幂等 install）
    if (!connected && Constants.isDesktop && Platform.isLinux) {
      final sm = _serviceManager;
      if (sm is UnixServiceManager && await sm.refreshCallerUid()) {
        // 刷新后 systemctl restart 使新 unit env 生效
        await sm.start();
        // 重试连接
        for (int i = 0; i < 5; i++) {
          try {
            await _ipcWorker!.connect();
            return true;
          } catch (_) {
            await Future.delayed(const Duration(milliseconds: 200));
          }
        }
      }
    }
    return false;
  }
```

> 这会弹一次 pkexec（仅限包预装后每个 GUI 用户首次）。之后 ACL 含其 uid，再连不再弹。

- [ ] **Step 2: 调整 _connectWithRetry / 探测逻辑**

在 `init()` 中，Linux 桌面端连接时若系统 socket 连不上，应回退尝试用户目录 socket（兼容旧直跑进程）。在 `_attemptReconnect` 和 `init` 中确保 ipcPath 一致使用 `_serviceManager!.ipcPath`。

由于 `ipcPath` getter 在 Linux 已固定为系统路径，直跑降级场景（`startDirect`）的 socket 仍在用户目录。需要让降级时也能连上：

在 `startDirect()` 后，临时切到用户目录 socket 重连。检查 `_startAndConnectWithFallback` 是否需要传不同 path。

实际改动：`UnixServiceManager` 新增 `directIpcPath` getter：

```dart
  /// 降级直跑模式用的用户目录 socket（startDirect 后）。
  String get directIpcPath => ServiceManager.defaultIpcPath(homeDir);
```

在 `lib_core.dart` 的 `_startAndConnectWithFallback` 中，startDirect 成功后用 `directIpcPath` 重建 IpcWorker：

```dart
  Future<bool> _startAndConnectWithFallback() async {
    if (await _startAndConnect()) return true;
    await _serviceManager!.stop();
    if (!await _serviceManager!.startDirect()) return false;
    // 降级：切换到用户目录 socket
    final sm = _serviceManager!;
    if (sm is UnixServiceManager && Platform.isLinux) {
      _ipcWorker = IpcWorker(ipcPath: sm.directIpcPath);
      _ipcWorker!.onCallback = _handleWorkerCallback;
      _ipcWorker!.onDisconnect = _onIpcDisconnected;
    }
    if (!await _connectWithRetry(attempts: 10)) return false;
    ...
  }
```

- [ ] **Step 3: 编译验证**

Run: `cd /home/mapleafgo/Projects/OpenProject/singcast && flutter analyze lib/core/`
Expected: 无错误

- [ ] **Step 4: 运行全部测试**

Run: `flutter test`
Expected: 全部 PASS

- [ ] **Step 5: commit**

```bash
cd /home/mapleafgo/Projects/OpenProject/singcast
git add lib/core/service_manager.dart lib/core/lib_core.dart
git commit -m "feat(lib_core): 服务模式与降级模式 ipcPath 分流"
```

---

### Task 6: AUR 打包（install 钩子 + 软链修复）

**Files:**
- Modify: `aurpkg/singcast/PKGBUILD`
- Create: `aurpkg/singcast/singcast.install`

- [ ] **Step 1: 创建 singcast.install 钩子**

创建 `aurpkg/singcast/singcast.install`：

```sh
post_install() {
    # 包安装时以 root 身份预装 systemd unit + polkit rules，
    # 使首次开 TUN 即零密码（不走 pkexec）。
    /opt/Singcast/singcast-core service install --home /var/lib/singcast 2>/dev/null || true
    systemctl daemon-reload
    echo "==> singcast: TUN 模式已免密就绪。"
}

post_upgrade() {
    post_install
}

pre_remove() {
    /opt/Singcast/singcast-core service uninstall 2>/dev/null || true
    systemctl stop singcast-core.service 2>/dev/null || true
    systemctl disable singcast-core.service 2>/dev/null || true
}
```

- [ ] **Step 2: 修改 PKGBUILD**

在 `source_x86_64` 中添加 `singcast.install`，添加 `install=singcast.install`，修复软链 bug：

> 软链 bug 背景：原 `ln -snf "${pkgdir}/${_install_path}/singcast"` 把 `${pkgdir}`（打包缓存绝对路径 `/home/.../.cache/yay/.../pkg/singcast/...`）写进了符号链接，装到别的机器上链接失效、`command -v singcast` 报错。改为链到 `/opt/Singcast/singcast`。

```sh
install=singcast.install
_install_path="/opt/Singcast"

package() {
  install -dm755 "${pkgdir}${_install_path}"

  cp -a "${srcdir}/lib" "${pkgdir}${_install_path}/lib"
  cp -a "${srcdir}/data" "${pkgdir}${_install_path}/data"
  install -Dm755 "${srcdir}/singcast" "${pkgdir}${_install_path}/singcast"
  install -Dm755 "${srcdir}/singcast-core" "${pkgdir}${_install_path}/singcast-core"

  install -dm755 "${pkgdir}/usr/bin"
  # 修复：用绝对路径而非 pkgdir 绝对路径
  ln -snf "${_install_path}/singcast" "${pkgdir}/usr/bin/${pkgname}"

  install -Dm644 "singcast.svg" "${pkgdir}/usr/share/icons/hicolor/scalable/apps/singcast.svg"
  install -Dm644 "singcast.desktop" "${pkgdir}/usr/share/applications/singcast.desktop"
}
```

> 注：unit/rules 由 `post_install` 调 `service install` 以 root 身份写入（而非 package() 静态文件），保证 ExecStart 路径与实际二进制位置一致。sysusers 创建由 `service install` 内部 `ensureServiceUser` 完成。
>
> **ACL 与多用户**：`post_install` 跑在 root，`effectiveCallerUID()` 此时拿不到 GUI 用户 uid（SUDO_USER 无值），fallback 到 root(euid=0)。首个 GUI 用户首次开 TUN 时，若 `isReady()==true` 直接 start，但 socket ACL 未含其 uid 会连接被拒。此时 GUI 应补一次 `pkexec singcast-core service install`（install 幂等：更新 unit 中 SINGCAST_GUI_UID 为当前 uid 并 daemon-reload）。这保证每用户首开各一次 pkexec，之后零密码。Task 4 的 setup 需在 isReady 仍走一次 install 以刷新 uid。

- [ ] **Step 3: 验证 PKGBUILD 语法**

Run: `cd /home/mapleafgo/Projects/OpenProject/aurpkg/singcast && bash -n PKGBUILD && echo OK`
Expected: OK

- [ ] **Step 4: 本地构建测试（可选，需完整环境）**

Run: `cd /home/mapleafgo/Projects/OpenProject/aurpkg/singcast && makepkg -f`
Expected: 生成 .pkg.tar.zst，`/usr/bin/singcast` 软链正确指向 `/opt/Singcast/singcast`

- [ ] **Step 5: commit**

```bash
cd /home/mapleafgo/Projects/OpenProject/aurpkg/singcast
git add PKGBUILD singcast.install
git commit -m "feat(packaging): 添加 install 钩子 + 修复软链路径"
```

---

### Task 7: 全量编译 + lint 验证

**Files:** 无新增

- [ ] **Step 1: singcast-cli 编译 + 测试**

Run:
```bash
cd /home/mapleafgo/Projects/OpenProject/singcast-cli
go build -tags 'with_clash_api,with_utls,with_quic,with_gvisor' ./...
go test -tags 'with_clash_api,with_utls,with_quic,with_gvisor' ./ipc/... ./core/...
gofmt -w ipc/ cmd/
golangci-lint run ./ipc/... ./cmd/...
```
Expected: 编译成功，测试全绿，lint 无新增告警

- [ ] **Step 2: singcast GUI 分析**

Run:
```bash
cd /home/mapleafgo/Projects/OpenProject/singcast
flutter analyze lib/core/ test/services/
flutter test
```
Expected: 无错误，测试全绿

- [ ] **Step 3: 修复 lint 问题（如有）**

根据 Step 1-2 输出修复格式、未用 import、类型问题。

- [ ] **Step 4: 最终 commit**

```bash
# 如有 lint 修复
cd /home/mapleafgo/Projects/OpenProject/singcast-cli
git add -A && git commit -m "chore: lint 修复"
```

---

### Task 8: 手工验收清单（文档化）

**Files:**
- Create: `singcast/docs/superpowers/specs/2026-07-25-linux-tun-acceptance.md`

- [ ] **Step 1: 写验收清单**

记录以下手工验证步骤，供发布前执行：

1. `yay -S singcast` 后打开 TUN → 0 次密码
2. 无 unit 时开 TUN → 1 次 pkexec → 之后 0 次
3. 关开 TUN / 热重载 → 无 resolved 三连弹
4. 关于页"移除提权" → 降级内置 core
5. `systemctl status singcast-core` 正常 running
6. `getcap` 不再是主判定依据

- [ ] **Step 2: commit**

```bash
cd /home/mapleafgo/Projects/OpenProject/singcast
git add docs/superpowers/specs/2026-07-25-linux-tun-acceptance.md
git commit -m "docs: 添加 Linux TUN 提权手工验收清单"
```
