package cn.mapleafgo.singcast

import android.os.Handler
import android.os.Looper
import cn.mapleafgo.ffi.EventHandler
import cn.mapleafgo.ffi.SocketProtector
import cn.mapleafgo.ffi.Singcast
import io.flutter.plugin.common.EventChannel

object Mobile {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val singcast = Singcast()
    private var eventSink: EventChannel.EventSink? = null
    private var vpnService: SingcastVpnService? = null

    private val socketProtector = object : SocketProtector {
        override fun protect(fd: Int): Boolean {
            val svc = vpnService ?: return false
            return svc.protectSocket(fd)
        }
    }

    fun setVpnService(svc: SingcastVpnService?) {
        vpnService = svc
        if (svc != null) {
            singcast.setSocketProtector(socketProtector)
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
        singcast.init(homeDir)
    }

    fun startWithContent(content: String, ruleSetProxy: String) {
        singcast.startWithContent(content, ruleSetProxy)
    }

    fun stopCore() {
        singcast.stop()
    }

    fun closeCore() {
        singcast.close()
    }

    fun reloadConfig() {
        singcast.reloadConfig()
    }

    fun setTunFd(fd: Int) {
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
        val sink = eventSink ?: return
        val data = mapOf("type" to 5, "data" to """{"connected":$connected}""")
        mainHandler.post { sink.success(data) }
    }
}
