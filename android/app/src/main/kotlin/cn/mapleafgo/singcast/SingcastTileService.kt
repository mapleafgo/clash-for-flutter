package cn.mapleafgo.singcast

import android.Manifest
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.widget.Toast

class SingcastTileService : TileService() {
    companion object {
        private const val TAG = "SingcastTile"
    }

    override fun onCreate() {
        super.onCreate()
        // 磁贴本身也可能冷启动进程（进程新建），先做原生初始化，
        // 保证权限判定与建连日志写入 AppLog、provider 已注册。
        Mobile.ensureNativeReady(this)
    }

    override fun onStartListening() {
        super.onStartListening()
        refreshTile()
    }

    override fun onTileAdded() {
        super.onTileAdded()
        refreshTile()
    }

    override fun onClick() {
        super.onClick()
        AppLog.i(TAG, "onClick: running=${SingcastVpnService.isServiceRunning}")
        if (SingcastVpnService.isServiceRunning) {
            setTileState(false)
            toggleOff()
        } else {
            // 点击先给切换反馈，真实状态由 requestTileUpdate/onStartListening 后置刷新；
            // 授权被拒或启动失败时，下次刷新会回落为真实状态。
            if (toggleOn()) setTileState(true)
        }
    }

    /// 仅图标着色：STATE_ACTIVE(已连接) / STATE_INACTIVE(未连接)。
    private fun setTileState(active: Boolean) {
        val tile = qsTile ?: return
        tile.state = if (active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.updateTile()
    }

    /// 同步真实状态（由 requestListeningState 触发的 onStartListening 调用）。
    private fun refreshTile() {
        setTileState(SingcastVpnService.isServiceRunning)
    }

    private fun toggleOn(): Boolean {
        val cfg = TileConfigReader.read(this)
        if (!TileConfigReader.canConnectVpn(cfg)) {
            AppLog.w(TAG, "toggleOn: no tun config, prompting only")
            Toast.makeText(this, getString(R.string.tile_no_config), Toast.LENGTH_LONG).show()
            return false
        }
        val prepare = VpnService.prepare(this)
        // 通知权限缺失时前台通知不显示，用户将无法从通知栏
        // 查看状态/断开 VPN，与 App 路径保持一致：一并走授权中转请求。
        val needNotification = checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        if (prepare != null || needNotification) {
            AppLog.i(
                TAG,
                "toggleOn: opening permission activity (vpn=${prepare != null}, notification=$needNotification)",
            )
            startPermissionActivity()
        } else {
            AppLog.i(TAG, "toggleOn: authorized, connecting")
            TileVpnConnector.startVpn(this)
        }
        return true
    }

    private fun toggleOff() {
        AppLog.i(TAG, "toggleOff: disconnecting to direct")
        // 完全直连：走服务自身 disconnect（内部 stopCore + stopForeground）。
        val intent = Intent(this, SingcastVpnService::class.java).apply {
            action = SingcastVpnService.ACTION_DISCONNECT_TILE
        }
        // 与 toggleOn 同理：后台 startService 会被系统拦截。
        startForegroundService(intent)
    }

    private fun startPermissionActivity() {
        val intent = Intent(this, VpnPermissionActivity::class.java)
        val pi = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        startActivityAndCollapse(pi)
    }
}
