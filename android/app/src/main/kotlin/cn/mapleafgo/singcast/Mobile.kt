package cn.mapleafgo.singcast

import android.os.ParcelFileDescriptor
import cn.mapleafgo.mobile.EventListener
import cn.mapleafgo.mobile.InterfaceProvider
import cn.mapleafgo.mobile.Mobile as NativeMobile
import cn.mapleafgo.mobile.Singcast
import cn.mapleafgo.mobile.SocketProtector
import cn.mapleafgo.mobile.WiFiStateProvider

object Mobile {
    private const val TAG = "SingcastVpn"
    const val EVT_STATS = 5
    private val coreLock = Any()
    private val singcast = NativeMobile.create()
    @Volatile private var vpnService: SingcastVpnService? = null

    private val socketProtector = SocketProtector { fd ->
        val svc = vpnService ?: return@SocketProtector false
        svc.protectSocket(fd)
    }

    private val interfaceProvider = InterfaceProvider { NetworkMonitor.getInterfacesJSON() }

    private val wifiStateProvider = WiFiStateProvider { NetworkMonitor.getWiFiStateJSON() }

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

    /// 注册按需回调 provider（内核启动时通过回调获取网络接口和 WiFi 状态）。
    fun registerProviders() {
        singcast.setInterfaceProvider(interfaceProvider)
        singcast.setWiFiStateProvider(wifiStateProvider)
        AppLog.i(TAG, "registerProviders: interface + WiFi state providers registered")
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
            val tunFd = onPrepare?.invoke() ?: -1
            AppLog.i(TAG, "startWithContent: content=${content.length} chars, tunFd=$tunFd")
            if (tunFd >= 0) {
                singcast.setTunFd(tunFd)
            }
            try {
                singcast.startWithContent(content, ruleSetProxy)
            } catch (e: Throwable) {
                // establish() 后 detachFd() 已交出所有权，内核启动失败时没人关它：
                // fd 泄漏且 Android VPN 路由残留（图标常亮 + 流量黑洞）。
                if (tunFd >= 0) {
                    try {
                        ParcelFileDescriptor.adoptFd(tunFd).close()
                        AppLog.i(TAG, "startWithContent: closed orphan tunFd=$tunFd")
                    } catch (ce: Throwable) {
                        AppLog.e(TAG, "startWithContent: close orphan tunFd failed", ce)
                    }
                }
                throw e
            }
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

    fun updateDefaultInterface(name: String, index: Long, metered: Boolean) {
        singcast.updateDefaultInterface(name, index, metered)
    }

    // --- Callbacks ---

    fun registerCallbacks(onEvent: (Int, String) -> Unit) {
        singcast.setOnEvent(EventListener { eventType, json -> onEvent(eventType, json) })
        AppLog.i(TAG, "registerCallbacks: registered unified event listener")
    }

}
