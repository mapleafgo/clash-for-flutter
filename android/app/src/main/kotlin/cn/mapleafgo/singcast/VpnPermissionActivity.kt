package cn.mapleafgo.singcast

import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts

/// 磁贴首次建连时的 VPN 授权中转：透明、授权成功后建连并自动 finish，
/// 不展示 App 界面。
class VpnPermissionActivity : ComponentActivity() {
    companion object {
        private const val TAG = "VpnPermission"
    }

    /// 与 MainActivity 一致，走 Activity Result API。
    private val vpnPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        AppLog.i(TAG, "permission result=${result.resultCode}")
        if (result.resultCode == RESULT_OK) {
            TileVpnConnector.startVpn(this)
        }
        finish()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val prepare = VpnService.prepare(this)
        if (prepare != null) {
            AppLog.i(TAG, "requesting vpn permission")
            vpnPermissionLauncher.launch(prepare)
        } else {
            AppLog.i(TAG, "vpn permission already granted, connecting")
            TileVpnConnector.startVpn(this)
            finish()
        }
    }
}
