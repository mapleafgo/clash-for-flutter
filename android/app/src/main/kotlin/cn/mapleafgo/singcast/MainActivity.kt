package cn.mapleafgo.singcast

import android.content.ComponentName
import android.content.Intent
import android.content.ServiceConnection
import android.net.VpnService
import android.os.IBinder
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channel = "cn.mapleafgo/singcast"
    private val eventChannelName = "cn.mapleafgo/singcast/events"
    private var vpnService: SingcastVpnService? = null
    private var vpnBound = false
    private var pendingVpn: Triple<String, String, MethodChannel.Result>? = null

    private val vpnConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, service: IBinder) {
            vpnService = (service as SingcastVpnService.LocalBinder).getService()
            vpnBound = true
        }
        override fun onServiceDisconnected(name: ComponentName) {
            vpnBound = false
            vpnService = null
        }
    }

    private val vpnPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        val pending = pendingVpn
        pendingVpn = null
        if (result.resultCode == RESULT_OK && pending != null) {
            startVpn(pending.first, pending.second, pending.third)
        } else {
            pending?.third?.error("VPN_DENIED", "VPN permission denied", null)
        }
    }

    override fun onResume() {
        super.onResume()
        val messenger = flutterEngine?.dartExecutor?.binaryMessenger ?: return

        MethodChannel(messenger, channel).setMethodCallHandler { call, result ->
            handleMethodCall(call.method, call.arguments as? Map<String, Any>, result)
        }

        EventChannel(messenger, eventChannelName).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                Mobile.setEventSink(sink)
                Mobile.setupEventHandler()
            }
            override fun onCancel(args: Any?) {
                Mobile.setEventSink(null)
            }
        })
    }

    private fun handleMethodCall(method: String, args: Map<String, Any>?, result: MethodChannel.Result) {
        try {
            when (method) {
                // Core lifecycle
                "initCore" -> { Mobile.initCore(args?.str("homeDir") ?: ""); result.success(null) }
                "startCoreWithContent" -> { Mobile.startWithContent(args?.str("content") ?: "", args?.str("ruleSetProxy") ?: ""); result.success(null) }
                "stopCore" -> { Mobile.stopCore(); result.success(null) }
                "closeCore" -> { Mobile.closeCore(); result.success(null) }
                "reloadConfig" -> { Mobile.reloadConfig(); result.success(null) }

                // TUN / VPN
                "connectVpn" -> requestVpn(args?.str("configContent") ?: "", args?.str("ruleSetProxy") ?: "", result)
                "disconnectVpn" -> { stopVpn(); result.success(true) }

                // Queries
                "queryProxies" -> result.success(Mobile.queryProxies())
                "queryTraffic" -> result.success(Mobile.queryTraffic())
                "queryLogs" -> result.success(Mobile.queryLogs())
                "queryConnections" -> result.success(Mobile.queryConnections())

                // Actions
                "selectProxy" -> { Mobile.selectProxy(args?.str("group") ?: "", args?.str("tag") ?: ""); result.success(null) }
                "testDelay" -> { Mobile.testDelay(args?.str("name") ?: ""); result.success(null) }
                "setMode" -> { Mobile.setMode(args?.str("mode") ?: ""); result.success(null) }
                "closeConnection" -> { Mobile.closeConnection(args?.str("id") ?: ""); result.success(null) }
                "closeAllConnections" -> { Mobile.closeAllConnections(); result.success(null) }
                "checkConfig" -> { Mobile.checkConfig(args?.str("content") ?: ""); result.success(null) }
                "getVersion" -> result.success(Mobile.getVersion())

                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("CORE_ERROR", e.message, null)
        }
    }

    private fun requestVpn(configContent: String, ruleSetProxy: String, result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent != null) {
            pendingVpn = Triple(configContent, ruleSetProxy, result)
            vpnPermissionLauncher.launch(intent)
        } else {
            startVpn(configContent, ruleSetProxy, result)
        }
    }

    private fun startVpn(configContent: String, ruleSetProxy: String, result: MethodChannel.Result) {
        val intent = Intent(this, SingcastVpnService::class.java).apply {
            action = SingcastVpnService.ACTION_CONNECT
            putExtra(SingcastVpnService.EXTRA_CONFIG, configContent)
            putExtra(SingcastVpnService.EXTRA_PROXY, ruleSetProxy)
        }
        startService(intent)
        bindService(intent, vpnConnection, BIND_AUTO_CREATE)
        result.success(true)
    }

    private fun stopVpn() {
        vpnService?.disconnect()
        try { unbindService(vpnConnection) } catch (_: Exception) {}
        vpnBound = false
        vpnService = null
    }

    override fun onDestroy() {
        if (vpnBound) try { unbindService(vpnConnection) } catch (_: Exception) {}
        super.onDestroy()
    }

    private fun Map<String, Any>.str(key: String) = this[key] as? String
}
