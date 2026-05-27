//
//  Generated file. Do not edit.
//

import FlutterMacOS
import Foundation

import desktop_lifecycle
import desktop_tray
import file_picker
import local_notifier
import package_info_plus
import screen_retriever_macos
import share_plus
import url_launcher_macos
import window_manager

func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {
  DesktopLifecyclePlugin.register(with: registry.registrar(forPlugin: "DesktopLifecyclePlugin"))
  DesktopTrayPlugin.register(with: registry.registrar(forPlugin: "DesktopTrayPlugin"))
  FilePickerPlugin.register(with: registry.registrar(forPlugin: "FilePickerPlugin"))
  LocalNotifierPlugin.register(with: registry.registrar(forPlugin: "LocalNotifierPlugin"))
  FPPPackageInfoPlusPlugin.register(with: registry.registrar(forPlugin: "FPPPackageInfoPlusPlugin"))
  ScreenRetrieverMacosPlugin.register(with: registry.registrar(forPlugin: "ScreenRetrieverMacosPlugin"))
  SharePlusMacosPlugin.register(with: registry.registrar(forPlugin: "SharePlusMacosPlugin"))
  UrlLauncherPlugin.register(with: registry.registrar(forPlugin: "UrlLauncherPlugin"))
  WindowManagerPlugin.register(with: registry.registrar(forPlugin: "WindowManagerPlugin"))
}
