package cn.mapleafgo.singcast

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    private val tag = "SingcastVpn"
    private val channel = "cn.mapleafgo/singcast"
    private val eventChannelName = "cn.mapleafgo/singcast/events"
    private val mainHandler = Handler(Looper.getMainLooper())
    private var vpnService: SingcastVpnService? = null
    private var vpnBound = false
    private var pendingVpn: VpnRequest? = null

    private data class VpnRequest(
        val configContent: String,
        val ruleSetProxy: String,
        val result: MethodChannel.Result
    )

    private val vpnConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, service: IBinder) {
            vpnService = (service as SingcastVpnService.LocalBinder).getService()
            vpnBound = true
            AppLog.i(tag, "VPN service connected, running=${vpnService?.isRunning()}")
        }
        override fun onServiceDisconnected(name: ComponentName) {
            AppLog.w(tag, "VPN service disconnected unexpectedly")
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
            AppLog.i(tag, "VPN permission granted, starting VPN")
            startVpn(pending.configContent, pending.ruleSetProxy, pending.result)
        } else {
            AppLog.w(tag, "VPN permission denied (resultCode=${result.resultCode})")
            pending?.result?.error("VPN_DENIED", "VPN permission denied", null)
        }
    }

    private val notificationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { /* best-effort, ignore result */ }

    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialize file logging early
        AppLog.init(filesDir)
        AppLog.i(tag, "MainActivity: file log initialized")

        val messenger = flutterEngine.dartExecutor.binaryMessenger

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

    private fun runOnThread(block: () -> Unit) = Thread(block).start()

    private fun handleMethodCall(method: String, args: Map<String, Any>?, result: MethodChannel.Result) {
        when (method) {
            "initCore" -> runOnThread {
                try {
                    val homeDir = args?.str("homeDir") ?: ""
                    AppLog.i(tag, "handleMethodCall: initCore homeDir=$homeDir")
                    Mobile.initCore(homeDir)
                    mainHandler.post { result.success(null) }
                } catch (e: Throwable) {
                    AppLog.e(tag, "handleMethodCall: initCore failed", e)
                    mainHandler.post { result.error("CORE_ERROR", e.message, null) }
                }
            }
            "startCoreWithContent" -> runOnThread {
                try {
                    val content = args?.str("content") ?: ""
                    val proxy = args?.str("ruleSetProxy") ?: ""
                    AppLog.i(tag, "handleMethodCall: startCoreWithContent (${content.length} chars, proxy='$proxy') [vpnBound=$vpnBound, vpnRunning=${vpnService?.isRunning()}]")
                    Mobile.startWithContent(content, proxy)
                    mainHandler.post { result.success(null) }
                } catch (e: Throwable) {
                    AppLog.e(tag, "handleMethodCall: startCoreWithContent failed", e)
                    mainHandler.post { result.error("CORE_ERROR", e.message, null) }
                }
            }
            "stopCore" -> runOnThread {
                try {
                    AppLog.i(tag, "handleMethodCall: stopCore")
                    Mobile.stopCore()
                    mainHandler.post { result.success(null) }
                } catch (e: Throwable) {
                    AppLog.e(tag, "handleMethodCall: stopCore failed", e)
                    mainHandler.post { result.error("CORE_ERROR", e.message, null) }
                }
            }
            "destroyCore" -> runOnThread {
                try {
                    AppLog.i(tag, "handleMethodCall: destroyCore")
                    Mobile.destroyCore()
                    mainHandler.post { result.success(null) }
                } catch (e: Throwable) {
                    AppLog.e(tag, "handleMethodCall: destroyCore failed", e)
                    mainHandler.post { result.error("CORE_ERROR", e.message, null) }
                }
            }
            // TUN / VPN
            "connectVpn" -> {
                val configContent = args?.str("configContent") ?: ""
                val proxy = args?.str("ruleSetProxy") ?: ""
                AppLog.i(tag, "handleMethodCall: connectVpn (${configContent.length} chars)")
                requestVpn(configContent, proxy, result)
            }
            "disconnectVpn" -> {
                AppLog.i(tag, "handleMethodCall: disconnectVpn")
                stopVpn()
                result.success(true)
            }

            // Lightweight queries — safe on main thread
            "queryProxies" -> result.success(Mobile.queryProxies())
            "queryTraffic" -> result.success(Mobile.queryTraffic())
            "queryLogs" -> result.success(Mobile.queryLogs())
            "queryConnections" -> result.success(Mobile.queryConnections())

            // Lightweight actions
            "selectProxy" -> runOnThread {
                try {
                    Mobile.selectProxy(args?.str("group") ?: "", args?.str("tag") ?: "")
                    mainHandler.post { result.success(null) }
                } catch (e: Throwable) {
                    mainHandler.post { result.error("CORE_ERROR", e.message, null) }
                }
            }
            "testDelay" -> runOnThread {
                try {
                    Mobile.testDelay(args?.str("name") ?: "")
                    mainHandler.post { result.success(null) }
                } catch (e: Throwable) {
                    mainHandler.post { result.error("CORE_ERROR", e.message, null) }
                }
            }
            "setMode" -> runOnThread {
                try {
                    Mobile.setMode(args?.str("mode") ?: "")
                    mainHandler.post { result.success(null) }
                } catch (e: Throwable) {
                    mainHandler.post { result.error("CORE_ERROR", e.message, null) }
                }
            }
            "closeConnection" -> runOnThread {
                try {
                    Mobile.closeConnection(args?.str("id") ?: "")
                    mainHandler.post { result.success(null) }
                } catch (e: Throwable) {
                    mainHandler.post { result.error("CORE_ERROR", e.message, null) }
                }
            }
            "closeAllConnections" -> runOnThread {
                try {
                    Mobile.closeAllConnections()
                    mainHandler.post { result.success(null) }
                } catch (e: Throwable) {
                    mainHandler.post { result.error("CORE_ERROR", e.message, null) }
                }
            }
            "checkConfig" -> result.success(Mobile.checkConfig(args?.str("content") ?: ""))
            "getVersion" -> result.success(Mobile.getVersion())
            "requestNotificationPermission" -> {
                requestNotificationPermission()
                result.success(null)
            }
            "isVpnRunning" -> {
                val running = vpnService?.isRunning() ?: false
                AppLog.d(tag, "handleMethodCall: isVpnRunning=$running (vpnBound=$vpnBound)")
                result.success(running)
            }
            "updateVpnTraffic" -> {
                vpnService?.updateTraffic(
                    up = args?.getLong("up") ?: 0,
                    down = args?.getLong("down") ?: 0,
                    upTotal = args?.getLong("upTotal") ?: 0,
                    downTotal = args?.getLong("downTotal") ?: 0,
                )
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun requestVpn(configContent: String, ruleSetProxy: String, result: MethodChannel.Result) {
        try {
            val intent = VpnService.prepare(this)
            if (intent != null) {
                AppLog.i(tag, "requestVpn: VPN permission not yet granted, launching dialog")
                pendingVpn = VpnRequest(configContent, ruleSetProxy, result)
                vpnPermissionLauncher.launch(intent)
            } else {
                AppLog.i(tag, "requestVpn: VPN permission already granted, starting directly")
                startVpn(configContent, ruleSetProxy, result)
            }
        } catch (e: Exception) {
            AppLog.e(tag, "requestVpn: prepare() failed", e)
            result.error("VPN_PREPARE_FAILED", "Failed to prepare VPN: ${e.message}", null)
        }
    }

    private fun startVpn(configContent: String, ruleSetProxy: String, result: MethodChannel.Result) {
        AppLog.i(tag, "startVpn: starting VPN service (config=${configContent.length} chars)")
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
        AppLog.i(tag, "stopVpn: stopping VPN (vpnBound=$vpnBound)")
        vpnService?.disconnect("user_disconnect")
        try { unbindService(vpnConnection) } catch (_: Exception) {}
        vpnBound = false
        vpnService = null
    }

    override fun onDestroy() {
        AppLog.i(tag, "MainActivity.onDestroy: vpnBound=$vpnBound")
        if (vpnBound) try { unbindService(vpnConnection) } catch (_: Exception) {}
        super.onDestroy()
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
            ) {
                notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
    }

    private fun Map<String, Any>.str(key: String) = this[key] as? String
    private fun Map<String, Any>.getLong(key: String): Long = (this[key] as? Number)?.toLong() ?: 0
}
