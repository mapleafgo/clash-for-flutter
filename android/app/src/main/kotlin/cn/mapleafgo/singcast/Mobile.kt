package cn.mapleafgo.singcast

import android.content.Context
import android.net.ConnectivityManager
import android.os.Handler
import android.os.Looper
import cn.mapleafgo.ffi.EventHandler
import org.json.JSONArray
import org.json.JSONObject
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

    fun detectAndReportDefaultInterface(context: Context) {
        try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

            // Find physical default network — skip VPN interfaces.
            // After TUN is established, cm.activeNetwork returns the VPN network.
            // We must report the physical interface (e.g. wlan0), not the VPN interface.
            val result = findPhysicalDefaultNetwork(cm)
            if (result == null) {
                AppLog.w(TAG, "detectDefaultInterface: no physical network found")
                singcast.updateDefaultInterface("", -1, false)
                return
            }
            val (network, ifaceName) = result
            val ni = java.net.NetworkInterface.getByName(ifaceName)
            if (ni != null) {
                val expensive = cm.getNetworkCapabilities(network)?.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_NOT_METERED) != true
                AppLog.i(TAG, "detectDefaultInterface: $ifaceName index=${ni.index} expensive=$expensive")
                singcast.updateDefaultInterface(ifaceName, ni.index.toLong(), expensive)
            } else {
                AppLog.w(TAG, "detectDefaultInterface: NetworkInterface.getByName($ifaceName) returned null")
                singcast.updateDefaultInterface("", -1, false)
            }
        } catch (e: Exception) {
            AppLog.e(TAG, "detectDefaultInterface: error", e)
            singcast.updateDefaultInterface("", -1, false)
        }
    }

    private data class PhysicalNetwork(val network: android.net.Network, val ifaceName: String)

    private fun findPhysicalDefaultNetwork(cm: ConnectivityManager): PhysicalNetwork? {
        // Try active network first if it's not a VPN interface
        val active = cm.activeNetwork
        if (active != null) {
            val lp = cm.getLinkProperties(active)
            val name = lp?.interfaceName
            if (name != null && !isVpnInterfaceName(name)) {
                return PhysicalNetwork(active, name)
            }
        }
        // Active network is VPN or null — find first physical network from allNetworks
        for (network in cm.allNetworks) {
            val lp = cm.getLinkProperties(network) ?: continue
            val name = lp.interfaceName ?: continue
            if (isVpnInterfaceName(name)) continue
            val ni = java.net.NetworkInterface.getByName(name) ?: continue
            if (ni.isUp && !ni.isLoopback) {
                return PhysicalNetwork(network, name)
            }
        }
        return null
    }

    private fun isVpnInterfaceName(name: String): Boolean {
        return name.startsWith("tun") || name.startsWith("tap") ||
            name.startsWith("wg") || name.startsWith("ppp") || name == "singcast0"
    }

    fun detectAndReportInterfaces(context: Context) {
        try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val networks = cm.allNetworks
            val jsonArr = JSONArray()

            for (network in networks) {
                try {
                    val lp = cm.getLinkProperties(network) ?: continue
                    val ifaceName = lp.interfaceName ?: continue
                    val ni = java.net.NetworkInterface.getByName(ifaceName) ?: continue

                    if (!ni.isUp || ni.isLoopback) continue

                    // Skip VPN interfaces
                    if (isVpnInterfaceName(ifaceName)) {
                        AppLog.d(TAG, "detectInterfaces: skipping VPN interface $ifaceName")
                        continue
                    }

                    val addrs = JSONArray()
                    for (addr in ni.interfaceAddresses) {
                        val host = addr.address.hostAddress?.substringBefore("%") ?: continue
                        addrs.put("$host/${addr.networkPrefixLength}")
                    }

                    // Linux interface flags (syscall.IFF_* constants)
                    var flags = 0
                    if (ni.isUp) flags = flags or 0x1               // IFF_UP
                    flags = flags or 0x40                            // IFF_RUNNING (active network)
                    if (!ni.isLoopback && !ni.isPointToPoint) flags = flags or 0x2   // IFF_BROADCAST
                    if (ni.isPointToPoint) flags = flags or 0x10    // IFF_POINTOPOINT
                    if (ni.isLoopback) flags = flags or 0x8         // IFF_LOOPBACK
                    if (ni.supportsMulticast()) flags = flags or 0x1000  // IFF_MULTICAST

                    val caps = cm.getNetworkCapabilities(network)
                    val isEthernet = caps?.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI) == true ||
                        caps?.hasTransport(android.net.NetworkCapabilities.TRANSPORT_ETHERNET) == true

                    jsonArr.put(JSONObject().apply {
                        put("name", ifaceName)
                        put("index", ni.index)
                        put("mtu", ni.mtu)
                        put("addresses", addrs)
                        put("flags", flags)
                        put("type", if (isEthernet) 1 else 0)
                    })
                    AppLog.d(TAG, "detectInterfaces: added $ifaceName (index=${ni.index}, ${addrs.length()} addresses)")
                } catch (e: Exception) {
                    AppLog.w(TAG, "detectInterfaces: skip network", e)
                }
            }

            AppLog.i(TAG, "detectInterfaces: found ${jsonArr.length()} interfaces")
            singcast.setInterfacesJSON(jsonArr.toString())
        } catch (e: Exception) {
            AppLog.e(TAG, "detectInterfaces: error", e)
        }
    }
}
