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
                connect(config, proxy)
            }
            ACTION_DISCONNECT, ACTION_DISCONNECT_NOTIFY -> disconnect()
        }
        return START_NOT_STICKY
    }

    private fun connect(configContent: String, ruleSetProxy: String) {
        synchronized(lock) {
            if (running) return
            running = true
        }

        Thread {
            try {
                Mobile.setVpnService(this@SingcastVpnService)
                val fd = establishTun()
                Mobile.setTunFd(fd)
                Mobile.startWithContent(configContent, ruleSetProxy)
                showNotification()
            } catch (e: Throwable) {
                disconnect()
            }
        }.start()
    }

    private fun establishTun(): Int {
        val builder = Builder()
            .setSession("singcast")
            .setMtu(9000)
            .addAddress("172.18.0.1", 30)
            .addRoute("0.0.0.0", 0)
            .addDnsServer("8.8.8.8")
            .addDnsServer("8.8.4.4")

        pfd = builder.establish() ?: throw IllegalStateException("VPN establish failed - check VPN permission")
        return pfd!!.fd
    }

    fun disconnect() {
        synchronized(lock) { running = false }
        try { Mobile.stopCore() } catch (_: Throwable) {}
        try { pfd?.close() } catch (_: Throwable) {}
        pfd = null
        Mobile.setVpnService(null)
        Mobile.notifyVpnStateChanged(false)
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    fun isRunning() = running

    fun updateTraffic(up: Long, down: Long, upTotal: Long, downTotal: Long) {
        lastUp = up
        lastDown = down
        lastUpTotal = upTotal
        lastDownTotal = downTotal
        updateNotification()
    }

    fun protectSocket(fd: Int) = protect(fd)

    override fun onRevoke() = disconnect()

    override fun onDestroy() {
        disconnect()
        super.onDestroy()
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
}
