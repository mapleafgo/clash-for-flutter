package cn.mapleafgo.clash_for_flutter

import android.content.ComponentName
import android.content.Intent
import android.content.ServiceConnection
import android.net.VpnService
import android.os.Bundle
import android.os.IBinder
import cn.mapleafgo.mobile.Mobile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  private val CHANNEL = "cn.mapleafgo/socks_vpn_plugin"
  private val REQUEST_CODE = 0

  private lateinit var cService: BaseService
  private var cBound: Boolean = false

  private val connection = object : ServiceConnection {
    override fun onServiceConnected(className: ComponentName, service: IBinder) {
      val binder = service as BaseService.BaseBinder
      cService = binder.getService()
      cBound = true
    }

    override fun onServiceDisconnected(arg0: ComponentName) {
      cBound = false
    }
  }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    Intent(this, ClashService::class.java).also { intent -> bindService(intent, connection, BIND_AUTO_CREATE) }
    MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
        "startVpn" -> {
          val intent = VpnService.prepare(this)
          if (intent != null) {
            startActivityForResult(intent, REQUEST_CODE);
            result.success(false)
          } else {
            onActivityResult(REQUEST_CODE, RESULT_OK, null);
            result.success(true)
          }
        }

        "stopVpn" -> {
          if (cBound) {
            cService.closeVpnService()
          }
          result.success(cBound)
        }

        "startService" -> {
          if (cBound) {
            val b = cService.setupClashServe()
            result.success(b)
          } else {
            result.success(cBound)
          }
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

  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
    super.onActivityResult(requestCode, resultCode, data)
    if (requestCode == REQUEST_CODE && resultCode == RESULT_OK && cBound) {
      cService.setupVpnServe()
    }
  }

  override fun onDestroy() {
    super.onDestroy()
    unbindService(connection)
    cBound = false
  }
}
