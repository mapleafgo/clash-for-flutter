import Cocoa
import FlutterMacOS
import ServiceManagement
import window_manager

class MainFlutterWindow: NSWindow {
  /// 供 AppDelegate 在退出前通知 Dart 做清理（见 applicationShouldTerminate）。
  static var lifecycleChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController.init()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    MainFlutterWindow.lifecycleChannel = FlutterMethodChannel(
      name: "cn.mapleafgo/singcast_lifecycle",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    FlutterMethodChannel(
      name: "launch_at_startup",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    .setMethodCallHandler { (_ call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
     case "launchAtStartupIsEnabled":
        result(SMAppService.mainApp.status == .enabled)
      case "launchAtStartupSetEnabled":
        // 强解包会在参数缺失时直接崩溃；失败也必须透传，
        // 否则 Dart 侧无法感知自启注册失败（设置开关会显示成已生效）。
        guard let arguments = call.arguments as? [String: Any],
              let enabled = arguments["setEnabledValue"] as? Bool else {
          result(FlutterError(
            code: "BAD_ARGS",
            message: "setEnabledValue (Bool) is required",
            details: nil
          ))
          return
        }
        do {
          if enabled {
            try SMAppService.mainApp.register()
          } else {
            try SMAppService.mainApp.unregister()
          }
          result(nil)
        } catch {
          result(FlutterError(
            code: "LAUNCH_AT_STARTUP_FAILED",
            message: error.localizedDescription,
            details: nil
          ))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }
}
