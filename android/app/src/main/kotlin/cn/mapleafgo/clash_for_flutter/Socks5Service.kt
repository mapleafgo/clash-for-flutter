package cn.mapleafgo.clash_for_flutter

import android.util.Log
import cn.mapleafgo.mobile.Mobile

class Socks5Service : BaseService() {
  private fun setupTun() {
    tun = Builder()
      .setMtu(mtu)
      .addDnsServer("8.8.8.8")
      .addDnsServer("114.114.114.114")
      .addRoute("0.0.0.0", 0)
      .addAddress("198.18.0.1", 30)
      .addDisallowedApplication(packageName)
      .establish() ?: throw Exception("启动隧道失败")
  }

  override fun setupVpnServe() {
    setupTun()
    try {
      Mobile.operateTun(true, tun?.detachFd()!!, mtu)
    } catch (e: Exception) {
      Log.e("socks service", "服务引起异常", e)
    }
  }

  override fun closeService() {
    Log.i("socks service", "停止服务")
    Mobile.operateTun(false, 0, 0)
    super.closeService()
  }

  override fun setupClashServe() {
    Mobile.startService()
  }
}
