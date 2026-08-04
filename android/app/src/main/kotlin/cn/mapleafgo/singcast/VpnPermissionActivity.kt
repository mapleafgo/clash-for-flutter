package cn.mapleafgo.singcast

import android.Manifest
import android.content.pm.PackageManager
import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat

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

    /// 通知权限仅是 best-effort：拒绝后 VPN 仍可建连，只是前台通知不显示。
    private val notificationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) {
        requestVpnAndConnect()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (needNotificationPermission()) {
            AppLog.i(TAG, "requesting notification permission")
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            requestVpnAndConnect()
        }
    }

    private fun needNotificationPermission(): Boolean {
        return ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
    }

    private fun requestVpnAndConnect() {
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
