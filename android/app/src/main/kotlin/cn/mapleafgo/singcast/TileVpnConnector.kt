package cn.mapleafgo.singcast

import android.content.Context
import android.content.Intent

/// 统一"读配置 → 启动 VPN 服务"；无配置时回退打开主 Activity。
object TileVpnConnector {
    fun startVpn(context: Context) {
        val cfg = TileConfigReader.read(context)
        val content = cfg.configContent
        if (content.isNullOrEmpty()) {
            val launcher = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launcher != null) {
                launcher.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(launcher)
            }
            return
        }
        val intent = Intent(context, SingcastVpnService::class.java).apply {
            action = SingcastVpnService.ACTION_CONNECT
            putExtra(SingcastVpnService.EXTRA_CONFIG, content)
            putExtra(SingcastVpnService.EXTRA_PROXY, cfg.ruleSetProxy)
            putExtra(SingcastVpnService.EXTRA_IPV6, cfg.ipv6)
        }
        context.startService(intent)
    }
}
