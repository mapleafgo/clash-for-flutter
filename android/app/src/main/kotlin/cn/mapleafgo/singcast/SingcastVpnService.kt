package cn.mapleafgo.singcast

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Binder
import android.os.IBinder
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat

class SingcastVpnService : VpnService() {

    companion object {
        const val ACTION_CONNECT = "cn.mapleafgo.singcast.CONNECT"
        const val ACTION_DISCONNECT = "cn.mapleafgo.singcast.DISCONNECT"
        const val EXTRA_CONFIG = "configContent"
        const val EXTRA_PROXY = "ruleSetProxy"
        private const val NOTIFY_ID = 2
        private const val CHANNEL_ID = "vpn_status"
        private const val ACTION_DISCONNECT_NOTIFY = "cn.mapleafgo.singcast.DISCONNECT_NOTIFY"
        private const val TAG = "SingcastVpn"

        @Volatile
        var isServiceRunning = false
            private set
    }

    private val binder = LocalBinder()
    private val lock = Any()
    private var pfd: ParcelFileDescriptor? = null
    private var running = false
    private var lastUp: Long = 0
    private var lastDown: Long = 0
    private var lastUpTotal: Long = 0
    private var lastDownTotal: Long = 0

    inner class LocalBinder : Binder() {
        fun getService() = this@SingcastVpnService
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONNECT -> {
                val config = intent.getStringExtra(EXTRA_CONFIG) ?: ""
                val proxy = intent.getStringExtra(EXTRA_PROXY) ?: ""
                AppLog.i(TAG, "onStartCommand: CONNECT config=${config.length} chars, proxy='$proxy'")
                connect(config, proxy)
            }
            ACTION_DISCONNECT -> {
                AppLog.i(TAG, "onStartCommand: DISCONNECT (explicit)")
                disconnect("explicit_action")
            }
            ACTION_DISCONNECT_NOTIFY -> {
                AppLog.i(TAG, "onStartCommand: DISCONNECT (notification button)")
                disconnect("notification_button")
            }
        }
        return START_NOT_STICKY
    }

    private fun connect(configContent: String, ruleSetProxy: String) {
        synchronized(lock) {
            if (running) {
                AppLog.w(TAG, "connect: already running, ignoring duplicate start")
                return
            }
            running = true
        }
        AppLog.i(TAG, "connect: starting VPN connection thread")

        Thread({
            try {
                AppLog.d(TAG, "connect: step 1/5 - setting VpnService on Mobile")
                Mobile.setVpnService(this@SingcastVpnService)

                AppLog.d(TAG, "connect: step 2/5 - establishing TUN interface")
                val fd = establishTun()
                AppLog.d(TAG, "connect: TUN established, fd=$fd")

                AppLog.d(TAG, "connect: step 3/5 - setting TUN fd in core")
                Mobile.setTunFd(fd)

                AppLog.d(TAG, "connect: step 4/5 - showing foreground notification")
                showNotification()

                AppLog.d(TAG, "connect: step 5/5 - starting core with content (${configContent.length} chars)")
                val startMs = System.currentTimeMillis()
                Mobile.startWithContent(configContent, ruleSetProxy)
                val elapsed = System.currentTimeMillis() - startMs
                isServiceRunning = true
                AppLog.i(TAG, "connect: core started successfully in ${elapsed}ms, VPN thread exiting")
            } catch (e: Throwable) {
                AppLog.e(TAG, "connect: FAILED - core start threw exception", e)
                disconnect("core_start_failed")
            }
        }, "vpn-connect").start()
    }

    private fun establishTun(): Int {
        AppLog.d(TAG, "establishTun: creating VPN interface")
        val builder = Builder()
            .setSession("singcast")
            .setMtu(9000)
            .addAddress("172.18.0.1", 30)
            .addAddress("fdfe:dcba:9876::1", 128)
            .addRoute("0.0.0.0", 0)
            .addRoute("::", 0)
            .addDnsServer("8.8.8.8")
            .addDnsServer("8.8.4.4")

        val result = builder.establish()
        if (result == null) {
            AppLog.e(TAG, "establishTun: builder.establish() returned null - VPN permission may be revoked")
            throw IllegalStateException("VPN establish failed - check VPN permission")
        }
        pfd = result
        val fd = result.fd
        AppLog.i(TAG, "establishTun: TUN interface created, fd=$fd")
        return fd
    }

    fun disconnect(reason: String = "unknown") {
        AppLog.i(TAG, "disconnect: reason=$reason, running=$running")
        synchronized(lock) { running = false }
        isServiceRunning = false
        try { Mobile.stopCore() } catch (e: Throwable) {
            AppLog.w(TAG, "disconnect: stopCore error: ${e.message}")
        }
        try { pfd?.close() } catch (e: Throwable) {
            AppLog.w(TAG, "disconnect: pfd.close error: ${e.message}")
        }
        pfd = null
        Mobile.setVpnService(null)
        Mobile.notifyVpnStateChanged(false)
        stopForeground(STOP_FOREGROUND_REMOVE)
        AppLog.i(TAG, "disconnect: VPN fully disconnected")
    }

    fun isRunning(): Boolean {
        synchronized(lock) { return running }
    }

    fun updateTraffic(up: Long, down: Long, upTotal: Long, downTotal: Long) {
        lastUp = up
        lastDown = down
        lastUpTotal = upTotal
        lastDownTotal = downTotal
        updateNotification()
    }

    fun protectSocket(fd: Int): Boolean {
        val result = protect(fd)
        if (!result) {
            AppLog.w(TAG, "protectSocket: protect($fd) returned false")
        }
        return result
    }

    private fun buildBaseNotification(): NotificationCompat.Builder {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
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
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
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

    override fun onRevoke() {
        AppLog.w(TAG, "onRevoke: VPN permission revoked by system")
        disconnect("permission_revoked")
    }

    override fun onDestroy() {
        AppLog.i(TAG, "onDestroy: service being destroyed, running=$running")
        disconnect("service_destroyed")
        super.onDestroy()
    }
}
