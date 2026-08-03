import UIKit
import Flutter
import NetworkExtension
import Singcast

// iOS VPN-only 架构:内核跑在 Network Extension 进程,主 App 是纯 RPC 客户端。
// 主 App 不再持有 FfiSingcast 实例,只负责:
//   1. VPN 生命周期(connect/disconnect/isVpnRunning)— 原生 NETunnelProviderManager
//   2. 内核 reload(reloadCore)— 转发到 Extension 本地 SetTunFd + StartWithContent
//   3. 暴露 App Group 容器路径(getAppGroupPath)— 供 Dart 连 RPC socket
// 运行时控制(查询/切节点/测延迟/切模式)由 Dart 侧 IpcWorker 直连 RPC,不经此 channel。

@main
class AppDelegate: FlutterAppDelegate {

    private var vpnConnected = false
    /// 是否观察到过 connecting/connected：用于区分"启动失败"与"本来就没连"。
    private var vpnActivating = false
    private var methodChannel: FlutterMethodChannel!
    /// 本地订阅转换实例：不依赖 VPN/RPC 连接。
    private let converter = MobileSingcast()

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        guard let controller = window?.rootViewController as? FlutterViewController else {
            return super.application(application, didFinishLaunchingWithOptions: launchOptions)
        }

        let messenger = controller.binaryMessenger
        methodChannel = FlutterMethodChannel(name: "cn.mapleafgo/singcast", binaryMessenger: messenger)
        methodChannel.setMethodCallHandler { call, result in
            self.handle(call: call, result: result)
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(vpnStatusDidChange),
            name: .NEVPNStatusDidChange, object: nil
        )

        // 查询 VPN 真实状态(app 被杀时隧道可能仍在运行)
        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            let status = (managers?.first?.connection as? NETunnelProviderSession)?.status ?? .invalid
            self.vpnConnected = (status == .connected)
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    @objc private func vpnStatusDidChange(_ notification: Notification) {
        guard let session = notification.object as? NETunnelProviderSession else { return }
        let status = session.status
        let connected = status == .connected
        let wasConnected = vpnConnected
        let wasActivating = vpnActivating
        vpnConnected = connected
        if status == .connecting || status == .connected {
            vpnActivating = true
        }

        // 掉线要报，启动失败(connecting → disconnected，从未 connected)也要报，
        // 否则 Extension 起不来时 Dart 侧 vpnConnected 会一直停在 true。
        let died = status == .disconnected || status == .invalid
        if died && (wasConnected || wasActivating) {
            vpnActivating = false
            DispatchQueue.main.async {
                self.methodChannel.invokeMethod("onVpnDisconnected", arguments: nil)
            }
        }
    }

    // MARK: - MethodChannel dispatch

    private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]

        switch call.method {
        // --- App Group ---
        case "getAppGroupPath":
            result(Self.appGroupContainerPath())

        // --- VPN lifecycle ---
        case "connectVpn":
            let config = args["configContent"] as? String ?? ""
            let proxy = args["ruleSetProxy"] as? String ?? ""
            let ipv6 = args["ipv6"] as? Bool ?? false
            startTunnel(configContent: config, ruleSetProxy: proxy, ipv6: ipv6, result: result)
        case "disconnectVpn":
            stopTunnel(result: result)
        case "isVpnRunning":
            NETunnelProviderManager.loadAllFromPreferences { managers, _ in
                let status = (managers?.first?.connection as? NETunnelProviderSession)?.status ?? .invalid
                result(status == .connected)
            }

        // --- Kernel reload (Extension-local: SetTunFd + StartWithContent) ---
        // 裸 RPC core.startWithContent 会因 tunFd 已被消费而失败,故经 sendProviderMessage
        // 让 Extension 本地重新 SetTunFd 再重启内核。
        case "reloadCore":
            let content = args["configContent"] as? String ?? ""
            let proxy = args["ruleSetProxy"] as? String ?? ""
            reloadTunnel(configContent: content, ruleSetProxy: proxy, result: result)

        // --- Local subscription convert (Runner FFI, no VPN required) ---
        case "convert":
            var err: NSError?
            let converted = converter.convert(args["content"] as? String ?? "", error: &err)
            if let err = err {
                result(FlutterError(code: "CONVERT_ERROR", message: err.localizedDescription, details: nil))
            } else {
                result(converted)
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - App Group

    /// App Group 共享容器路径。主 App 与 Extension 解析到同一容器,RPC socket 落此。
    static func appGroupContainerPath() -> String? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.cn.mapleafgo.singcast"
        )?.path
    }

    // MARK: - Network Extension

    private func startTunnel(configContent: String, ruleSetProxy: String, ipv6: Bool = true, result: @escaping FlutterResult) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            if let error = error {
                result(FlutterError(code: "TUNNEL_ERROR", message: error.localizedDescription, details: nil))
                return
            }

            let manager = managers?.first ?? NETunnelProviderManager()
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = (Bundle.main.bundleIdentifier ?? "") + ".tunnel"
            proto.serverAddress = "127.0.0.1"
            manager.protocolConfiguration = proto
            manager.localizedDescription = "Singcast TUN"
            manager.isEnabled = true

            manager.saveToPreferences { error in
                if let error = error {
                    result(FlutterError(code: "TUNNEL_ERROR", message: error.localizedDescription, details: nil))
                    return
                }

                // 必须 reload 后再 start：saveToPreferences 完成时 manager 仍是 stale 的，
                // 直接 startVPNTunnel 会抛 NEVPNErrorConfigurationInvalid
                // ("Missing protocol or protocol has invalid type")，
                // 表现为首次连接失败、第二次才成功。
                manager.loadFromPreferences { error in
                    if let error = error {
                        result(FlutterError(code: "TUNNEL_ERROR", message: error.localizedDescription, details: nil))
                        return
                    }
                    do {
                        try (manager.connection as? NETunnelProviderSession)?.startVPNTunnel(options: [
                            "configContent": configContent as NSObject,
                            "ruleSetProxy": ruleSetProxy as NSObject,
                            "ipv6": ipv6 as NSObject,
                        ])
                        result(true)
                    } catch {
                        result(FlutterError(code: "TUNNEL_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }
        }
    }

    private func stopTunnel(result: @escaping FlutterResult) {
        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            (managers?.first?.connection as? NETunnelProviderSession)?.stopVPNTunnel()
            result(true)
        }
    }

    private func reloadTunnel(configContent: String, ruleSetProxy: String, result: @escaping FlutterResult) {
        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            guard let session = managers?.first?.connection as? NETunnelProviderSession else {
                result(FlutterError(code: "TUNNEL_ERROR", message: "No active tunnel session", details: nil))
                return
            }
            let payload: [String: String] = [
                "configContent": configContent,
                "ruleSetProxy": ruleSetProxy,
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
                result(FlutterError(code: "TUNNEL_ERROR", message: "Failed to serialize config", details: nil))
                return
            }
            do {
                try session.sendProviderMessage(data) { response in
                // 解析 Extension 回传的 reload 结果;失败透传 FlutterError 让 Dart 感知。
                guard let response = response,
                      let json = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
                      let ok = json["ok"] as? Bool else {
                    result(FlutterError(code: "RELOAD_ERROR", message: "Extension 未响应 reload 结果", details: nil))
                    return
                }
                if ok {
                    result(nil)
                } else {
                    let msg = (json["error"] as? String) ?? "reload 失败"
                    result(FlutterError(code: "RELOAD_ERROR", message: msg, details: nil))
                }
            }
            } catch {
                result(FlutterError(code: "RELOAD_ERROR", message: error.localizedDescription, details: nil))
            }
        }
    }
}
