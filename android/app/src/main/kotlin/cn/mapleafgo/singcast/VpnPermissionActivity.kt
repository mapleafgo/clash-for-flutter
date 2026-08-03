package cn.mapleafgo.singcast

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Bundle

/// 磁贴首次建连时的 VPN 授权中转：透明、授权成功后建连并自动 finish，
/// 不展示 App 界面。
class VpnPermissionActivity : Activity() {
    companion object {
        private const val REQ_VPN = 1001
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val prepare = VpnService.prepare(this)
        if (prepare != null) {
            startActivityForResult(prepare, REQ_VPN)
        } else {
            TileVpnConnector.startVpn(this)
            finish()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_VPN && resultCode == RESULT_OK) {
            TileVpnConnector.startVpn(this)
        }
        finish()
    }
}
