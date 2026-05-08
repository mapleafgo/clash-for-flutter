package cn.mapleafgo.singcast

import android.os.Handler
import android.os.Looper
import android.system.Os
import cn.mapleafgo.ffi.EventHandler
import cn.mapleafgo.ffi.Ffi
import cn.mapleafgo.ffi.Singcast
import cn.mapleafgo.ffi.SocketProtector
import io.flutter.plugin.common.EventChannel

object Mobile {
    private const val TAG = "SingcastVpn"
    private val mainHandler = Handler(Looper.getMainLooper())
    private val coreLock = Any()
    private val singcast = Ffi.create()
    @Volatile private var eventSink: EventChannel.EventSink? = null
    @Volatile private var vpnService: SingcastVpnService? = null

    private val socketProtector = object : SocketProtector {
        override fun protect(fd: Int): Boolean {
            val svc = vpnService
            if (svc == null) {
                AppLog.w(TAG, "socketProtector: vpnService is null, cannot protect fd=$fd")
                return false
            }
            val ok = svc.protectSocket(fd)
            if (!ok) {
                AppLog.w(TAG, "socketProtector: protect($fd) failed via VpnService")
            }
            return ok
        }
    }

    fun setVpnService(svc: SingcastVpnService?) {
        vpnService = svc
        if (svc != null) {
            AppLog.d(TAG, "setVpnService: registered socket protector")
            singcast.setSocketProtector(socketProtector)
        } else {
            AppLog.d(TAG, "setVpnService: cleared (svc=null)")
        }
    }

    private val eventHandler = object : EventHandler {
        override fun onEvent(eventType: Int, jsonPayload: String) {
            val sink = eventSink
            if (sink == null) {
                AppLog.w(TAG, "onEvent: eventSink is null, dropping eventType=$eventType payload=${jsonPayload.take(200)}")
                return
            }
            val data = mapOf("type" to eventType.toInt(), "data" to jsonPayload)
            mainHandler.post { sink.success(data) }
        }
    }

    @Volatile private var coreInitialized = false

    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    fun setupEventHandler() {
        if (coreInitialized) {
            singcast.setOnEvent(eventHandler)
        }
    }

    // --- Lifecycle ---

    fun initCore(optionsJSON: String) {
        synchronized(coreLock) {
            if (coreInitialized) {
                AppLog.i(TAG, "initCore: already initialized, re-registering event handler")
                singcast.setOnEvent(eventHandler)
                return
            }
            AppLog.i(TAG, "initCore: optionsJSON=$optionsJSON")
            singcast.init(optionsJSON)
            singcast.setOnEvent(eventHandler)
            coreInitialized = true
            AppLog.i(TAG, "initCore: done")
        }
    }

    fun startWithContent(content: String, ruleSetProxy: String) {
        synchronized(coreLock) {
            AppLog.i(TAG, "startWithContent: content=${content.length} chars, proxy='$ruleSetProxy', thread=${Thread.currentThread().name}")
            singcast.startWithContent(content, ruleSetProxy)
            AppLog.i(TAG, "startWithContent: completed successfully")
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

    fun pause() {
        AppLog.i(TAG, "pause")
        singcast.pause()
    }

    fun wake() {
        AppLog.i(TAG, "wake")
        singcast.wake()
    }

    fun resetNetwork() {
        AppLog.i(TAG, "resetNetwork")
        singcast.resetNetwork()
    }

    // --- Config ---

    fun reloadTUN() {
        AppLog.i(TAG, "reloadTUN")
        singcast.reloadTUN()
    }

    fun setOverridePackages(overrideJSON: String) {
        AppLog.i(TAG, "setOverridePackages: $overrideJSON")
        singcast.setOverridePackages(overrideJSON)
    }

    fun queryTunOptions(): String = singcast.queryTunOptions()

    // --- Queries ---

    fun setTunFd(fd: Int) {
        AppLog.i(TAG, "setTunFd: fd=$fd")
        singcast.setTunFd(fd)
    }

    fun queryProxies(): String = singcast.queryProxies()

    fun queryTraffic(): String = singcast.queryTraffic()

    fun queryLogs(clear: Boolean): String = singcast.queryLogs(clear)

    fun queryConnections(): String = singcast.queryConnections()

    // --- Proxy Control ---

    fun selectProxy(group: String, tag: String) {
        singcast.selectProxy(group, tag)
    }

    fun testDelay(name: String) {
        singcast.testDelay(name)
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

    fun setMemoryLimit(bytes: Long): String {
        return try {
            singcast.setMemoryLimit(bytes)
            ""
        } catch (e: Exception) {
            AppLog.e(TAG, "setMemoryLimit: ${e.message}")
            e.message ?: "error"
        }
    }

    fun queryMemoryStats(): String = singcast.queryMemoryStats()

    fun flushSystemDNS() {
        singcast.flushSystemDNS()
    }

    // --- Platform ---

    fun needWIFIState(): Boolean = singcast.needWIFIState()

    fun needFindProcess(): Boolean = singcast.needFindProcess()

    fun updateWIFIState() {
        singcast.updateWIFIState()
    }

    fun setIncludeAllNetworks(v: Boolean) {
        singcast.setIncludeAllNetworks(v)
    }

    fun setWIFIState(ssid: String, bssid: String) {
        singcast.setWIFIState(ssid, bssid)
    }

    fun writeMessage(level: Int, message: String) {
        singcast.writeMessage(level, message)
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

    fun setLocale(localeID: String) {
        // Locale setting not supported by current kernel
        AppLog.d(TAG, "setLocale: $localeID (no-op)")
    }

    // --- VPN Notification ---

    fun detectAndReportInterfaces(context: android.content.Context) {
        try {
            val interfaces = java.net.NetworkInterface.getNetworkInterfaces()
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

    @android.annotation.TargetApi(31)
    fun detectAndReportDefaultInterface(context: android.content.Context) {
        try {
            val cm = context.getSystemService(android.content.Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager

            if (defaultNetworkCallback == null) {
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
            val caps = cm.getNetworkCapabilities(network)
            val metered = if (caps != null) !caps.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_NOT_METERED) else false
            val index = try { Os.if_nametoindex(ifaceName).toLong() } catch (_: Exception) { 0L }
            singcast.updateDefaultInterface(ifaceName, index, metered)
            AppLog.d(TAG, "detectAndReportDefaultInterface: $ifaceName index=$index metered=$metered")
        } catch (e: Exception) {
            AppLog.e(TAG, "_reportDefaultInterface: failed", e)
        }
    }

    fun notifyVpnStateChanged(connected: Boolean) {
        AppLog.i(TAG, "notifyVpnStateChanged: connected=$connected")
        val sink = eventSink ?: return
        val data = mapOf("type" to 5, "data" to """{"connected":$connected}""")
        mainHandler.post { sink.success(data) }
    }

}
