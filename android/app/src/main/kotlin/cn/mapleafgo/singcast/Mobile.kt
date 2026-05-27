package cn.mapleafgo.singcast

import cn.mapleafgo.mobile.EventListener
import cn.mapleafgo.mobile.Mobile as NativeMobile
import cn.mapleafgo.mobile.Singcast
import cn.mapleafgo.mobile.SocketProtector

object Mobile {
    private const val TAG = "SingcastVpn"
    private val coreLock = Any()
    private val singcast = NativeMobile.create()
    @Volatile private var vpnService: SingcastVpnService? = null

    private val socketProtector = SocketProtector { fd ->
        val svc = vpnService ?: return@SocketProtector false
        svc.protectSocket(fd)
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

    // --- Lifecycle ---

    fun initCore(optionsJSON: String) {
        synchronized(coreLock) {
            val state = singcast.state()
            if (state != "created" && state != "destroyed") {
                AppLog.i(TAG, "initCore: kernel already active (state=$state), skipping")
                return
            }
            AppLog.i(TAG, "initCore: state=$state, optionsJSON=$optionsJSON")
            singcast.init(optionsJSON)
            AppLog.i(TAG, "initCore: done")
        }
    }

    fun startWithContent(content: String, ruleSetProxy: String, onPrepare: (() -> Int)? = null) {
        synchronized(coreLock) {
            val hasTun = content.contains("tun:") && content.contains("enable: true")
            val tunFd = onPrepare?.invoke() ?: -1
            AppLog.i(TAG, "startWithContent: content=${content.length} chars, hasTun=$hasTun, tunFd=$tunFd")
            if (tunFd >= 0) {
                singcast.setTunFd(tunFd)
            }
            NetworkMonitor.reportInterfaces()
            singcast.startWithContent(content, ruleSetProxy)
            AppLog.i(TAG, "startWithContent: done")
        }
    }

    fun stopCore() {
        synchronized(coreLock) {
            AppLog.i(TAG, "stopCore: stopping core")
            singcast.stop()
            AppLog.i(TAG, "stopCore: done")
        }
    }

    // --- Queries ---

    fun queryProxies(): String = singcast.queryProxies()

    fun queryStats(): String = singcast.queryStats()

    fun queryConnections(): String = singcast.queryConnections()

    fun queryMode(): String = singcast.queryMode()

    fun queryState(): String = singcast.state()

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

    // Expose singcast instance for NetworkMonitor
    val native: Singcast get() = singcast

    // --- Network (delegated to NetworkMonitor) ---

    fun unregisterDefaultNetworkCallback(context: android.content.Context) =
        NetworkMonitor.stopMonitoring(context)

    // --- Callbacks ---

    fun registerCallbacks(onEvent: (Int, String) -> Unit) {
        singcast.setOnEvent(EventListener { eventType, json -> onEvent(eventType, json) })
        AppLog.i(TAG, "registerCallbacks: registered unified event listener")
    }

}
