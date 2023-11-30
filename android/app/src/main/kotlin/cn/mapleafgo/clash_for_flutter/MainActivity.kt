package cn.mapleafgo.clash_for_flutter

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import cn.mapleafgo.mobile.Mobile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  private val CHANNEL = "cn.mapleafgo/socks_vpn_plugin"
  private val REQUEST_CODE = 0

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
        "startVpn" -> {
          startVpn()
          result.success(null)
        }

        "stopVpn" -> {
          stopVpn()
          result.success(null)
        }

        "startService" -> {
          startClash()
          result.success(true)
        }

        "setConfig" -> {
          val config = call.argument<String>("config")
          result.success(Mobile.setConfig(config))
        }

        "setHomeDir" -> {
          val dir = call.argument<String>("dir")
          result.success(Mobile.setHomeDir(dir))
        }

        "startRust" -> {
          val addr = call.argument<String>("addr")
          result.success(Mobile.startRust(addr))
        }

        "verifyMMDB" -> {
          val path = call.argument<String>("path")
          result.success(Mobile.verifyMMDB(path))
        }

        else -> {
          result.notImplemented()
        }
      }
    }
  }

  private fun startVpn() {
    val intent = VpnService.prepare(this)
    if (intent != null) {
      startActivityForResult(intent, REQUEST_CODE);
    } else {
      onActivityResult(REQUEST_CODE, Activity.RESULT_OK, null);
    }

    val vpnIntent = Intent(this, Socks5Service::class.java)
    vpnIntent.action = BaseService.ACTION_CONNECT
    startService(vpnIntent)
  }

  private fun stopVpn() {
    val vpnIntent = Intent(this, Socks5Service::class.java)
    vpnIntent.action = BaseService.ACTION_DISCONNECT
    startService(vpnIntent)
  }

  private fun startClash() {
    val vpnIntent = Intent(this, Socks5Service::class.java)
    vpnIntent.action = BaseService.ACTION_CLASH
    startService(vpnIntent)
  }
}
