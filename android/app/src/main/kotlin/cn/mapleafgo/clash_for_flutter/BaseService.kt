package cn.mapleafgo.clash_for_flutter

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.net.VpnService
import android.os.Binder
import android.os.IBinder
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat

open class BaseService : VpnService() {
  companion object {
    val ACTION_CONNECT = "cn.mapleafgo.clash_for_flutter.START"
    val ACTION_CLASH = "cn.mapleafgo.clash_for_flutter.CLASH"
    val ACTION_DISCONNECT = "cn.mapleafgo.clash_for_flutter.STOP"
  }

  private val binder = BaseBinder()

  private val notifyID = 1
  private val notifyChannelID = "vpn"
  private val notifyChannelName = "VPN服务状态"
  private var notificationManager: NotificationManager? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    return START_NOT_STICKY
  }

  inner class BaseBinder : Binder() {
    fun getService(): BaseService = this@BaseService
  }

  override fun onBind(intent: Intent?): IBinder? {
    return binder
  }

  protected fun startForeground() {
    notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager

    val channel = NotificationChannel(notifyChannelID, notifyChannelName, NotificationManager.IMPORTANCE_DEFAULT)
    notificationManager?.createNotificationChannel(channel)

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

  open fun setupClashServe(): Boolean {
    throw RuntimeException("Stub!")
  }

  open fun closeVpnService() {
    notificationManager?.cancel(notifyID)
  }

  override fun onDestroy() {
    closeVpnService()
  }

  override fun onRevoke() {
    closeVpnService()
  }
}

