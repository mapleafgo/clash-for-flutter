package cn.mapleafgo.singcast

import android.os.Looper
import android.system.Os
import cn.mapleafgo.mobile.EventListener
import cn.mapleafgo.mobile.Mobile as NativeMobile
import cn.mapleafgo.mobile.Singcast
import cn.mapleafgo.mobile.SocketProtector

object Mobile {
    private const val TAG = "SingcastVpn"
    private val coreLock = Any()
    private val singcast = NativeMobile.create()
    @Volatile private var vpnService: SingcastVpnService? = null

    @Volatile private var protectCallCount = 0

    private val socketProtector = object : SocketProtector {
        override fun protect(fd: Int): Boolean {
            val svc = vpnService
            if (svc == null) {
                AppLog.w(TAG, "socketProtector: vpnService is null, cannot protect fd=$fd")
                return false
            }
            val ok = svc.protectSocket(fd)
            protectCallCount++
            if (!ok) {
                AppLog.w(TAG, "socketProtector: protect($fd) FAILED via VpnService")
            } else if (protectCallCount <= 5 || protectCallCount % 100 == 0) {
                AppLog.i(TAG, "socketProtector: protect($fd) OK (count=$protectCallCount)")
            }
            return ok
        }
    }

    fun setVpnService(svc: SingcastVpnService?) {
        vpnService = svc
        if (svc != null) {
            AppLog.i(TAG, "setVpnService: registering socket protector (thread=${Thread.currentThread().name})")
            singcast.setSocketProtector(socketProtector)
            AppLog.i(TAG, "setVpnService: socket protector registered successfully")
        } else {
            singcast.setSocketProtector(null)
            AppLog.w(TAG, "setVpnService: cleared (svc=null), socket protector removed")
        }
    }

    @Volatile private var coreInitialized = false

    // --- Lifecycle ---

    fun initCore(optionsJSON: String) {
        synchronized(coreLock) {
            if (coreInitialized) {
                AppLog.i(TAG, "initCore: already initialized")
                return
            }
            AppLog.i(TAG, "initCore: optionsJSON=$optionsJSON")
            singcast.init(optionsJSON)
            coreInitialized = true
            AppLog.i(TAG, "initCore: done")
        }
    }

    fun startWithContent(content: String, ruleSetProxy: String) {
        synchronized(coreLock) {
            val hasTun = content.contains("tun:") && content.contains("enable: true")
            protectCallCount = 0
            AppLog.i(TAG, "startWithContent: content=${content.length} chars, hasTun=$hasTun, vpnServiceSet=${vpnService != null}, thread=${Thread.currentThread().name}")
            singcast.startWithContent(content, ruleSetProxy)
            AppLog.i(TAG, "startWithContent: completed successfully, protectCallCount=$protectCallCount")
        }
    }

    fun stopCore() {
        synchronized(coreLock) {
            AppLog.i(TAG, "stopCore: stopping core")
            singcast.stop()
            AppLog.i(TAG, "stopCore: done")
        }
    }

    fun destroyCore() {
        synchronized(coreLock) {
            AppLog.i(TAG, "destroyCore: destroying core")
            singcast.destroy()
            coreInitialized = false
            AppLog.i(TAG, "destroyCore: done")
        }
    }

    fun resetNetwork() {
        AppLog.i(TAG, "resetNetwork")
        singcast.resetNetwork()
    }

    // --- Queries ---

    fun setTunFd(fd: Int) {
        AppLog.i(TAG, "setTunFd: fd=$fd")
        singcast.setTunFd(fd)
    }

    fun queryProxies(): String = singcast.queryProxies()

    fun queryStats(): String = singcast.queryStats()

    fun queryConnections(): String = singcast.queryConnections()

    fun queryMode(): String = singcast.queryMode()

    fun queryState(): Int = singcast.state()

    // --- Proxy Control ---

    fun selectProxy(group: String, tag: String) {
        singcast.selectProxy(group, tag)
    }

    fun testDelay(name: String, timeoutMs: Int): Int {
        return singcast.testDelay(name, timeoutMs)
    }

    fun testGroupDelay(group: String, timeoutMs: Int): String {
        return singcast.testGroupDelay(group, timeoutMs)
    }

    fun setMode(mode: String) {
        singcast.setMode(mode)
    }

    fun setGroupExpand(group: String, expand: Boolean) {
        singcast.setGroupExpand(group, expand)
    }

    // --- Connection Management ---

    fun closeConnection(id: String) {
        singcast.closeConnection(id)
    }

    fun closeAllConnections() {
        singcast.closeAllConnections()
    }

    // --- Logging / Memory ---

    fun setLogLevel(level: Int) {
        singcast.setLogLevel(level)
    }

    fun setMemoryLimit(bytes: Long) {
        singcast.setMemoryLimit(bytes)
    }

    fun queryRules(): String = singcast.queryRules()

    fun flushSystemDNS() {
        singcast.flushSystemDNS()
    }

    fun flushFakeIP() {
        singcast.flushFakeIP()
    }

    fun flushDNSCache() {
        singcast.flushDNSCache()
    }

    fun triggerGC() {
        singcast.triggerGC()
    }

    // --- Platform ---

    fun setIncludeAllNetworks(v: Boolean) {
        singcast.setIncludeAllNetworks(v)
    }

    fun setWIFIState(ssid: String, bssid: String) {
        singcast.setWIFIState(ssid, bssid)
    }

    // --- Utilities ---

    fun checkConfig(content: String): String {
        return try {
            singcast.checkConfig(content)
            ""
        } catch (e: Exception) {
            AppLog.e(TAG, "checkConfig: ${e.message}")
            e.message ?: "error"
        }
    }

    fun getVersion(): String = singcast.version()

    // --- VPN Notification ---

    fun detectAndReportInterfaces(context: android.content.Context) {
        try {
            val interfaces = java.net.NetworkInterface.getNetworkInterfaces() ?: return
            val arr = org.json.JSONArray()
            while (interfaces.hasMoreElements()) {
                val intf = interfaces.nextElement()
                val addrs = org.json.JSONArray()
                for (ia in intf.interfaceAddresses) {
                    val host = ia.address.hostAddress?.substringBefore('%') ?: continue
                    addrs.put("${host}/${ia.networkPrefixLength}")
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
            singcast.setInterfacesJSON(arr.toString())
            AppLog.d(TAG, "detectAndReportInterfaces: reported ${arr.length()} interfaces")
        } catch (e: Exception) {
            AppLog.e(TAG, "detectAndReportInterfaces: failed", e)
        }
    }

    // sing-box approach: registerBestMatchingNetworkCallback returns the actual default
    // transport network, bypassing VPN. registerDefaultNetworkCallback returns VPN since Android P.
    private val defaultNetworkRequest = android.net.NetworkRequest.Builder()
        .addCapability(android.net.NetworkCapabilities.NET_CAPABILITY_INTERNET)
        .addCapability(android.net.NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
        .build()

    @Volatile private var defaultNetworkCallback: android.net.ConnectivityManager.NetworkCallback? = null
    @Volatile private var defaultNetwork: android.net.Network? = null

    fun detectAndReportDefaultInterface(context: android.content.Context) {
        try {
            val cm = context.getSystemService(android.content.Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager

            if (defaultNetworkCallback == null) {
                // 注册回调前同步获取当前活跃网络并立即报告
                val activeNetwork = cm.activeNetwork
                if (activeNetwork != null) {
                    defaultNetwork = activeNetwork
                    _reportDefaultInterface(context, activeNetwork)
                }

                val callback = object : android.net.ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: android.net.Network) {
                        defaultNetwork = network
                        _reportDefaultInterface(context, network)
                    }
                    override fun onLost(network: android.net.Network) {
                        if (defaultNetwork == network) {
                            defaultNetwork = null
                            AppLog.w(TAG, "detectAndReportDefaultInterface: default network lost")
                        }
                    }
                }
                cm.registerBestMatchingNetworkCallback(defaultNetworkRequest, callback, android.os.Handler(android.os.Looper.getMainLooper()))
                defaultNetworkCallback = callback
                AppLog.i(TAG, "detectAndReportDefaultInterface: registered network callback")
            }

            // Report immediately with current default if available
            val currentNetwork = defaultNetwork
            if (currentNetwork != null) {
                _reportDefaultInterface(context, currentNetwork)
            }
        } catch (e: Exception) {
            AppLog.e(TAG, "detectAndReportDefaultInterface: failed", e)
        }
    }

    fun unregisterDefaultNetworkCallback(context: android.content.Context) {
        val callback = defaultNetworkCallback ?: return
        defaultNetworkCallback = null
        defaultNetwork = null
        try {
            val cm = context.getSystemService(android.content.Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
            cm.unregisterNetworkCallback(callback)
            AppLog.i(TAG, "unregisterDefaultNetworkCallback: unregistered")
        } catch (e: Exception) {
            AppLog.w(TAG, "unregisterDefaultNetworkCallback: ${e.message}")
        }
    }

    private fun _reportDefaultInterface(context: android.content.Context, network: android.net.Network) {
        try {
            val cm = context.getSystemService(android.content.Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
            val lp = cm.getLinkProperties(network) ?: return
            val ifaceName = lp.interfaceName ?: return
            if (ifaceName.isEmpty()) return
            // Skip VPN/TUN interfaces — the default interface must be a real transport.
            if (ifaceName.startsWith("tun") || ifaceName.startsWith("ppp") || ifaceName.startsWith("tap")) {
                AppLog.d(TAG, "_reportDefaultInterface: skip VPN interface $ifaceName")
                return
            }
            val caps = cm.getNetworkCapabilities(network)
            val metered = if (caps != null) !caps.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_NOT_METERED) else false
            val index = try { Os.if_nametoindex(ifaceName).toLong() } catch (_: Exception) { 0L }
            singcast.updateDefaultInterface(ifaceName, index, metered)
            AppLog.d(TAG, "detectAndReportDefaultInterface: $ifaceName index=$index metered=$metered")
        } catch (e: Exception) {
            AppLog.e(TAG, "_reportDefaultInterface: failed", e)
        }
    }

    // --- Callbacks ---

    fun registerCallbacks(onEvent: (Int, String) -> Unit) {
        singcast.setOnEvent(EventListener { eventType, json -> onEvent(eventType, json) })
        AppLog.i(TAG, "registerCallbacks: registered unified event listener")
    }

}
