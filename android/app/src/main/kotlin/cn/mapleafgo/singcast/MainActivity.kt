package cn.mapleafgo.singcast

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.IBinder
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

class MainActivity : FlutterFragmentActivity() {

    private val tag = "SingcastVpn"
    private val channelName = "cn.mapleafgo/singcast"
    private lateinit var flutterChannel: MethodChannel
    @Volatile private var vpnService: SingcastVpnService? = null
    private var vpnBound = false
    @Volatile private var pendingVpn: VpnRequest? = null

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
            if (vpnService?.isRunning() == true) {
                Mobile.setVpnService(vpnService)
            }
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
            startVpn(pending.configContent, pending.ruleSetProxy, pending.ipv6, pending.result)
        } else {
            pending?.result?.error("VPN_DENIED", "VPN permission denied", null)
        }
    }

    private val notificationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { /* best-effort */ }

    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Mobile.ensureNativeReady(this)

        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val taskQueue = messenger.makeBackgroundTaskQueue()

        flutterChannel = MethodChannel(messenger, channelName, StandardMethodCodec.INSTANCE, taskQueue)
        flutterChannel.setMethodCallHandler { call, result ->
            handleMethodCall(call.method, call.arguments as? Map<String, Any>, result)
        }

        Mobile.registerPrimaryCallbacks(this) { eventType, payload ->
            // Stats 事件：Native 端直接更新通知栏，不绕 Flutter
            if (eventType == Mobile.EVT_STATS) {
                val svc = vpnService
                if (svc != null && svc.isRunning()) {
                    try {
                        val json = org.json.JSONObject(payload)
                        svc.updateStatsFromRaw(
                            upTotal = json.optLong("up", 0),
                            downTotal = json.optLong("down", 0),
                        )
                    } catch (_: Exception) {}
                }
            }
            runOnUiThread {
                flutterChannel.invokeMethod("onEvent", mapOf("eventType" to eventType, "payload" to payload))
            }
        }

        SingcastVpnService.onVpnDisconnected = {
            runOnUiThread {
                flutterChannel.invokeMethod("onVpnDisconnected", null)
            }
        }
        SingcastVpnService.onVpnConnected = {
            runOnUiThread {
                flutterChannel.invokeMethod("onVpnConnected", null)
            }
        }
    }

    private inline fun safeCall(result: MethodChannel.Result, block: () -> Unit) {
        try {
            block()
            result.success(null)
        } catch (e: Throwable) {
            AppLog.e(tag, "method call failed", e)
            result.error("CORE_ERROR", e.message, null)
        }
    }

    private inline fun <T> safeReply(result: MethodChannel.Result, block: () -> T?) {
        try {
            result.success(block())
        } catch (e: Throwable) {
            AppLog.e(tag, "method call failed", e)
            result.error("CORE_ERROR", e.message, null)
        }
    }

    private fun handleMethodCall(method: String, args: Map<String, Any>?, result: MethodChannel.Result) {
        when (method) {
            // Lifecycle
            "initCore" -> safeCall(result) {
                Mobile.initCore(args?.str("optionsJSON") ?: "")
            }
            "startCoreWithContent" -> {
                val content = args?.str("content") ?: ""
                val proxy = args?.str("ruleSetProxy") ?: ""
                val enabledVpn = args?.get("enabledVpn") as? Boolean ?: false
                val svc = vpnService
                if (svc != null && svc.isRunning()) {
                    // refreshConfig 会阻塞（JNI 同步调用内核热重载），
                    // 在独立线程执行避免阻塞串行任务队列导致 queryStats 无法响应。
                    Thread({
                        try {
                            svc.refreshConfig(content, proxy, enabledVpn)
                            if (!enabledVpn) SingcastVpnService.cacheNonTunConfig(content, proxy)
                            result.success(null)
                        } catch (e: Throwable) {
                            AppLog.e(tag, "refreshConfig failed", e)
                            result.error("CORE_ERROR", e.message, null)
                        }
                    }, "core-reload").start()
                } else if (enabledVpn) {
                    requestVpn(content, proxy, true, result)
                } else {
                    Thread({
                        try {
                            Mobile.startWithContent(content, proxy)
                            SingcastVpnService.cacheNonTunConfig(content, proxy)
                            result.success(null)
                        } catch (e: Throwable) {
                            AppLog.e(tag, "startWithContent failed", e)
                            result.error("CORE_ERROR", e.message, null)
                        }
                    }, "core-reload").start()
                }
            }
            "stopCore" -> safeCall(result) { Mobile.stopCore() }

            // VPN
            "connectVpn" -> {
                val configContent = args?.str("configContent") ?: ""
                val proxy = args?.str("ruleSetProxy") ?: ""
                val ipv6 = args?.get("ipv6") as? Boolean ?: false
                requestVpn(configContent, proxy, ipv6, result)
            }
            "disconnectVpn" -> {
                stopVpn()
                result.success(true)
            }
            "updateNotification" -> {
                val locale = args?.get("locale") as? String
                vpnService?.recreateNotification(locale)
                result.success(null)
            }

            // Queries
            "queryProxies" -> safeReply(result) { Mobile.queryProxies() }
            "queryConnections" -> safeReply(result) { Mobile.queryConnections() }
            "queryMode" -> safeReply(result) { Mobile.queryMode() }
            "queryState" -> safeReply(result) { Mobile.queryState() }

            // Proxy control
            "selectProxy" -> safeCall(result) {
                Mobile.selectProxy(args?.str("group") ?: "", args?.str("tag") ?: "")
            }
            "testDelay" -> safeReply(result) {
                Mobile.testDelay(args?.str("name") ?: "", args?.getInt("timeoutMs") ?: 3000)
            }
            "testGroupDelay" -> safeReply(result) {
                Mobile.testGroupDelay(args?.str("group") ?: "", args?.getInt("timeoutMs") ?: 3000)
            }
            "setMode" -> safeCall(result) { Mobile.setMode(args?.str("mode") ?: "") }
            "closeConnection" -> safeCall(result) { Mobile.closeConnection(args?.str("id") ?: "") }
            "closeAllConnections" -> safeCall(result) { Mobile.closeAllConnections() }

            // Config
            "setGroupExpand" -> safeCall(result) {
                Mobile.setGroupExpand(args?.str("group") ?: "", args?.get("expand") as? Boolean ?: false)
            }

            // Logging / Memory
            "setLogLevel" -> safeCall(result) { Mobile.setLogLevel((args?.get("level") as? Number)?.toInt() ?: 4) }
            "setMemoryLimit" -> safeReply(result) { Mobile.setMemoryLimit(args?.getLong("bytes") ?: 0) }
            "flushSystemDNS" -> safeCall(result) { Mobile.flushSystemDNS() }
            "flushFakeIP" -> safeCall(result) { Mobile.flushFakeIP() }
            "flushDNSCache" -> safeCall(result) { Mobile.flushDNSCache() }
            "triggerGC" -> safeCall(result) { Mobile.triggerGC() }

            // Utilities
            "checkConfig" -> safeReply(result) { Mobile.checkConfig(args?.str("content") ?: "") }
            "convert" -> safeReply(result) { Mobile.convert(args?.str("content") ?: "") }
            "getVersion" -> safeReply(result) { Mobile.getVersion() }
            "isVpnRunning" -> safeReply(result) { SingcastVpnService.isServiceRunning }
            else -> result.notImplemented()
        }
    }

    private fun requestVpn(configContent: String, ruleSetProxy: String, ipv6: Boolean, result: MethodChannel.Result) {
        // channel handler 跑在后台任务队列上，而 ActivityResultLauncher.launch
        // 必须在主线程调用，否则部分 ROM 上授权窗不弹或直接抛异常。
        runOnUiThread {
            requestNotificationPermission()
            try {
                val intent = VpnService.prepare(this)
                if (intent != null) {
                    // 授权窗期间再次请求会覆盖 pending，被覆盖的 Result 若不回调，
                    // Dart 侧 Future 会永久挂起。
                    pendingVpn?.result?.error("VPN_BUSY", "Superseded by a newer VPN request", null)
                    pendingVpn = VpnRequest(configContent, ruleSetProxy, ipv6, result)
                    vpnPermissionLauncher.launch(intent)
                } else {
                    startVpn(configContent, ruleSetProxy, ipv6, result)
                }
            } catch (e: Exception) {
                result.error("VPN_PREPARE_FAILED", "Failed to prepare VPN: ${e.message}", null)
            }
        }
    }

    private fun startVpn(configContent: String, ruleSetProxy: String, ipv6: Boolean, result: MethodChannel.Result) {
        val intent = SingcastVpnService.buildConnectIntent(this, configContent, ruleSetProxy, ipv6)
        SingcastVpnService.startVpnService(this, intent)
        if (!vpnBound) {
            bindService(intent, vpnConnection, BIND_AUTO_CREATE)
        }
        result.success(true)
    }

    private fun stopVpn() {
        vpnService?.disconnect(SingcastVpnService.REASON_USER_DISCONNECT)
        try { unbindService(vpnConnection) } catch (_: Exception) {}
        stopService(Intent(this, SingcastVpnService::class.java))
        vpnBound = false
        vpnService = null
    }

    override fun onDestroy() {
        SingcastVpnService.onVpnDisconnected = null
        SingcastVpnService.onVpnConnected = null
        // 事件监听的 lambda 捕获了本 Activity，不注销会泄漏并把事件投递到
        // 已 detach 的 Flutter 引擎
        Mobile.unregisterCallbacks(this)
        SingcastVpnService.activeService?.restoreFallbackCallbacks()
        // VPN 服务可独立于 Activity 存活，磁贴后续启停仍要写日志；
        // 只有确认服务已停才关闭句柄。
        if (!SingcastVpnService.isServiceRunning) {
            AppLog.close()
        }
        if (vpnBound) try { unbindService(vpnConnection) } catch (_: Exception) {}
        super.onDestroy()
    }

    override fun onResume() {
        super.onResume()
        if (!vpnBound && SingcastVpnService.isServiceRunning) {
            try {
                bindService(Intent(this, SingcastVpnService::class.java), vpnConnection, BIND_AUTO_CREATE)
            } catch (_: Exception) {}
        }
    }

    private fun requestNotificationPermission() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    private fun Map<String, Any>.str(key: String) = this[key] as? String
    private fun Map<String, Any>.getInt(key: String): Int = (this[key] as? Number)?.toInt() ?: 0
    private fun Map<String, Any>.getLong(key: String): Long = (this[key] as? Number)?.toLong() ?: 0
}
