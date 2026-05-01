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
        override fun onEvent(eventType: Long, jsonPayload: String) {
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

    fun initCore(homeDir: String) {
        AppLog.i(TAG, "initCore: homeDir=$homeDir")
        singcast.init(homeDir)
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

    fun setTunFd(fd: Int) {
        AppLog.i(TAG, "setTunFd: fd=$fd")
        singcast.setTunFd(fd)
    }

    fun queryProxies(): String = singcast.queryProxies()

    fun queryTraffic(): String = singcast.queryTraffic()

    fun queryLogs(): String = singcast.queryLogs()

    fun queryConnections(): String = singcast.queryConnections()

    fun selectProxy(group: String, tag: String) {
        singcast.selectProxy(group, tag)
    }

    fun testDelay(name: String) {
        singcast.testDelay(name)
    }

    fun setMode(mode: String) {
        singcast.setMode(mode)
    }

    fun closeConnection(id: String) {
        singcast.closeConnection(id)
    }

    fun closeAllConnections() {
        singcast.closeAllConnections()
    }

    fun checkConfig(content: String) {
        singcast.checkConfig(content)
    }

    fun getVersion(): String = singcast.version()

    fun notifyVpnStateChanged(connected: Boolean) {
        AppLog.i(TAG, "notifyVpnStateChanged: connected=$connected")
        val sink = eventSink ?: return
        val data = mapOf("type" to 5, "data" to """{"connected":$connected}""")
        mainHandler.post { sink.success(data) }
    }
}
