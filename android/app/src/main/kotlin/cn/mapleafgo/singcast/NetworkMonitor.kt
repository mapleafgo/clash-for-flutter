package cn.mapleafgo.singcast

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import android.system.Os

object NetworkMonitor {
    private const val TAG = "SingcastVpn"

    private val defaultNetworkRequest = NetworkRequest.Builder()
        .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
        .build()

    @Volatile private var defaultNetworkCallback: ConnectivityManager.NetworkCallback? = null
    @Volatile private var defaultNetwork: android.net.Network? = null

    fun detectAndReportInterfaces(context: Context) {
        try {
            val interfaces = java.net.NetworkInterface.getNetworkInterfaces() ?: return
            val arr = org.json.JSONArray()
            while (interfaces.hasMoreElements()) {
                val intf = interfaces.nextElement()
                val addrs = org.json.JSONArray()
                for (ia in intf.interfaceAddresses) {
                    val host = ia.address.hostAddress?.substringBefore('%') ?: continue
                    addrs.put("$host/${ia.networkPrefixLength}")
                }
                val index = try { Os.if_nametoindex(intf.name) } catch (_: Exception) { 0 }
                var flags = 0
                if (intf.isUp) flags = flags or 0x1
                if (intf.isLoopback) flags = flags or 0x8
                if (intf.supportsMulticast()) flags = flags or 0x1000
                val type = when {
                    intf.isLoopback -> 0
                    intf.name.startsWith("wlan") || intf.name.startsWith("wifi") -> 2
                    intf.name.startsWith("rmnet") || intf.name.startsWith("ccmni") -> 3
                    else -> 1
                }
                arr.put(org.json.JSONObject().apply {
                    put("name", intf.name)
                    put("index", index)
                    put("mtu", intf.mtu)
                    put("addresses", addrs)
                    put("flags", flags)
                    put("type", type)
                })
            }
            Mobile.native.setInterfacesJSON(arr.toString())
        } catch (e: Exception) {
            AppLog.e(TAG, "detectAndReportInterfaces: failed", e)
        }
    }

    fun detectAndReportDefaultInterface(context: Context) {
        try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

            if (defaultNetworkCallback == null) {
                reportPhysicalDefaultInterface(context, cm.activeNetwork)

                val callback = object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: android.net.Network) {
                        reportPhysicalDefaultInterface(context, network)
                    }
                    override fun onLost(network: android.net.Network) {
                        if (defaultNetwork == network) {
                            defaultNetwork = null
                        }
                    }
                }
                // registerNetworkCallback 对所有匹配网络触发回调，包括 WiFi 连上时。
                // 不用 registerBestMatchingNetworkCallback，它追踪 VPN 网络本身。
                cm.registerNetworkCallback(defaultNetworkRequest, callback, Handler(Looper.getMainLooper()))
                defaultNetworkCallback = callback
            }

            defaultNetwork?.let { reportDefaultInterface(context, it) }
        } catch (e: Exception) {
            AppLog.e(TAG, "detectAndReportDefaultInterface: failed", e)
        }
    }

    fun unregisterDefaultNetworkCallback(context: Context) {
        val callback = defaultNetworkCallback ?: return
        defaultNetworkCallback = null
        defaultNetwork = null
        try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            cm.unregisterNetworkCallback(callback)
        } catch (e: Exception) {
            AppLog.w(TAG, "unregisterDefaultNetworkCallback: ${e.message}")
        }
    }

    /** 过滤 VPN/TUN 网络后上报物理默认接口 */
    private fun reportPhysicalDefaultInterface(context: Context, network: android.net.Network?) {
        if (network == null) return
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val lp = cm.getLinkProperties(network) ?: return
        val ifaceName = lp.interfaceName ?: return
        if (ifaceName.isEmpty() || ifaceName.startsWith("tun") || ifaceName.startsWith("ppp") || ifaceName.startsWith("tap")) return
        defaultNetwork = network
        reportDefaultInterface(context, network)
    }

    private fun reportDefaultInterface(context: Context, network: android.net.Network) {
        try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val lp = cm.getLinkProperties(network) ?: return
            val ifaceName = lp.interfaceName ?: return
            if (ifaceName.isEmpty()) return
            val caps = cm.getNetworkCapabilities(network)
            val metered = caps != null && !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
            val index = try { Os.if_nametoindex(ifaceName).toLong() } catch (_: Exception) { 0L }
            Mobile.native.updateDefaultInterface(ifaceName, index, metered)
        } catch (e: Exception) {
            AppLog.e(TAG, "reportDefaultInterface: failed", e)
        }
    }
}
