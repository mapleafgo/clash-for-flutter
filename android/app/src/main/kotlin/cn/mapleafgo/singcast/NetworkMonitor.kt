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

    // VPN 激活后 activeNetwork 返回 VPN 接口，需要单独跟踪物理默认接口
    fun startMonitoring(context: Context) {
        try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

            // Report current default immediately
            reportPhysicalDefaultInterface(context, cm.activeNetwork)

            val callback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: android.net.Network) {
                    reportPhysicalDefaultInterface(context, network)
                }
                override fun onLost(network: android.net.Network) {
                    if (defaultNetwork == network) {
                        defaultNetwork = null
                        Mobile.native.updateDefaultInterface("", -1, false)
                    }
                }
            }
            cm.registerBestMatchingNetworkCallback(defaultNetworkRequest, callback, Handler(Looper.getMainLooper()))
            defaultNetworkCallback = callback
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

    private fun reportPhysicalDefaultInterface(context: Context, network: android.net.Network?) {
        if (network == null) return
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val lp = cm.getLinkProperties(network) ?: return
        val ifaceName = lp.interfaceName ?: return
        if (ifaceName.isEmpty()) return
        defaultNetwork = network
        try {
            val caps = cm.getNetworkCapabilities(network)
            val metered = caps != null && !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
            val index = try { Os.if_nametoindex(ifaceName).toLong() } catch (_: Exception) { 0L }
            Mobile.native.updateDefaultInterface(ifaceName, index, metered)
        } catch (e: Exception) {
            AppLog.e(TAG, "reportPhysicalDefaultInterface: failed", e)
        }
    }
}
