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
    @Volatile private var running = false
    @Volatile private var disconnected = false
    private var ipv6Enabled = true
    private var lastUp: Long = 0
    private var lastDown: Long = 0
    private var lastUpTotal: Long = 0
    private var lastDownTotal: Long = 0

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
        if (running) {
            AppLog.w(TAG, "connect: already running, ignoring duplicate start")
            return
        }
        running = true
        disconnected = false
        AppLog.i(TAG, "connect: starting VPN connection thread (config=${configContent.length} chars)")
        ipv6Enabled = enableIpv6

        Thread({
            if (disconnected) {
                AppLog.w(TAG, "connect: disconnected before thread started, aborting")
                return@Thread
            }
            try {
                Mobile.setVpnService(this@SingcastVpnService)

                val fd = establishTun(enableIpv6)
                Mobile.setTunFd(fd)
                AppLog.i(TAG, "connect: TUN established and handed to core, fd=$fd")

                if (disconnected) {
                    AppLog.w(TAG, "connect: disconnected after setTunFd, aborting")
                    return@Thread
                }

                showNotification()

                Mobile.startWithContent(configContent, ruleSetProxy)
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
        if (disconnected) {
            AppLog.d(TAG, "disconnect: already disconnected (reason=$reason), skip")
            return
        }
        disconnected = true
        running = false
        AppLog.i(TAG, "disconnect: reason=$reason")
        isServiceRunning = false
        NetworkMonitor.stopMonitoring(this)
        Mobile.setVpnService(null)
        stopForeground(STOP_FOREGROUND_REMOVE)
        AppLog.i(TAG, "disconnect: VPN fully disconnected (reason=$reason)")
    }

    fun isRunning(): Boolean = running

    fun refreshConfig(content: String, ruleSetProxy: String) {
        if (!running || disconnected) {
            AppLog.w(TAG, "refreshConfig: not running or already disconnected, ignoring (running=$running, disconnected=$disconnected)")
            return
        }
        val hasTun = content.contains("tun:") && content.contains("enable: true")
        AppLog.i(TAG, "refreshConfig: config=${content.length} chars, hasTun=$hasTun")
        if (hasTun) {
            val fd = establishTun(ipv6Enabled)
            Mobile.setTunFd(fd)
        }
        Mobile.startWithContent(content, ruleSetProxy)
        AppLog.i(TAG, "refreshConfig: done")
    }

    fun updateStats(up: Long, down: Long, upTotal: Long, downTotal: Long) {
        if (!running) return
        lastUp = up
        lastDown = down
        lastUpTotal = upTotal
        lastDownTotal = downTotal
        updateNotification()
    }

    fun protectSocket(fd: Int): Boolean = protect(fd)

    private fun buildBaseNotification(): NotificationCompat.Builder {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "VPN 服务", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Singcast VPN 服务状态"
                setShowBadge(false)
            }
        )

        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openPending = PendingIntent.getActivity(
            this, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val disconnectIntent = Intent(this, SingcastVpnService::class.java).apply {
            action = ACTION_DISCONNECT_NOTIFY
        }
        val disconnectPending = PendingIntent.getService(
            this, 1, disconnectIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setContentIntent(openPending)
            .addAction(R.mipmap.ic_launcher, "断开", disconnectPending)
    }

    private fun showNotification() {
        val notification = buildBaseNotification()
            .setContentTitle("Singcast")
            .setContentText(formatTraffic())
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .bigText(formatTrafficDetail())
            )
            .build()

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFY_ID, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFY_ID, notification)
        }
    }

    private fun updateNotification() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val notification = buildBaseNotification()
            .setContentTitle("Singcast")
            .setContentText(formatTraffic())
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .bigText(formatTrafficDetail())
            )
            .build()
        nm.notify(NOTIFY_ID, notification)
    }

    private fun formatTraffic(): String {
        return "↑ ${formatBytes(lastUp)}/s  ↓ ${formatBytes(lastDown)}/s"
    }

    private fun formatTrafficDetail(): String {
        return "网速: ↑ ${formatBytes(lastUp)}/s  ↓ ${formatBytes(lastDown)}/s\n" +
               "流量: ↑ ${formatBytes(lastUpTotal)}  ↓ ${formatBytes(lastDownTotal)}"
    }

    private fun formatBytes(bytes: Long): String {
        if (bytes < 1024) return "$bytes B"
        val kb = bytes / 1024.0
        if (kb < 1024) return "%.1f KB".format(kb)
        val mb = kb / 1024.0
        if (mb < 1024) return "%.1f MB".format(mb)
        val gb = mb / 1024.0
        return "%.2f GB".format(gb)
    }
}
