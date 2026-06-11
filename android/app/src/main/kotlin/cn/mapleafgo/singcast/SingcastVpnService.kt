package cn.mapleafgo.singcast

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat
import java.util.concurrent.atomic.AtomicBoolean

class SingcastVpnService : VpnService() {

    companion object {
        const val ACTION_CONNECT = "cn.mapleafgo.singcast.CONNECT"
        const val ACTION_DISCONNECT = "cn.mapleafgo.singcast.DISCONNECT"
        const val EXTRA_CONFIG = "configContent"
        const val EXTRA_PROXY = "ruleSetProxy"
        const val EXTRA_IPV6 = "ipv6"
        @Volatile private var lastNonTunConfig: String? = null
        @Volatile private var lastNonTunProxy: String = ""

        fun cacheNonTunConfig(content: String, proxy: String) {
            lastNonTunConfig = content
            lastNonTunProxy = proxy
        }

        var onNotificationDisconnect: (() -> Unit)? = null

        private const val NOTIFY_ID = 2
        private const val CHANNEL_ID = "vpn_status"
        private const val ACTION_DISCONNECT_NOTIFY = "cn.mapleafgo.singcast.DISCONNECT_NOTIFY"
        private const val TAG = "SingcastVpn"

        @Volatile
        var isServiceRunning = false
            private set
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

    inner class LocalBinder : Binder() {
        fun getService() = this@SingcastVpnService
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onDestroy() {
        AppLog.i(TAG, "onDestroy: service being destroyed")
        disconnect("service_destroyed")
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
                connect(config, proxy, ipv6)
            }
            ACTION_DISCONNECT -> {
                AppLog.i(TAG, "onStartCommand: DISCONNECT (explicit)")
                disconnect("explicit_action")
            }
            ACTION_DISCONNECT_NOTIFY -> {
                AppLog.i(TAG, "onStartCommand: DISCONNECT (notification button)")
                val config = lastNonTunConfig
                val proxy = lastNonTunProxy
                Thread({
                    disconnect("notification_button")
                    if (config != null) {
                        Mobile.startWithContent(config, proxy)
                    } else {
                        Mobile.stopCore()
                    }
                    onNotificationDisconnect?.invoke()
                    stopSelf()
                }, "vpn-disconnect").start()
            }
        }
        return START_NOT_STICKY
    }

    private fun connect(configContent: String, ruleSetProxy: String, enableIpv6: Boolean = true) {
        if (!running.compareAndSet(false, true)) {
            AppLog.w(TAG, "connect: already running, ignoring duplicate start")
            return
        }
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

                showNotification()

                Mobile.startWithContent(configContent, ruleSetProxy, onPrepare = {
                    Mobile.setVpnService(this@SingcastVpnService)
                    val fd = establishTun(enableIpv6)
                    AppLog.i(TAG, "connect: TUN established, fd=$fd")
                    fd
                })
                isServiceRunning = true

                // 启动默认接口监控；网络变化时 Go 层自动 UpdateInterfaces + ResetNetwork
                NetworkMonitor.startMonitoring(this@SingcastVpnService)

                AppLog.i(TAG, "connect: core started successfully")
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

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
        AppLog.i(TAG, "disconnect: VPN fully disconnected (reason=$reason)")
    }

    fun isRunning(): Boolean = running.get()

    fun refreshConfig(content: String, ruleSetProxy: String, enabledVpn: Boolean = false) {
        if (!running.get() || disconnected.get()) {
            AppLog.w(TAG, "refreshConfig: not running or already disconnected, ignoring (running=$running, disconnected=$disconnected)")
            return
        }
        AppLog.i(TAG, "refreshConfig: config=${content.length} chars, enabledVpn=$enabledVpn")
        if (enabledVpn) {
            Mobile.startWithContent(content, ruleSetProxy, onPrepare = { establishTun(ipv6Enabled) })
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

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "VPN 服务", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Singcast VPN 服务状态"
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
            .addAction(R.mipmap.ic_launcher, "断开", disconnectPending)
        return notificationBuilder!!
    }

    private fun buildNotification() = ensureNotificationBuilder()
        .setContentTitle("Singcast")
        .setContentText(formatTraffic())
        .setStyle(NotificationCompat.BigTextStyle().bigText(formatTrafficDetail()))
        .build()

    private fun showNotification() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFY_ID, buildNotification(), android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFY_ID, buildNotification())
        }
    }

    private fun updateNotification() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFY_ID, buildNotification())
    }

    private fun formatTraffic(): String {
        return "↑ ${formatBytes(upSpeed)}/s  ↓ ${formatBytes(downSpeed)}/s"
    }

    private fun formatTrafficDetail(): String {
        return "网速: ↑ ${formatBytes(upSpeed)}/s  ↓ ${formatBytes(downSpeed)}/s\n" +
               "流量: ↑ ${formatBytes(lastUpTotal)}  ↓ ${formatBytes(lastDownTotal)}"
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
