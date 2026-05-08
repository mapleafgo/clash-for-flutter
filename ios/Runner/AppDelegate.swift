import UIKit
import Flutter
import Singcast
import NetworkExtension

@main
class AppDelegate: FlutterAppDelegate {

    private let singcast = FfiSingcast()
    private var eventSink: FlutterEventSink?
    private var vpnConnected = false
    private let bgQueue = DispatchQueue(label: "cn.mapleafgo.singcast.core", qos: .userInitiated)

    private lazy var eventHandler = SingcastEventHandler { [weak self] eventType, jsonPayload in
        guard let self, let sink = self.eventSink else { return }
        DispatchQueue.main.async {
            sink(["type": eventType, "data": jsonPayload])
        }
    }

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrator.register(with: self)

        guard let controller = window?.rootViewController as? FlutterViewController else {
            return super.application(application, didFinishLaunchingWithOptions: launchOptions)
        }

        let messenger = controller.binaryMessenger

        FlutterEventChannel(name: "cn.mapleafgo/singcast/events", binaryMessenger: messenger)
            .setStreamHandler(self)

        FlutterMethodChannel(name: "cn.mapleafgo/singcast", binaryMessenger: messenger)
            .setMethodCallHandler { call, result in
                self.handle(call: call, result: result)
            }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - MethodChannel dispatch

    private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]

        switch call.method {
        // Heavy core lifecycle — run off main thread to avoid UI jank
        case "initCore":
            runAsync(result: result) {
                try self.singcast.init_(args["homeDir"] as? String ?? "")
            }
        case "startCoreWithContent":
            let content = args["content"] as? String ?? ""
            let proxy = args["ruleSetProxy"] as? String ?? ""
            if vpnConnected {
                reloadTunnel(configContent: content, ruleSetProxy: proxy, result: result)
            } else {
                runAsync(result: result) {
                    try self.singcast.startWithContent(content, ruleSetProxy: proxy)
                }
            }
        case "stopCore":
            runAsync(result: result) {
                try self.singcast.stop()
            }
        case "closeCore":
            runAsync(result: result) {
                self.singcast.close()
            }

        // TUN / VPN
        case "connectVpn":
            let config = args["configContent"] as? String ?? ""
            let proxy = args["ruleSetProxy"] as? String ?? ""
            startTunnel(configContent: config, ruleSetProxy: proxy, result: result)

        case "disconnectVpn":
            stopTunnel(result: result)

        // Lightweight queries — safe on main thread
        case "queryProxies":
            result(singcast.queryProxies())

        case "queryTraffic":
            result(singcast.queryTraffic())

        case "queryLogs":
            result(singcast.queryLogs())

        case "queryConnections":
            result(singcast.queryConnections())

        // Lightweight actions — run off main thread
        case "selectProxy":
            runAsync(result: result) {
                try self.singcast.selectProxy(args["group"] as? String ?? "", tag: args["tag"] as? String ?? "")
            }
        case "testDelay":
            runAsync(result: result) {
                try self.singcast.testDelay(args["name"] as? String ?? "")
            }
        case "setMode":
            runAsync(result: result) {
                try self.singcast.setMode(args["mode"] as? String ?? "")
            }
        case "closeConnection":
            runAsync(result: result) {
                try self.singcast.closeConnection(args["id"] as? String ?? "")
            }
        case "closeAllConnections":
            runAsync(result: result) {
                try self.singcast.closeAllConnections()
            }

        case "checkConfig":
            result(singcast.checkConfig(args["content"] as? String ?? ""))

        case "getVersion":
            result(singcast.version())

        case "requestNotificationPermission":
            result(nil)

        case "isVpnRunning":
            NETunnelProviderManager.loadAllFromPreferences { managers, _ in
                let status = (managers?.first?.connection as? NETunnelProviderSession)?.status ?? .invalid
                result(status == .connected)
            }

        case "updateVpnTraffic":
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

    private func startTunnel(configContent: String, ruleSetProxy: String, result: @escaping FlutterResult) {
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

// MARK: - EventChannel StreamHandler

extension AppDelegate: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        singcast.setOnEvent(eventHandler)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}

// MARK: - EventHandler wrapper

class SingcastEventHandler: NSObject, FfiEventHandler {
    private let callback: (Int, String) -> Void

    init(_ callback: @escaping (Int, String) -> Void) {
        self.callback = callback
    }

    func onEvent(_ eventType: Int, jsonPayload: String) {
        callback(eventType, jsonPayload)
    }
}
