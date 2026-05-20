package cn.mapleafgo.singcast

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Binder
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.Build
import androidx.core.app.NotificationCompat

class SingcastVpnService : VpnService() {

    companion object {
        const val ACTION_CONNECT = "cn.mapleafgo.singcast.CONNECT"
        const val ACTION_DISCONNECT = "cn.mapleafgo.singcast.DISCONNECT"
        const val EXTRA_CONFIG = "configContent"
        const val EXTRA_PROXY = "ruleSetProxy"
        const val EXTRA_IPV6 = "ipv6"
        private const val NOTIFY_ID = 2
        private const val CHANNEL_ID = "vpn_status"
        private const val ACTION_DISCONNECT_NOTIFY = "cn.mapleafgo.singcast.DISCONNECT_NOTIFY"
        private const val TAG = "SingcastVpn"

        @Volatile
        var isServiceRunning = false
            private set

        private const val NETWORK_DEBOUNCE_MS = 500L
    }

    private val binder = LocalBinder()
    private val lock = Any()  // protects pfd (fd read/close must be atomic)
    private var pfd: ParcelFileDescriptor? = null
    @Volatile private var running = false
    @Volatile private var disconnected = false
    // dup 后的裸 fd，不经过 ParcelFileDescriptor 包装，避免 fdsan 崩溃
    private var activeTunFd: Int = -1
    private var ipv6Enabled = true
    private var lastUp: Long = 0
    private var lastDown: Long = 0
    private var lastUpTotal: Long = 0
    private var lastDownTotal: Long = 0
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private val networkHandler = Handler(Looper.getMainLooper())
    private val networkUpdateRunnable = Runnable {
        Mobile.detectAndReportInterfaces(this@SingcastVpnService)
        Mobile.detectAndReportDefaultInterface(this@SingcastVpnService)
        Mobile.resetNetwork()
    }

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
                disconnect("notification_button")
                stopSelf()
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
                AppLog.i(TAG, "connect: TUN established, fd=$fd")

                Mobile.setTunFd(fd)

                if (disconnected) {
                    AppLog.w(TAG, "connect: disconnected after setTunFd, aborting")
                    return@Thread
                }

                showNotification()

                Mobile.startWithContent(configContent, ruleSetProxy)
                isServiceRunning = true

                Mobile.detectAndReportInterfaces(this@SingcastVpnService)
                Mobile.detectAndReportDefaultInterface(this@SingcastVpnService)
                registerNetworkCallback()

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
            // /126 匹配 sing-box 内核默认 TUN 地址，/128 会导致响应包被丢弃
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
        synchronized(lock) {
            try { pfd?.close() } catch (_: Exception) {}
            pfd = result
        }
        val fd = result.fd
        AppLog.i(TAG, "establishTun: TUN interface created, fd=$fd")
        return fd
    }

    fun disconnect(reason: String = "unknown") {
        synchronized(lock) {
            if (disconnected) {
                AppLog.d(TAG, "disconnect: already disconnected (reason=$reason), skip")
                return
            }
            disconnected = true
            running = false
        }
        AppLog.i(TAG, "disconnect: reason=$reason")
        isServiceRunning = false
        unregisterNetworkCallback()
        Mobile.unregisterDefaultNetworkCallback(this)
        synchronized(lock) {
            try { pfd?.detachFd() } catch (e: Throwable) {
                AppLog.w(TAG, "disconnect: pfd.detachFd error: ${e.message}")
            }
            pfd = null
            activeTunFd = -1
        }
        Mobile.setVpnService(null)
        stopForeground(STOP_FOREGROUND_REMOVE)
        AppLog.i(TAG, "disconnect: VPN fully disconnected (reason=$reason)")
    }

    fun isRunning(): Boolean = running

    // dup 裸 fd：短暂 adopt 触发 dup，立即 detach 释放 fdsan 跟踪
    private fun dupRawFd(fd: Int): Int {
        val tempPfd = ParcelFileDescriptor.adoptFd(fd)
        val dupedPfd = ParcelFileDescriptor.dup(tempPfd.fileDescriptor)
        tempPfd.detachFd()
        return dupedPfd.detachFd()
    }

    /**
     * Hot-reload config while VPN is active. Duplicates the TUN fd so the kernel's
     * internal stop won't invalidate it, then restarts the core with new config.
     * Uses raw fd tracking (activeTunFd) to avoid fdsan ownership conflicts.
     */
    fun refreshConfig(content: String, ruleSetProxy: String) {
        if (!running || disconnected) {
            AppLog.w(TAG, "refreshConfig: not running or already disconnected, ignoring (running=$running, disconnected=$disconnected)")
            return
        }
        val hasTun = content.contains("tun:") && content.contains("enable: true")
        AppLog.i(TAG, "refreshConfig: config=${content.length} chars, hasTun=$hasTun")
        if (hasTun) {
            try {
                val dupFd = synchronized(lock) {
                    val currentPfd = pfd
                    if (currentPfd != null) {
                        val dupedPfd = ParcelFileDescriptor.dup(currentPfd.fileDescriptor)
                        val fd = dupedPfd.detachFd()
                        try { currentPfd.detachFd() } catch (_: Exception) {}
                        pfd = null
                        activeTunFd = fd
                        fd
                    } else if (activeTunFd >= 0) {
                        val fd = dupRawFd(activeTunFd)
                        activeTunFd = fd
                        fd
                    } else {
                        throw IllegalStateException("TUN not established")
                    }
                }
                Mobile.setTunFd(dupFd)
            } catch (e: Throwable) {
                AppLog.e(TAG, "refreshConfig: failed to dup TUN fd: ${e.message}")
            }
        }
        Mobile.startWithContent(content, ruleSetProxy)
        // 内核重建后接口信息丢失，重新检测
        Mobile.detectAndReportInterfaces(this@SingcastVpnService)
        Mobile.detectAndReportDefaultInterface(this@SingcastVpnService)
        AppLog.i(TAG, "refreshConfig: done")
    }

    fun updateStats(up: Long, down: Long, upTotal: Long, downTotal: Long) {
        lastUp = up
        lastDown = down
        lastUpTotal = upTotal
        lastDownTotal = downTotal
        updateNotification()
    }

    fun protectSocket(fd: Int): Boolean = protect(fd)

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

    private fun registerNetworkCallback() {
        try {
            val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
            val callback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    AppLog.i(TAG, "NetworkCallback: onAvailable")
                    scheduleNetworkUpdate()
                }

                override fun onLost(network: Network) {
                    AppLog.i(TAG, "NetworkCallback: onLost")
                    scheduleNetworkUpdate()
                }

                override fun onLinkPropertiesChanged(network: Network, linkProperties: android.net.LinkProperties) {
                    AppLog.d(TAG, "NetworkCallback: onLinkPropertiesChanged")
                    scheduleNetworkUpdate()
                }
            }
            val request = NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build()
            cm.registerNetworkCallback(request, callback)
            networkCallback = callback
            AppLog.i(TAG, "registerNetworkCallback: registered")
        } catch (e: Exception) {
            AppLog.e(TAG, "registerNetworkCallback: failed", e)
        }
    }

    private fun scheduleNetworkUpdate() {
        networkHandler.removeCallbacks(networkUpdateRunnable)
        networkHandler.postDelayed(networkUpdateRunnable, NETWORK_DEBOUNCE_MS)
    }

    private fun unregisterNetworkCallback() {
        networkHandler.removeCallbacks(networkUpdateRunnable)
        val callback = networkCallback ?: return
        try {
            val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
            cm.unregisterNetworkCallback(callback)
            AppLog.i(TAG, "unregisterNetworkCallback: unregistered")
        } catch (e: Exception) {
            AppLog.w(TAG, "unregisterNetworkCallback: ${e.message}")
        }
        networkCallback = null
    }

}
