import UIKit
import Flutter
import Singcast
import NetworkExtension

// MARK: - Kernel callback handler

class SingcastCallbackHandler: NSObject, FfiEventListener {
    private let channel: FlutterMethodChannel
    init(channel: FlutterMethodChannel) { self.channel = channel; super.init() }

    func onEvent(_ eventType: Int32, json: String?) {
        DispatchQueue.main.async {
            self.channel.invokeMethod("onEvent", arguments: [
                "eventType": Int(eventType), "payload": json ?? ""
            ])
        }
    }
}

@main
class AppDelegate: FlutterAppDelegate {

    private let singcast = FfiSingcast()
    private var vpnConnected = false
    private let bgQueue = DispatchQueue(label: "cn.mapleafgo.singcast.core", qos: .userInitiated)
    private var methodChannel: FlutterMethodChannel!
    private var callbackHandler: SingcastCallbackHandler?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrator.register(with: self)

        guard let controller = window?.rootViewController as? FlutterViewController else {
            return super.application(application, didFinishLaunchingWithOptions: launchOptions)
        }

        let messenger = controller.binaryMessenger
        methodChannel = FlutterMethodChannel(name: "cn.mapleafgo/singcast", binaryMessenger: messenger)
        methodChannel.setMethodCallHandler { call, result in
            self.handle(call: call, result: result)
        }

        callbackHandler = SingcastCallbackHandler(channel: methodChannel)
        singcast.setOnEvent(callbackHandler)

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - MethodChannel dispatch

    private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]

        switch call.method {
        // --- Lifecycle ---
        case "initCore":
            runAsync(result: result) {
                let state = self.singcast.state()
                if state != "created" && state != "destroyed" {
                    return
                }
                try self.singcast.init_(args["optionsJSON"] as? String ?? "")
            }
        case "startCoreWithContent":
            let content = args["content"] as? String ?? ""
            let proxy = args["ruleSetProxy"] as? String ?? ""
            if vpnConnected {
                reloadTunnel(configContent: content, ruleSetProxy: proxy, result: result)
            } else {
                runAsync(result: result) {
                    InterfaceReporter.report(self.singcast)
                    try self.singcast.startWithContent(content, ruleSetProxy: proxy)
                }
            }
        case "stopCore":
            singcast.stop()
            result(nil)

        case "resetNetwork":
            singcast.resetNetwork()
            result(nil)

        // --- Queries ---
        case "queryProxies":
            result(singcast.queryProxies())
        case "queryStats":
            result(singcast.queryStats())
        case "queryConnections":
            result(singcast.queryConnections())
        case "queryMode":
            result(singcast.queryMode())
        case "queryState":
            result(singcast.state())

        // --- Proxy Control ---
        case "selectProxy":
            runAsync(result: result) {
                try self.singcast.selectProxy(args["group"] as? String ?? "", tag: args["tag"] as? String ?? "")
            }
        case "testDelay":
            let name = args["name"] as? String ?? ""
            let timeoutMs = args["timeoutMs"] as? Int32 ?? 3000
            bgQueue.async {
                let delay = self.singcast.testDelay(name, timeoutMs: timeoutMs)
                DispatchQueue.main.async { result(delay) }
            }
        case "testGroupDelay":
            let group = args["group"] as? String ?? ""
            let timeoutMs = args["timeoutMs"] as? Int32 ?? 3000
            bgQueue.async {
                let json = self.singcast.testGroupDelay(group, timeoutMs: timeoutMs)
                DispatchQueue.main.async { result(json) }
            }
        case "setMode":
            runAsync(result: result) {
                try self.singcast.setMode(args["mode"] as? String ?? "")
            }
        case "setGroupExpand":
            runAsync(result: result) {
                try self.singcast.setGroupExpand(args["group"] as? String ?? "", expand: args["expand"] as? Bool ?? false)
            }

        // --- Connection Management ---
        case "closeConnection":
            runAsync(result: result) {
                try self.singcast.closeConnection(args["id"] as? String ?? "")
            }
        case "closeAllConnections":
            runAsync(result: result) {
                try self.singcast.closeAllConnections()
            }

        // --- Logging / Memory ---
        case "setLogLevel":
            singcast.setLogLevel(args["level"] as? Int32 ?? 4)
            result(nil)
        case "setMemoryLimit":
            singcast.setMemoryLimit(args["bytes"] as? Int64 ?? 0)
            result(nil)
        case "flushSystemDNS":
            singcast.flushSystemDNS()
            result(nil)
        case "flushFakeIP":
            runAsync(result: result) {
                try self.singcast.flushFakeIP()
            }
        case "flushDNSCache":
            runAsync(result: result) {
                try self.singcast.flushDNSCache()
            }
        case "triggerGC":
            singcast.triggerGC()
            result(nil)

        // --- Utilities ---
        case "checkConfig":
            bgQueue.async {
                do {
                    try self.singcast.checkConfig(args["content"] as? String ?? "")
                    DispatchQueue.main.async { result("") }
                } catch {
                    DispatchQueue.main.async { result(error.localizedDescription) }
                }
            }
        case "getVersion":
            result(singcast.version())

        // --- VPN ---
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
        case "updateVpnStats":
            result(nil)

        // --- Platform (iOS no-ops) ---
        case "requestNotificationPermission":
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Run a blocking operation on a background queue, then post the result back to the main thread.
    private func runAsync(result: @escaping FlutterResult, block: @escaping () throws -> Void) {
        bgQueue.async {
            do {
                try block()
                DispatchQueue.main.async { result(nil) }
            } catch {
                DispatchQueue.main.async { result(FlutterError(code: "CORE_ERROR", message: error.localizedDescription, details: nil)) }
            }
        }
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

                do {
                    try (manager.connection as? NETunnelProviderSession)?.startVPNTunnel(options: [
                        "configContent": configContent as NSObject,
                        "ruleSetProxy": ruleSetProxy as NSObject,
                        "ipv6": ipv6 as NSObject,
                    ])
                    self.vpnConnected = true
                    result(true)
                } catch {
                    result(FlutterError(code: "TUNNEL_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    private func stopTunnel(result: @escaping FlutterResult) {
        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            (managers?.first?.connection as? NETunnelProviderSession)?.stopVPNTunnel()
            self.vpnConnected = false
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
            session.sendProviderMessage(data) { _ in
                result(nil)
            }
        }
    }
}
