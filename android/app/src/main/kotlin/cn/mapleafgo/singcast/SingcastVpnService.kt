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
        const val EXTRA_TUN_ENABLED = "tunEnabled"
        private const val NOTIFY_ID = 2
        private const val CHANNEL_ID = "vpn_status"
        private const val ACTION_DISCONNECT_NOTIFY = "cn.mapleafgo.singcast.DISCONNECT_NOTIFY"
    }

    private val binder = LocalBinder()
    private var pfd: ParcelFileDescriptor? = null
    private var running = false

    inner class LocalBinder : Binder() {
        fun getService() = this@SingcastVpnService
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONNECT -> {
                val config = intent.getStringExtra(EXTRA_CONFIG) ?: ""
                val proxy = intent.getStringExtra(EXTRA_PROXY) ?: ""
                val tunEnabled = intent.getBooleanExtra(EXTRA_TUN_ENABLED, true)
                connect(config, proxy, tunEnabled)
            }
            ACTION_DISCONNECT, ACTION_DISCONNECT_NOTIFY -> disconnect()
        }
        return START_NOT_STICKY
    }

    private fun connect(configContent: String, ruleSetProxy: String, tunEnabled: Boolean) {
        if (running) return

        try {
            val fd = if (tunEnabled) {
                // TUN 模式：建立完整 VPN，接管所有流量
                establishTun()
            } else {
                // 代理模式：建立最小化 VPN，不接管流量
                // 仅为内核提供 netlink 路由表访问权限
                establishMinimalVpn()
            }
            Mobile.setTunFd(fd)
            Mobile.startWithContent(configContent, ruleSetProxy)
            running = true
            showNotification(tunEnabled)
        } catch (e: Exception) {
            disconnect()
            throw e
        }
    }

    /// TUN 模式：完整 VPN，接管所有流量
    private fun establishTun(): Int {
        val builder = Builder()
            .setSession("singcast")
            .setMtu(9000)
            .addAddress("172.18.0.1", 30)
            .addRoute("0.0.0.0", 0)
            .addDnsServer("8.8.8.8")
            .addDnsServer("8.8.4.4")

        try {
            pfd = builder.establish() ?: throw IllegalStateException("VPN establish failed - check VPN permission")
            return pfd!!.fd
        } catch (e: Exception) {
            throw IllegalStateException("Failed to establish TUN: ${e.message}", e)
        }
    }

    /// 代理模式：最小化 VPN，不接管流量，仅为内核提供 netlink 访问权限
    private fun establishMinimalVpn(): Int {
        val builder = Builder()
            .setSession("singcast")
            .setMtu(9000)
            .addAddress("172.18.0.2", 30)
            // 使用精确路由（/32），不匹配任何实际流量
            .addRoute("255.255.255.255", 32)

        try {
            pfd = builder.establish() ?: throw IllegalStateException("VPN establish failed - check VPN permission")
            return pfd!!.fd
        } catch (e: Exception) {
            throw IllegalStateException("Failed to establish minimal VPN: ${e.message}", e)
        }
    }

    fun disconnect() {
        try { Mobile.stopCore() } catch (_: Exception) {}
        try { pfd?.close() } catch (_: Exception) {}
        pfd = null
        running = false
        Mobile.notifyVpnStateChanged(false)
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    fun isRunning() = running

    fun protectSocket(fd: Int) = protect(fd)

    override fun onRevoke() = disconnect()

    override fun onDestroy() {
        disconnect()
        super.onDestroy()
    }

    private fun showNotification(tunEnabled: Boolean = true) {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "VPN 服务", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Singcast VPN 服务状态"
                setShowBadge(false)
            }
        )

        // 点击通知打开 App
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openPending = PendingIntent.getActivity(
            this, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // 通知栏断开按钮
        val disconnectIntent = Intent(this, SingcastVpnService::class.java).apply {
            action = ACTION_DISCONNECT_NOTIFY
        }
        val disconnectPending = PendingIntent.getService(
            this, 1, disconnectIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val statusText = if (tunEnabled) "TUN 模式已启用" else "代理模式已启用"

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Singcast")
            .setContentText(statusText)
            .setOngoing(true)
            .setContentIntent(openPending)
            .addAction(R.mipmap.ic_launcher, "断开", disconnectPending)
            .build()

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFY_ID, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFY_ID, notification)
        }
    }
}
