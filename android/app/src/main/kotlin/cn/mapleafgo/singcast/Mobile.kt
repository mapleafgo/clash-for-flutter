package cn.mapleafgo.singcast

import android.os.Handler
import android.os.Looper
import cn.mapleafgo.ffi.EventHandler
import cn.mapleafgo.ffi.SocketProtector
import cn.mapleafgo.ffi.Singcast
import io.flutter.plugin.common.EventChannel

object Mobile {
    private const val TAG = "SingcastVpn"
    private val mainHandler = Handler(Looper.getMainLooper())
    private val coreLock = Any()
    private val singcast = Singcast()
    private var eventSink: EventChannel.EventSink? = null
    private var vpnService: SingcastVpnService? = null

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
            val sink = eventSink ?: return
            val data = mapOf("type" to eventType.toInt(), "data" to jsonPayload)
            mainHandler.post { sink.success(data) }
        }
    }

    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    fun setupEventHandler() {
        singcast.setOnEvent(eventHandler)
    }

    // --- Lifecycle ---

    fun initCore(optionsJSON: String) {
        AppLog.i(TAG, "initCore: optionsJSON=$optionsJSON")
        singcast.init(optionsJSON)
        AppLog.i(TAG, "initCore: done")
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
        AppLog.i(TAG, "destroyCore: destroying core")
        singcast.destroy()
        AppLog.i(TAG, "destroyCore: done")
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

    fun reloadConfig(content: String, ruleSetProxy: String) {
        synchronized(coreLock) {
            AppLog.i(TAG, "reloadConfig: content=${content.length} chars, proxy='$ruleSetProxy'")
            singcast.reloadConfig(content, ruleSetProxy)
            AppLog.i(TAG, "reloadConfig: completed successfully")
        }
    }

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
            val json = StringBuilder("[")
            var first = true
            while (interfaces.hasMoreElements()) {
                val intf = interfaces.nextElement()
                if (!first) json.append(",")
                first = false
                val addresses = intf.inetAddresses
                val addrList = StringBuilder("[")
                var addrFirst = true
                while (addresses.hasMoreElements()) {
                    val addr = addresses.nextElement()
                    if (!addrFirst) addrList.append(",")
                    addrFirst = false
                    addrList.append("\"${addr.hostAddress}\"")
                }
                addrList.append("]")
                json.append("{\"name\":\"${intf.name}\",\"mtu\":${intf.mtu},\"addresses\":$addrList}")
            }
            json.append("]")
            singcast.setInterfacesJSON(json.toString())
            AppLog.d(TAG, "detectAndReportInterfaces: reported ${json.length} chars")
        } catch (e: Exception) {
            AppLog.e(TAG, "detectAndReportInterfaces: failed", e)
        }
    }

    fun detectAndReportDefaultInterface(context: android.content.Context) {
        try {
            val cm = context.getSystemService(android.content.Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
            val activeNetwork = cm.activeNetwork
            val linkProperties = if (activeNetwork != null) cm.getLinkProperties(activeNetwork) else null
            val ifaceName = linkProperties?.interfaceName ?: ""
            if (ifaceName.isNotEmpty()) {
                val intf = java.net.NetworkInterface.getByName(ifaceName)
                val mtu = intf?.mtu?.toLong() ?: 0L
                singcast.updateDefaultInterface(ifaceName, mtu, true)
                AppLog.d(TAG, "detectAndReportDefaultInterface: $ifaceName mtu=$mtu")
            }
        } catch (e: Exception) {
            AppLog.e(TAG, "detectAndReportDefaultInterface: failed", e)
        }
    }

    fun notifyVpnStateChanged(connected: Boolean) {
        AppLog.i(TAG, "notifyVpnStateChanged: connected=$connected")
        val sink = eventSink ?: return
        val data = mapOf("type" to 5, "data" to """{"connected":$connected}""")
        mainHandler.post { sink.success(data) }
    }

}
