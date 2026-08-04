package cn.mapleafgo.singcast

import android.content.Context

/// 统一"读配置 → 启动 VPN 服务"；缺 tun 配置时不操作 VPN。
object TileVpnConnector {
    private const val TAG = "TileVpn"

    fun startVpn(context: Context) {
        val cfg = TileConfigReader.read(context)
        val content = cfg.configContent
        if (content.isNullOrEmpty() || !TileConfigReader.hasTunInbound(content)) {
            AppLog.w(TAG, "no tun config, skipping vpn")
            return
        }
        AppLog.i(
            TAG,
            "starting vpn (config=${content.length} chars, ipv6=${cfg.ipv6}, " +
                "proxy=${cfg.ruleSetProxy.isNotEmpty()})",
        )
        val intent = SingcastVpnService.buildConnectIntent(
            context,
            content,
            cfg.ruleSetProxy,
            cfg.ipv6,
        )
        SingcastVpnService.startVpnService(context, intent)
    }
}
