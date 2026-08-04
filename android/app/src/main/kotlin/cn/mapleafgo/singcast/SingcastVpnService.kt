package cn.mapleafgo.singcast

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.ComponentName
import android.content.Intent
import android.content.res.Configuration
import android.net.VpnService
import android.os.Binder
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.service.quicksettings.TileService
import androidx.core.app.NotificationCompat
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean

class SingcastVpnService : VpnService() {

    companion object {
        const val ACTION_CONNECT = "cn.mapleafgo.singcast.CONNECT"
        const val EXTRA_CONFIG = "configContent"
        const val EXTRA_PROXY = "ruleSetProxy"
        const val EXTRA_IPV6 = "ipv6"
        @Volatile private var lastNonTunConfig: String? = null
        @Volatile private var lastNonTunProxy: String = ""

        fun cacheNonTunConfig(content: String, proxy: String) {
            lastNonTunConfig = content
            lastNonTunProxy = proxy
        }

        /// Dart 侧主动发起的断开，不需要回传事件（见 disconnect）。
        const val REASON_USER_DISCONNECT = "user_disconnect"

        /// VPN 断开通知回调，由 MainActivity 注入转发给 Flutter。
        /// 所有断开路径（用户操作、通知栏按钮、系统撤销、内核启动失败、服务销毁）
        /// 都必须触发，否则 Dart 侧 vpnConnected 会永远停在 true。
        var onVpnDisconnected: (() -> Unit)? = null

        /// VPN 连接成功回调，用于磁贴启动后通知 Flutter 同步 UI 状态。
        var onVpnConnected: (() -> Unit)? = null

        private const val NOTIFY_ID = 2
        private const val CHANNEL_ID = "vpn_status"
        private const val ACTION_DISCONNECT_NOTIFY = "cn.mapleafgo.singcast.DISCONNECT_NOTIFY"
        /// 磁贴主动断开的 action：断开到完全直连（不复用 ACTION_DISCONNECT_NOTIFY
        /// 那条回退非 VPN 代理的逻辑）。
        const val ACTION_DISCONNECT_TILE = "cn.mapleafgo.singcast.DISCONNECT_TILE"
        private const val TAG = "SingcastVpn"

        @Volatile
        var isServiceRunning = false
            private set
        @Volatile
        var activeService: SingcastVpnService? = null
            private set

        /// 构造 ACTION_CONNECT 启动 Intent；App 与磁贴共用同一份 intent 契约。
        fun buildConnectIntent(
            context: Context,
            configContent: String,
            proxy: String,
            ipv6: Boolean,
        ): Intent = Intent(context, SingcastVpnService::class.java).apply {
            action = ACTION_CONNECT
            putExtra(EXTRA_CONFIG, configContent)
            putExtra(EXTRA_PROXY, proxy)
            putExtra(EXTRA_IPV6, ipv6)
        }

        /// 统一 VPN 服务启动入口：磁贴可能从后台调 startService 被系统拦截，
        /// 必须用 startForegroundService；SingcastVpnService 连接后本身就是
        /// foreground service（有通知），App 路径复用同一入口无副作用。
        fun startVpnService(context: Context, intent: Intent) {
            context.startForegroundService(intent)
        }
    }

    private val binder = LocalBinder()
    private val running = AtomicBoolean(false)
    private val disconnected = AtomicBoolean(false)
    private var ipv6Enabled = true
    private var upSpeed: Long = 0
    private var downSpeed: Long = 0
    private var lastUpTotal: Long = 0
    private var lastDownTotal: Long = 0
    private var prevUpTotal: Long = 0
    private var prevDownTotal: Long = 0
    private var notificationBuilder: NotificationCompat.Builder? = null
    /// Flutter 端当前 locale，null = 跟随系统。
    private var currentLocale: String? = null

    /// 返回适配当前 locale 的 Context，用于 getString() 解析正确的语言资源。
    private fun localizedContext(): Context {
        val tag = currentLocale ?: return this
        val locale = Locale(tag)
        val config = Configuration(resources.configuration)
        config.setLocale(locale)
        return createConfigurationContext(config)
    }

    inner class LocalBinder : Binder() {
        fun getService() = this@SingcastVpnService
    }

    override fun onCreate() {
        super.onCreate()
        activeService = this
        // 磁贴可能在没有启动 MainActivity 的情况下冷启动服务（进程新建），
        // 而初始化原本只在 MainActivity.configureFlutterEngine 里调用。
        // 缺少 providers 时内核拿不到网络接口，建连后无网络、断开时 TUN 残留。
        Mobile.ensureNativeReady(this)
        registerFallbackCallbacks()
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onDestroy() {
        if (activeService === this) activeService = null
        AppLog.i(TAG, "onDestroy: service being destroyed")
        disconnect("service_destroyed")
        Mobile.unregisterCallbacks(this)
        super.onDestroy()
    }

    override fun onRevoke() {
        AppLog.i(TAG, "onRevoke: VPN permission revoked")
        disconnect("permission_revoked")
        super.onRevoke()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONNECT -> {
                val config = intent.getStringExtra(EXTRA_CONFIG) ?: ""
                val proxy = intent.getStringExtra(EXTRA_PROXY) ?: ""
                val ipv6 = intent.getBooleanExtra(EXTRA_IPV6, true)
                AppLog.i(TAG, "onStartCommand: CONNECT config=${config.length} chars, proxy='$proxy', ipv6=$ipv6")
                // startForegroundService 必须在 5 秒内 startForeground，
                // 先同步满足窗口，再让 connect 线程做耗时初始化。
                showNotification()
                connect(config, proxy, ipv6)
            }
            ACTION_DISCONNECT_NOTIFY -> {
                AppLog.i(TAG, "onStartCommand: DISCONNECT (notification button)")
                val config = lastNonTunConfig
                val proxy = lastNonTunProxy
                Thread({
                    disconnect("notification_button")
                    // disconnect 已 stopCore；有缓存配置则拉起非 VPN 实例
                    if (config != null) {
                        try {
                            Mobile.startWithContent(config, proxy)
                        } catch (e: Throwable) {
                            AppLog.e(TAG, "restart non-tun core failed", e)
                        }
                    }
                    stopSelf()
                }, "vpn-disconnect").start()
            }
            ACTION_DISCONNECT_TILE -> {
                // startForegroundService 可能在服务已销毁后创建新实例，
                // 必须先 startForeground 满足 5 秒窗口要求，否则系统会 crash。
                if (!running.get()) showNotification()
                AppLog.i(TAG, "onStartCommand: DISCONNECT (tile)")
                disconnect("tile_disconnect")
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    private fun connect(configContent: String, ruleSetProxy: String, enableIpv6: Boolean = true) {
        if (!running.compareAndSet(false, true)) {
            AppLog.w(TAG, "connect: already running, ignoring duplicate start")
            return
        }
        val connectStart = System.currentTimeMillis()
        disconnected.set(false)
        resetStats()
        AppLog.i(TAG, "connect: starting VPN connection thread (config=${configContent.length} chars)")
        ipv6Enabled = enableIpv6

        Thread({
            try {
                if (disconnected.get()) {
                    AppLog.w(TAG, "connect: disconnected before start, aborting")
                    return@Thread
                }

                // 磁贴可能在 App 未启动（内核未 init）或内核 stop 后重新连接。
                // startWithContent 要求内核处于 initialized 以上状态，
                // created 状态会报 "invalid state created"。
                Mobile.initCoreForVpnService(this@SingcastVpnService)

                Mobile.startWithContent(configContent, ruleSetProxy, onPrepare = {
                    // 在 coreLock 临界区内复查：disconnect() 可能已经抢先跑完
                    // stopCore，此处若照常 establish 会把 TUN 又拉起来，
                    // 出现"UI 已断开但内核带 TUN 在跑"。
                    if (disconnected.get()) {
                        throw IllegalStateException("disconnected before TUN establish")
                    }
                    Mobile.setVpnService(this@SingcastVpnService)
                    val fd = establishTun(enableIpv6)
                    AppLog.i(TAG, "connect: TUN established, fd=$fd")
                    fd
                })
                if (disconnected.get()) {
                    AppLog.w(TAG, "connect: disconnected during startup, stopping core")
                    Mobile.stopCore()
                    return@Thread
                }
                isServiceRunning = true

                // 启动默认接口监控；网络变化时 Go 层自动 UpdateInterfaces + ResetNetwork
                NetworkMonitor.startMonitoring(this@SingcastVpnService)

                AppLog.i(
                    TAG,
                    "connect: core started successfully " +
                        "(elapsed_ms=${System.currentTimeMillis() - connectStart})",
                )
                requestTileUpdate()
                try { onVpnConnected?.invoke() } catch (e: Throwable) {
                    AppLog.e(TAG, "connect: notify flutter connected failed", e)
                }
            } catch (e: Throwable) {
                AppLog.e(TAG, "connect: FAILED", e)
                disconnect("core_start_failed")
            }
        }, "vpn-connect").start()
    }

    private fun establishTun(enableIpv6: Boolean = true): Int {
        AppLog.d(TAG, "establishTun: creating VPN interface (ipv6=$enableIpv6)")
        val builder = Builder()
            .setSession("tun0")
            .setMtu(1500)
            .addAddress("172.18.0.1", 30)
            .addRoute("0.0.0.0", 0)
            .addDnsServer("8.8.8.8")
            .addDnsServer("8.8.4.4")
        if (enableIpv6) {
            builder.addAddress("fdfe:dcba:9876::1", 126)
            builder.addRoute("::", 0)
        }
        builder.setMetered(false)

        val result = builder.establish()
        if (result == null) {
            AppLog.e(TAG, "establishTun: builder.establish() returned null - VPN permission may be revoked")
            throw IllegalStateException("VPN establish failed - check VPN permission")
        }
        val fd = result.fd
        result.detachFd()
        AppLog.i(TAG, "establishTun: TUN interface created, fd=$fd")
        return fd
    }

    fun disconnect(reason: String = "unknown") {
        if (!disconnected.compareAndSet(false, true)) {
            AppLog.d(TAG, "disconnect: already disconnected (reason=$reason), skip")
            return
        }
        running.set(false)
        AppLog.i(TAG, "disconnect: reason=$reason")
        isServiceRunning = false
        NetworkMonitor.stopMonitoring(this)
        Mobile.setVpnService(null)
        notificationBuilder = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        // 停止内核以关闭 TUN fd，撤销 Android VPN 路由。
        // 仅 stopForeground 不会关 fd：内核仍持有 TUN，VPN 路由残留，
        // 用户"断开 VPN"后流量仍被劫持，必须 stopCore 才能真正停掉 VPN。
        // 通知栏断开等需继续代理的场景，由调用方随后 startWithContent 拉起非 VPN 实例。
        try {
            Mobile.stopCore()
        } catch (e: Throwable) {
            AppLog.e(TAG, "disconnect: stopCore failed", e)
        }
        // 统一在此通知 Flutter：onRevoke / onDestroy / core_start_failed 等路径
        // 此前都不上报，UI 会一直显示"已连接"而流量早已直连。
        // 例外是 user_disconnect：Dart 侧发起时已自行更新状态，再回传一次的话，
        // 若用户紧接着重新开启 TUN，这个迟到事件会把它又关掉。
        if (reason != REASON_USER_DISCONNECT) {
            try {
                onVpnDisconnected?.invoke()
            } catch (e: Throwable) {
                AppLog.e(TAG, "disconnect: notify flutter failed", e)
            }
        }
        requestTileUpdate()
        AppLog.i(TAG, "disconnect: VPN fully disconnected (reason=$reason)")
    }

    /// 通知系统刷新磁贴状态（连接成功/断开后磁贴着色即时更新）。
    private fun requestTileUpdate() {
        try {
            TileService.requestListeningState(
                this,
                ComponentName(this, SingcastTileService::class.java),
            )
        } catch (e: Exception) {
            AppLog.w(TAG, "requestTileUpdate: failed to refresh tile", e)
        }
    }

    fun isRunning(): Boolean = running.get()

    /// 磁贴/服务自持回调：仅更新通知栏速度，不转发 Flutter。
    /// MainActivity 存在时会跳过，Activity 销毁后由 MainActivity 重新调回本方法。
    fun restoreFallbackCallbacks() {
        registerFallbackCallbacks()
    }

    private fun registerFallbackCallbacks() {
        Mobile.registerCallbacks(this) { eventType, payload ->
            if (eventType == Mobile.EVT_STATS && isRunning()) {
                try {
                    val json = org.json.JSONObject(payload)
                    updateStatsFromRaw(
                        upTotal = json.optLong("up", 0),
                        downTotal = json.optLong("down", 0),
                    )
                } catch (_: Exception) {}
            }
        }
    }

    fun refreshConfig(content: String, ruleSetProxy: String, enabledVpn: Boolean = false) {
        if (!running.get() || disconnected.get()) {
            AppLog.w(TAG, "refreshConfig: not running or already disconnected, ignoring (running=$running, disconnected=$disconnected)")
            return
        }
        AppLog.i(TAG, "refreshConfig: config=${content.length} chars, enabledVpn=$enabledVpn")
        if (enabledVpn) {
            Mobile.startWithContent(content, ruleSetProxy, onPrepare = {
                // 必须与 connect() 一样重新绑定：重建 TUN 却不绑定 VpnService，
                // 内核出站就拿不到 protect，会被自己的 TUN 捕获形成路由环路。
                Mobile.setVpnService(this@SingcastVpnService)
                establishTun(ipv6Enabled)
            })
        } else {
            Mobile.startWithContent(content, ruleSetProxy)
        }
        AppLog.i(TAG, "refreshConfig: done")
    }

    /// 内核推送原始统计数据时直接调用，Native 端计算速度并更新通知。
    fun updateStatsFromRaw(upTotal: Long, downTotal: Long) {
        if (!running.get()) return
        upSpeed = (upTotal - prevUpTotal).coerceIn(0, upTotal)
        downSpeed = (downTotal - prevDownTotal).coerceIn(0, downTotal)
        prevUpTotal = upTotal
        prevDownTotal = downTotal
        lastUpTotal = upTotal
        lastDownTotal = downTotal
        updateNotification()
    }

    fun resetStats() {
        prevUpTotal = 0
        prevDownTotal = 0
    }

    fun protectSocket(fd: Int): Boolean = protect(fd)

    private fun ensureNotificationBuilder(): NotificationCompat.Builder {
        notificationBuilder?.let { return it }

        val ctx = localizedContext()
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, ctx.getString(R.string.vpn_notification_channel), NotificationManager.IMPORTANCE_LOW).apply {
                description = ctx.getString(R.string.vpn_notification_channel_desc)
                setShowBadge(false)
            }
        )

        val openPending = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val disconnectPending = PendingIntent.getService(
            this, 1,
            Intent(this, SingcastVpnService::class.java).apply { action = ACTION_DISCONNECT_NOTIFY },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        notificationBuilder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setContentIntent(openPending)
            .addAction(R.mipmap.ic_launcher, ctx.getString(R.string.vpn_disconnect), disconnectPending)
        return notificationBuilder!!
    }

    private fun buildNotification() = ensureNotificationBuilder()
        .setContentTitle("Singcast")
        .setContentText(formatTraffic())
        .setStyle(NotificationCompat.BigTextStyle().bigText(formatTrafficDetail()))
        .build()

    private fun showNotification() {
        startForeground(
            NOTIFY_ID,
            buildNotification(),
            android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
        )
    }

    private fun updateNotification() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFY_ID, buildNotification())
    }

    /// 根据 Flutter 端传入的 locale 重建通知栏文本。
    /// locale 为 null 表示跟随系统，直接使用 Service 的默认 Context。
    fun recreateNotification(locale: String?) {
        notificationBuilder = null
        currentLocale = locale
        updateNotification()
    }

    private fun formatTraffic(): String {
        return "↑ ${formatBytes(upSpeed)}/s  ↓ ${formatBytes(downSpeed)}/s"
    }

    private fun formatTrafficDetail(): String {
        val ctx = localizedContext()
        return "${ctx.getString(R.string.vpn_speed)}: ↑ ${formatBytes(upSpeed)}/s  ↓ ${formatBytes(downSpeed)}/s\n" +
               "${ctx.getString(R.string.vpn_traffic)}: ↑ ${formatBytes(lastUpTotal)}  ↓ ${formatBytes(lastDownTotal)}"
    }

    private fun formatBytes(bytes: Long): String {
        if (bytes < 0) return "0 B"
        if (bytes < 1024) return "$bytes B"
        val kb = bytes / 1024.0
        if (kb < 1024) return "%.1f KB".format(kb)
        val mb = kb / 1024.0
        if (mb < 1024) return "%.1f MB".format(mb)
        val gb = mb / 1024.0
        return "%.2f GB".format(gb)
    }
}
