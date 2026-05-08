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
    @Volatile private var vpnService: SingcastVpnService? = null
    private var vpnBound = false
    private var pendingVpn: VpnRequest? = null

    private data class VpnRequest(
        val configContent: String,
        val ruleSetProxy: String,
        val ipv6: Boolean,
        val result: MethodChannel.Result
    )

    private val vpnConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, service: IBinder) {
            vpnService = (service as SingcastVpnService.LocalBinder).getService()
            vpnBound = true
            val running = vpnService?.isRunning() ?: false
            AppLog.i(tag, "VPN service connected, running=$running")
            if (running) {
                Mobile.setVpnService(vpnService)
                Mobile.notifyVpnStateChanged(true)
            }
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
            startVpn(pending.configContent, pending.ruleSetProxy, pending.ipv6, pending.result)
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

    private val executor = java.util.concurrent.Executors.newCachedThreadPool()
    private fun runOnThread(block: () -> Unit) = executor.execute(block)

    private fun handleMethodCall(method: String, args: Map<String, Any>?, result: MethodChannel.Result) {
        when (method) {
            "initCore" -> runOnThread {
                try {
                    val optionsJSON = args?.str("optionsJSON") ?: ""
                    AppLog.i(tag, "handleMethodCall: initCore optionsJSON=$optionsJSON")
                    Mobile.initCore(optionsJSON)
                    Mobile.detectAndReportInterfaces(this@MainActivity)
                    Mobile.detectAndReportDefaultInterface(this@MainActivity)
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
                    val svc = vpnService
                    AppLog.i(tag, "handleMethodCall: startCoreWithContent (${content.length} chars, vpn=${svc != null})")
                    if (svc != null && svc.isRunning()) {
                        // VPN active: hot-reload config through service (reuses existing TUN)
                        svc.refreshConfig(content, proxy)
                    } else {
                        // No VPN: plain core start
                        Mobile.startWithContent(content, proxy)
                    }
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
            "pause" -> runOnThread {
                try { Mobile.pause(); mainHandler.post { result.success(null) } }
                catch (e: Throwable) { mainHandler.post { result.error("CORE_ERROR", e.message, null) } }
            }
            "wake" -> runOnThread {
                try { Mobile.wake(); mainHandler.post { result.success(null) } }
                catch (e: Throwable) { mainHandler.post { result.error("CORE_ERROR", e.message, null) } }
            }
            "resetNetwork" -> runOnThread {
                try { Mobile.resetNetwork(); mainHandler.post { result.success(null) } }
                catch (e: Throwable) { mainHandler.post { result.error("CORE_ERROR", e.message, null) } }
            }
            // TUN / VPN
            "connectVpn" -> {
                val configContent = args?.str("configContent") ?: ""
                val proxy = args?.str("ruleSetProxy") ?: ""
                val ipv6 = args?.get("ipv6") as? Boolean ?: true
                AppLog.i(tag, "handleMethodCall: connectVpn (${configContent.length} chars, ipv6=$ipv6)")
                requestVpn(configContent, proxy, ipv6, result)
            }
            "disconnectVpn" -> {
                AppLog.i(tag, "handleMethodCall: disconnectVpn")
                stopVpn()
                result.success(true)
            }

            // Queries — run off main thread to avoid blocking UI on large payloads
            "queryProxies" -> runOnThread {
                try { val r = Mobile.queryProxies(); mainHandler.post { result.success(r) } }
                catch (e: Throwable) { mainHandler.post { result.error("CORE_ERROR", e.message, null) } }
            }
            "queryTraffic" -> runOnThread {
                try { val r = Mobile.queryTraffic(); mainHandler.post { result.success(r) } }
                catch (e: Throwable) { mainHandler.post { result.error("CORE_ERROR", e.message, null) } }
            }
            "queryLogs" -> runOnThread {
                try { val r = Mobile.queryLogs(args?.get("clear") as? Boolean ?: false); mainHandler.post { result.success(r) } }
                catch (e: Throwable) { mainHandler.post { result.error("CORE_ERROR", e.message, null) } }
            }
            "queryConnections" -> runOnThread {
                try { val r = Mobile.queryConnections(); mainHandler.post { result.success(r) } }
                catch (e: Throwable) { mainHandler.post { result.error("CORE_ERROR", e.message, null) } }
            }

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
            // Config
            "reloadTUN" -> runOnThread {
                try { Mobile.reloadTUN(); mainHandler.post { result.success(null) } }
                catch (e: Throwable) { mainHandler.post { result.error("CORE_ERROR", e.message, null) } }
            }
            "setOverridePackages" -> runOnThread {
                try { Mobile.setOverridePackages(args?.str("overrideJSON") ?: "{}"); mainHandler.post { result.success(null) } }
                catch (e: Throwable) { mainHandler.post { result.error("CORE_ERROR", e.message, null) } }
            }
            "queryTunOptions" -> result.success(Mobile.queryTunOptions())
            // Proxy
            "setGroupExpand" -> runOnThread {
                try {
                    Mobile.setGroupExpand(args?.str("group") ?: "", args?.get("expand") as? Boolean ?: false)
                    mainHandler.post { result.success(null) }
                } catch (e: Throwable) { mainHandler.post { result.error("CORE_ERROR", e.message, null) } }
            }
            // Logging / Memory
            "setLogLevel" -> {
                Mobile.setLogLevel((args?.get("level") as? Number)?.toInt() ?: 4)
                result.success(null)
            }
            "setMemoryLimit" -> runOnThread {
                try {
                    val r = Mobile.setMemoryLimit(args?.getLong("bytes") ?: 0)
                    mainHandler.post { result.success(r) }
                } catch (e: Throwable) { mainHandler.post { result.error("CORE_ERROR", e.message, null) } }
            }
            "queryMemoryStats" -> result.success(Mobile.queryMemoryStats())
            "flushSystemDNS" -> {
                Mobile.flushSystemDNS()
                result.success(null)
            }
            // Platform
            "needWIFIState" -> result.success(Mobile.needWIFIState())
            "needFindProcess" -> result.success(Mobile.needFindProcess())
            "updateWIFIState" -> { Mobile.updateWIFIState(); result.success(null) }
            "setIncludeAllNetworks" -> {
                Mobile.setIncludeAllNetworks(args?.get("v") as? Boolean ?: false)
                result.success(null)
            }
            "setWIFIState" -> {
                Mobile.setWIFIState(args?.str("ssid") ?: "", args?.str("bssid") ?: "")
                result.success(null)
            }
            "writeMessage" -> {
                Mobile.writeMessage((args?.get("level") as? Number)?.toInt() ?: 4, args?.str("message") ?: "")
                result.success(null)
            }
            // Utilities
            "setLocale" -> { Mobile.setLocale(args?.str("localeID") ?: ""); result.success(null) }
            "checkConfig" -> runOnThread {
                try {
                    val r = Mobile.checkConfig(args?.str("content") ?: "")
                    mainHandler.post { result.success(r) }
                } catch (e: Throwable) {
                    mainHandler.post { result.error("CORE_ERROR", e.message, null) }
                }
            }
            "getVersion" -> runOnThread {
                try {
                    val r = Mobile.getVersion()
                    mainHandler.post { result.success(r) }
                } catch (e: Throwable) {
                    mainHandler.post { result.error("CORE_ERROR", e.message, null) }
                }
            }
            "requestNotificationPermission" -> {
                requestNotificationPermission()
                result.success(null)
            }
            "isVpnRunning" -> {
                val running = SingcastVpnService.isServiceRunning
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

    private fun requestVpn(configContent: String, ruleSetProxy: String, ipv6: Boolean, result: MethodChannel.Result) {
        try {
            val intent = VpnService.prepare(this)
            if (intent != null) {
                AppLog.i(tag, "requestVpn: VPN permission not yet granted, launching dialog")
                pendingVpn = VpnRequest(configContent, ruleSetProxy, ipv6, result)
                vpnPermissionLauncher.launch(intent)
            } else {
                AppLog.i(tag, "requestVpn: VPN permission already granted, starting directly")
                startVpn(configContent, ruleSetProxy, ipv6, result)
            }
        } catch (e: Exception) {
            AppLog.e(tag, "requestVpn: prepare() failed", e)
            result.error("VPN_PREPARE_FAILED", "Failed to prepare VPN: ${e.message}", null)
        }
    }

    private fun startVpn(configContent: String, ruleSetProxy: String, ipv6: Boolean, result: MethodChannel.Result) {
        AppLog.i(tag, "startVpn: starting VPN service (config=${configContent.length} chars, ipv6=$ipv6)")
        val intent = Intent(this, SingcastVpnService::class.java).apply {
            action = SingcastVpnService.ACTION_CONNECT
            putExtra(SingcastVpnService.EXTRA_CONFIG, configContent)
            putExtra(SingcastVpnService.EXTRA_PROXY, ruleSetProxy)
            putExtra(SingcastVpnService.EXTRA_IPV6, ipv6)
        }
        startService(intent)
        bindService(intent, vpnConnection, BIND_AUTO_CREATE)
        result.success(true)
    }

    private fun stopVpn() {
        AppLog.i(tag, "stopVpn: stopping VPN (vpnBound=$vpnBound)")
        vpnService?.disconnect("user_disconnect")
        try { unbindService(vpnConnection) } catch (_: Exception) {}
        stopService(Intent(this, SingcastVpnService::class.java))
        vpnBound = false
        vpnService = null
    }

    override fun onDestroy() {
        AppLog.i(tag, "MainActivity.onDestroy: vpnBound=$vpnBound")
        if (vpnBound) try { unbindService(vpnConnection) } catch (_: Exception) {}
        super.onDestroy()
    }

    override fun onResume() {
        super.onResume()
        if (!vpnBound && SingcastVpnService.isServiceRunning) {
            AppLog.i(tag, "onResume: VPN service running but not bound, re-binding")
            try {
                val intent = Intent(this, SingcastVpnService::class.java)
                bindService(intent, vpnConnection, BIND_AUTO_CREATE)
            } catch (e: Exception) {
                AppLog.w(tag, "onResume: failed to re-bind VPN service: ${e.message}")
            }
        }
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
