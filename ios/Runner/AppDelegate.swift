import UIKit
import Flutter
import Singcast
import NetworkExtension

@main
class AppDelegate: FlutterAppDelegate {

    private let singcast = FfiSingcast()
    private var eventSink: FlutterEventSink?

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
        // Core lifecycle
        case "initCore":
            do {
                try singcast.init_(args["homeDir"] as? String ?? "")
                result(nil)
            } catch { result(FlutterError(code: "CORE_ERROR", message: error.localizedDescription, details: nil)) }

        case "startCoreWithContent":
            do {
                try singcast.startWithContent(args["content"] as? String ?? "", ruleSetProxy: args["ruleSetProxy"] as? String ?? "")
                result(nil)
            } catch { result(FlutterError(code: "CORE_ERROR", message: error.localizedDescription, details: nil)) }

        case "stopCore":
            do {
                try singcast.stop()
                result(nil)
            } catch { result(FlutterError(code: "CORE_ERROR", message: error.localizedDescription, details: nil)) }

        case "closeCore":
            singcast.close()
            result(nil)

        case "reloadConfig":
            do {
                try singcast.reloadConfig()
                result(nil)
            } catch { result(FlutterError(code: "CORE_ERROR", message: error.localizedDescription, details: nil)) }

        // TUN / VPN
        case "connectVpn":
            let config = args["configContent"] as? String ?? ""
            let proxy = args["ruleSetProxy"] as? String ?? ""
            let tunEnabled = args["tunEnabled"] as? Bool ?? true
            startTunnel(configContent: config, ruleSetProxy: proxy, tunEnabled: tunEnabled, result: result)

        case "disconnectVpn":
            stopTunnel(result: result)

        // Queries (return JSON strings)
        case "queryProxies":
            result(singcast.queryProxies())

        case "queryTraffic":
            result(singcast.queryTraffic())

        case "queryLogs":
            result(singcast.queryLogs())

        case "queryConnections":
            result(singcast.queryConnections())

        // Actions
        case "selectProxy":
            do {
                try singcast.selectProxy(args["group"] as? String ?? "", tag: args["tag"] as? String ?? "")
                result(nil)
            } catch { result(FlutterError(code: "CORE_ERROR", message: error.localizedDescription, details: nil)) }

        case "testDelay":
            do {
                try singcast.testDelay(args["name"] as? String ?? "")
                result(nil)
            } catch { result(FlutterError(code: "CORE_ERROR", message: error.localizedDescription, details: nil)) }

        case "setMode":
            do {
                try singcast.setMode(args["mode"] as? String ?? "")
                result(nil)
            } catch { result(FlutterError(code: "CORE_ERROR", message: error.localizedDescription, details: nil)) }

        case "closeConnection":
            do {
                try singcast.closeConnection(args["id"] as? String ?? "")
                result(nil)
            } catch { result(FlutterError(code: "CORE_ERROR", message: error.localizedDescription, details: nil)) }

        case "closeAllConnections":
            do {
                try singcast.closeAllConnections()
                result(nil)
            } catch { result(FlutterError(code: "CORE_ERROR", message: error.localizedDescription, details: nil)) }

        case "checkConfig":
            do {
                try singcast.checkConfig(args["content"] as? String ?? "")
                result(nil)
            } catch { result(FlutterError(code: "CORE_ERROR", message: error.localizedDescription, details: nil)) }

        case "getVersion":
            result(singcast.version())

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Network Extension

    private func startTunnel(configContent: String, ruleSetProxy: String, tunEnabled: Bool, result: @escaping FlutterResult) {
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
            manager.localizedDescription = tunEnabled ? "Singcast TUN" : "Singcast Proxy"
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
                        "tunEnabled": tunEnabled as NSObject,
                    ])
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
            result(true)
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
