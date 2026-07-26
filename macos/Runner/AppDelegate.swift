import Cocoa
import FlutterMacOS

@NSApplicationMain
class AppDelegate: FlutterAppDelegate {
  /// 是否已回复过 reply(toApplicationShouldTerminate:)，防止重复回复。
  private var terminationReplied = false

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // 常驻托盘：关窗不退出，退出走托盘菜单或 Cmd+Q
    return false
  }

  /// Cmd+Q / 注销时先让 Dart 停内核并还原系统代理，再真正退出。
  ///
  /// 不做这一步的话，Flutter 引擎被直接杀死，detached 的 singcast-core 与
  /// 已设置的系统代理都会残留——系统代理指向已死端口，用户退出应用后断网。
  override func applicationShouldTerminate(
    _ sender: NSApplication
  ) -> NSApplication.TerminateReply {
    guard let channel = MainFlutterWindow.lifecycleChannel,
          !terminationReplied else {
      return .terminateNow
    }

    // 兜底超时：Dart 无响应（引擎已崩溃等）也必须能退出，绝不能卡住退出流程
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
      self?.replyTermination()
    }
    channel.invokeMethod("prepareTermination", arguments: nil) { [weak self] _ in
      self?.replyTermination()
    }
    return .terminateLater
  }

  private func replyTermination() {
    guard !terminationReplied else { return }
    terminationReplied = true
    NSApp.reply(toApplicationShouldTerminate: true)
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      for window in NSApp.windows {
        if !window.isVisible {
          window.setIsVisible(true)
        }
        window.makeKeyAndOrderFront(self)
        NSApp.activate(ignoringOtherApps: true)
      }
    }
    return true
  }
}
