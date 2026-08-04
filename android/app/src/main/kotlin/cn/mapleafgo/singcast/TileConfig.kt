package cn.mapleafgo.singcast

import android.content.Context
import org.json.JSONObject
import java.io.File

/// 磁贴建连所需的三个要素。
data class TileVpnConfig(
    val configContent: String?,
    val ipv6: Boolean,
    val ruleSetProxy: String,
)

/// 从既有磁盘文件组装磁贴建连参数，不新增持久化字段。
object TileConfigReader {
    /// 与 Dart 侧 Defaults.ruleSetProxy 保持一致。
    private const val DEFAULT_RULE_SET_PROXY = "https://gh-proxy.org"

    fun read(context: Context): TileVpnConfig {
        val filesDir = context.filesDir
        val merged = File(filesDir, "cache-tun.json").takeIf { it.exists() }?.readText()
        val settings = File(filesDir, "settings.json").takeIf { it.exists() }?.readText()
        return parse(merged, settings)
    }

    /// 纯函数，便于 JVM 单测。
    fun parse(mergedContent: String?, settingsJson: String?): TileVpnConfig {
        val content = mergedContent?.trim()?.takeIf { it.isNotEmpty() }
        return TileVpnConfig(
            configContent = content,
            ipv6 = parseIpv6(content),
            ruleSetProxy = parseRuleSetProxy(settingsJson),
        )
    }

    private fun parseIpv6(content: String?): Boolean {
        if (content.isNullOrEmpty()) return false
        return try {
            val dns = JSONObject(content).optJSONObject("dns")
            dns?.optString("strategy") == "prefer_ipv6"
        } catch (e: Exception) {
            false
        }
    }

    private fun parseRuleSetProxy(settingsJson: String?): String {
        if (settingsJson.isNullOrEmpty()) return DEFAULT_RULE_SET_PROXY
        return try {
            JSONObject(settingsJson).optString("rule-set-proxy", DEFAULT_RULE_SET_PROXY)
        } catch (e: Exception) {
            DEFAULT_RULE_SET_PROXY
        }
    }

    /// 磁贴建连配置必须带 tun inbound，否则内核不会打开外部 TUN fd，
    /// 表现为"VPN 已开但无网络、关闭后 TUN fd 残留"。
    /// 缺文件/无 tun/解析失败都返回 false，调用方只提示、不启动 VPN。
    fun hasTunInbound(content: String?): Boolean {
        if (content.isNullOrEmpty()) return false
        return try {
            val inbounds = JSONObject(content).optJSONArray("inbounds") ?: return false
            for (i in 0 until inbounds.length()) {
                val inbound = inbounds.optJSONObject(i) ?: continue
                if (inbound.optString("type") == "tun") return true
            }
            false
        } catch (e: Exception) {
            false
        }
    }

    /// 判定缓存配置是否足够直接建连，供磁贴与系统「始终开启 VPN」启动共用。
    fun canConnectVpn(cfg: TileVpnConfig): Boolean =
        !cfg.configContent.isNullOrEmpty() && hasTunInbound(cfg.configContent)
}
