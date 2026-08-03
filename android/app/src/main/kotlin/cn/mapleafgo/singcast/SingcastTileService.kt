package cn.mapleafgo.singcast

import android.content.Intent
import android.net.VpnService
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

class SingcastTileService : TileService() {

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
        if (SingcastVpnService.isServiceRunning) {
            toggleOff()
        } else {
            toggleOn()
        }
    }

    /// 仅图标着色：STATE_ACTIVE(已连接) / STATE_INACTIVE(未连接)。
    private fun refreshTile() {
        val tile = qsTile ?: return
        val running = SingcastVpnService.isServiceRunning
        tile.state = if (running) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.updateTile()
    }

    private fun toggleOn() {
        val prepare = VpnService.prepare(this)
        if (prepare != null) {
            // 未授权：拉起透明授权 Activity，其一并在授权成功后建连并 finish。
            startActivityAndCollapse(Intent(this, VpnPermissionActivity::class.java))
        } else {
            TileVpnConnector.startVpn(this)
        }
    }

    private fun toggleOff() {
        // 完全直连：走服务自身 disconnect（内部 stopCore + stopForeground）。
        val intent = Intent(this, SingcastVpnService::class.java).apply {
            action = SingcastVpnService.ACTION_DISCONNECT_TILE
        }
        startService(intent)
    }
}
