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
        val merged = File(filesDir, "cache-merged.json").takeIf { it.exists() }?.readText()
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
}
