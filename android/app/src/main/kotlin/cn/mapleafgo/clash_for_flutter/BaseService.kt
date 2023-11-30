package cn.mapleafgo.clash_for_flutter

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat

open class BaseService : VpnService() {
  companion object {
    val ACTION_CONNECT = "cn.mapleafgo.clash_for_flutter.START"
    val ACTION_CLASH = "cn.mapleafgo.clash_for_flutter.CLASH"
    val ACTION_DISCONNECT = "cn.mapleafgo.clash_for_flutter.STOP"
  }

  protected var tun: ParcelFileDescriptor? = null
  protected var mtu = 1500

  private val notifyID = 1
  private val notifyChannelID = "vpn"
  private val notifyChannelName = "VPN服务状态"
  private lateinit var notificationManager: NotificationManager

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    if (intent?.action == ACTION_DISCONNECT) {
      closeService()
      return START_NOT_STICKY
    } else if (intent?.action == ACTION_CLASH) {
      setupClashServe()
      return START_NOT_STICKY
    }
    setupVpnServe()
    startForeground()
    return START_STICKY
  }

  private fun startForeground() {
    notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager

    val channel = NotificationChannel(notifyChannelID, notifyChannelName, NotificationManager.IMPORTANCE_DEFAULT)
    notificationManager.createNotificationChannel(channel)

    val notification = NotificationCompat.Builder(this, notifyChannelID)
      .setSmallIcon(R.mipmap.ic_launcher)
      .setContentTitle("Clash for Flutter")
      .setContentText("已在后台启动服务")
      .setPriority(NotificationCompat.PRIORITY_DEFAULT)
      .build()
    startForeground(notifyID, notification)
  }

  open fun setupVpnServe() {
    throw RuntimeException("Stub!")
  }

  open fun setupClashServe() {
    throw RuntimeException("Stub!")
  }

  open fun closeService() {
    notificationManager.cancel(notifyID)
    tun?.close()
    stopForeground(Service.STOP_FOREGROUND_REMOVE)
  }

  override fun onDestroy() {
    closeService()
  }

  override fun onRevoke() {
    closeService()
  }
}

