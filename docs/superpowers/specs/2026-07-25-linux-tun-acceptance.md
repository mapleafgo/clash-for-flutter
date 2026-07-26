# Linux TUN 提权手工验收清单

> 日期：2026-07-25

## 前置

- 部署最新 GUI + core（v1.1.18+）
- `systemctl cat singcast-core.service` 可查看 unit（安装/首次 setup 后）
- `/usr/share/polkit-1/rules.d/singcast.rules` 存在
- 系统用户 `singcast` 存在（`id singcast`）
- 设置页 TUN 协议栈默认 gvisor

## 验收项

1. **AUR/本地 unit 安装后开 TUN**
   - `systemctl cat singcast-core.service` 成功
   - 开 TUN：0 次密码
   - DNS/路由正常，浏览器可上网

2. **无 unit 时开 TUN（便携/AppImage）**
   - 首次：1 次 pkexec（service install）
   - 之后：0 次

3. **关开 TUN / 热重载**
   - 无 resolved 弹窗（set-domains / set-default-route / set-dns-servers / revert）
   - 关闭时无 revert 弹窗

4. **关于页「移除提权」**
   - 降级到内置 core
   - `systemctl cat singcast-core.service` 失败

5. **服务状态**
   - `systemctl status singcast-core` 在 TUN 开时 running
   - socket `/run/singcast/command.sock` 存在
   - 便携/AppImage 首次 install 后 ExecStart 指向 `/var/lib/singcast/singcast-core`（非 `/tmp/.mount_*`）

6. **软链**
   - `readlink /usr/bin/singcast` 指向 `/opt/Singcast/singcast`
