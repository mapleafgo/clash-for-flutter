package cn.mapleafgo.singcast

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import android.system.Os
import android.system.OsConstants

object NetworkMonitor {
    private const val TAG = "SingcastVpn"

    private const val TYPE_LOOPBACK = 0
    private const val TYPE_OTHER = 1
    private const val TYPE_WIFI = 2
    private const val TYPE_CELLULAR = 3
    private const val TYPE_ETHERNET = 4

    private val defaultNetworkRequest = NetworkRequest.Builder()
        .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
        .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
        .build()

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile private var defaultNetworkCallback: ConnectivityManager.NetworkCallback? = null
    @Volatile private var defaultNetwork: android.net.Network? = null
    @Volatile private var appContext: Context? = null

    fun init(context: Context) {
        appContext = context.applicationContext
    }

    /// 按需回调：内核通过 InterfaceProvider.GetInterfaces() 调用，返回当前所有网络接口的 JSON 数组。
    fun getInterfacesJSON(): String {
        try {
            val ctx = appContext ?: return "[]"
            val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            return buildInterfacesJSON(cm)
        } catch (e: Exception) {
            AppLog.e(TAG, "getInterfacesJSON: failed", e)
            return "[]"
        }
    }

    /// 按需回调：内核通过 WiFiStateProvider.GetWiFiState() 调用，返回 WiFi 状态 JSON。
    fun getWiFiStateJSON(): String {
        // Android 端暂无 WiFi SSID/BSSID 追踪，返回空对象
        return "{}"
    }

    fun startMonitoring(context: Context) {
        try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

            reportPhysicalDefaultInterface(context, cm.activeNetwork)

            val callback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: android.net.Network) {
                    reportPhysicalDefaultInterface(context, network)
                }
                override fun onCapabilitiesChanged(network: android.net.Network, networkCapabilities: NetworkCapabilities) {
                    if (defaultNetwork == network) {
                        reportPhysicalDefaultInterface(context, network)
                    }
                }
                override fun onLost(network: android.net.Network) {
                    if (defaultNetwork == network) {
                        defaultNetwork = null
                        Mobile.updateDefaultInterface("", -1, false)
                    }
                }
            }
            defaultNetworkCallback = callback
            cm.registerBestMatchingNetworkCallback(defaultNetworkRequest, callback, mainHandler)
        } catch (e: Exception) {
            AppLog.e(TAG, "startMonitoring: failed", e)
        }
    }

    fun stopMonitoring(context: Context) {
        val callback = defaultNetworkCallback ?: return
        defaultNetworkCallback = null
        defaultNetwork = null
        try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            cm.unregisterNetworkCallback(callback)
        } catch (e: Exception) {
            AppLog.w(TAG, "stopMonitoring: ${e.message}")
        }
    }

    private fun buildInterfacesJSON(cm: ConnectivityManager): String {
        val allNetworks = cm.allNetworks
        val networkInterfaces = try {
            java.net.NetworkInterface.getNetworkInterfaces()?.toList() ?: emptyList()
        } catch (_: Exception) {
            emptyList()
        }
        val arr = org.json.JSONArray()
        for (network in allNetworks) {
            val lp = cm.getLinkProperties(network) ?: continue
            val caps = cm.getNetworkCapabilities(network) ?: continue
            // 不上报 VPN 接口，避免内核把 tun0 当作出站接口导致路由环路
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) continue
            val ifaceName = lp.interfaceName ?: continue
            val netIntf = networkInterfaces.find { it.name == ifaceName } ?: continue

            val addrs = org.json.JSONArray()
            for (ia in netIntf.interfaceAddresses) {
                val host = ia.address.hostAddress?.substringBefore('%') ?: continue
                addrs.put("$host/${ia.networkPrefixLength}")
            }
            val type = when {
                netIntf.isLoopback -> TYPE_LOOPBACK
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> TYPE_WIFI
                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> TYPE_CELLULAR
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> TYPE_ETHERNET
                else -> TYPE_OTHER
            }
            val index = try { Os.if_nametoindex(ifaceName) } catch (_: Exception) { 0 }
            var flags = 0
            if (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                flags = flags or OsConstants.IFF_UP or OsConstants.IFF_RUNNING
            }
            if (netIntf.isLoopback) flags = flags or OsConstants.IFF_LOOPBACK
            if (netIntf.isPointToPoint) flags = flags or OsConstants.IFF_POINTOPOINT
            if (netIntf.supportsMulticast()) flags = flags or OsConstants.IFF_MULTICAST
            arr.put(org.json.JSONObject().apply {
                put("name", ifaceName)
                put("index", index)
                put("mtu", netIntf.mtu)
                put("addresses", addrs)
                put("flags", flags)
                put("type", type)
            })
        }
        return arr.toString()
    }

    private fun reportPhysicalDefaultInterface(context: Context, network: android.net.Network?) {
        if (network == null) return
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val caps = cm.getNetworkCapabilities(network)
        // 跳过 VPN 网络，避免把 tun0 当默认接口导致路由环路
        if (caps?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true) return
        val lp = cm.getLinkProperties(network) ?: return
        val ifaceName = lp.interfaceName ?: return
        if (ifaceName.isEmpty()) return
        defaultNetwork = network
        try {
            val metered = caps != null && !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
            val index = try { Os.if_nametoindex(ifaceName).toLong() } catch (_: Exception) { 0L }
            Mobile.updateDefaultInterface(ifaceName, index, metered)
        } catch (e: Exception) {
            AppLog.e(TAG, "reportPhysicalDefaultInterface: failed", e)
        }
    }
}
