package cn.mapleafgo.singcast

import android.content.Context
import android.content.pm.ApplicationInfo
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
    @Volatile private var callbackOwner: Any? = null

    /// 绑定/解绑 VpnService。
    ///
    /// 【不要在 svc == null 时调用 singcast.setSocketProtector(null)】
    /// protector 一旦从内核摘除，内核所有出站 socket 都无法绕过 TUN：
    ///   - VPN 关闭时：内核自身连接建不起来，表现为只有本应用上不了网；
    ///   - VPN 开启时：内核连节点的包被自己刚建的 TUN 捕获，自己转发给自己，
    ///     形成路由环路，整机断网。
    /// socketProtector 内部已处理 vpnService == null（返回 false），
    /// 因此始终保持注册即可，无需摘除。
    /// 见 8e6b6f2「接入内核 SocketProtector 防止 VPN 路由环路」；
    /// 该保护曾在 6d7cfd3 的重构中被误加 else 分支撤销，导致问题复发。
    fun setVpnService(svc: SingcastVpnService?) {
        vpnService = svc
        if (svc != null) {
            singcast.setSocketProtector(socketProtector)
            AppLog.i(TAG, "setVpnService: bound, socket protector registered")
        } else {
            AppLog.i(TAG, "setVpnService: unbound (protector kept registered)")
        }
    }

    /// 注册按需回调 provider（内核启动时通过回调获取网络接口和 WiFi 状态）。
    fun registerProviders() {
        singcast.setInterfaceProvider(interfaceProvider)
        singcast.setWiFiStateProvider(wifiStateProvider)
        AppLog.i(TAG, "registerProviders: interface + WiFi state providers registered")
    }

    /// 通用原生初始化：App 与磁贴冷启动共用，幂等。
    fun ensureNativeReady(context: Context) {
        val start = System.currentTimeMillis()
        AppLog.init(context.filesDir)
        NetworkMonitor.init(context)
        registerProviders()
        AppLog.i(
            TAG,
            "ensureNativeReady: done (elapsed_ms=${System.currentTimeMillis() - start})",
        )
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

    /// VPN 服务专用初始化：磁贴路径没有 Flutter kDebugMode，
    /// 用 ApplicationInfo.FLAG_DEBUGGABLE 判断，避免 release 也进 debug 初始化。
    fun initCoreForVpnService(context: Context) {
        val debug = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        initCore("""{"home_dir":"${context.filesDir.absolutePath}","debug":$debug}""")
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

    fun convert(content: String): String {
        return singcast.convert(content)
    }

    fun getVersion(): String = singcast.version()

    fun updateDefaultInterface(name: String, index: Long, metered: Boolean) {
        singcast.updateDefaultInterface(name, index, metered)
    }

    // --- Callbacks ---

    fun registerCallbacks(owner: Any, onEvent: (Int, String) -> Unit) {
        val current = callbackOwner
        if (current != null && current !== owner) {
            AppLog.d(TAG, "registerCallbacks: skipped, already owned by $current")
            return
        }
        callbackOwner = owner
        singcast.setOnEvent(EventListener { eventType, json -> onEvent(eventType, json) })
        AppLog.i(TAG, "registerCallbacks: registered unified event listener owner=$owner")
    }

    /// 注销事件监听。
    ///
    /// 必须在 Activity 销毁时调用：注册进来的 lambda 捕获了 Activity
    /// （runOnUiThread / flutterChannel），不注销会让 native 单例长期持有
    /// 已销毁的 Activity（泄漏），且内核事件会继续投递到已 detach 的引擎。
    fun unregisterCallbacks(owner: Any) {
        val current = callbackOwner
        if (current !== owner) {
            AppLog.d(TAG, "unregisterCallbacks: skipped, owner mismatch current=$current requested=$owner")
            return
        }
        callbackOwner = null
        singcast.setOnEvent(null)
        AppLog.i(TAG, "unregisterCallbacks: cleared event listener")
    }

}
