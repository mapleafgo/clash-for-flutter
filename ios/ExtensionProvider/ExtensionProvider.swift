import Foundation
import Network
import NetworkExtension
import Singcast

// iOS Network Extension requires Xcode configuration:
// 1. Add target: "Network Extension" → "Packet Tunnel Provider"
// 2. Bundle ID: <main-bundle-id>.tunnel
// 3. Add "Network Extension" entitlement
// 4. Link Singcast.xcframework to the extension target
// 5. Set deployment target to match main app

class ExtensionProvider: NEPacketTunnelProvider {

    private let singcast = MobileSingcast()
    private var pathMonitor: NWPathMonitor?

    override func startTunnel(options: [String: NSObject]?) async throws {
        guard let configContent = options?["configContent"] as? String else {
            throw ExtensionError.missingConfig
        }
        let ruleSetProxy = options?["ruleSetProxy"] as? String ?? ""
        let enableIpv6 = options?["ipv6"] as? Bool ?? true

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        let ipv4 = NEIPv4Settings(addresses: ["172.18.0.1"], subnetMasks: ["255.255.255.252"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        if enableIpv6 {
            let ipv6 = NEIPv6Settings(addresses: ["fdfe:dcba:9876::1"], networkPrefixLengths: [128])
            ipv6.includedRoutes = [NEIPv6Route.default()]
            settings.ipv6Settings = ipv6
        }
        settings.dnsSettings = NEDNSSettings(servers: ["8.8.8.8", "8.8.4.4"])
        settings.mtu = 1500
        try await setTunnelNetworkSettings(settings)

        guard let rawFd = extractTunFd() ?? getTunnelFileDescriptor() else {
            throw ExtensionError.tunnelSetupFailed
        }

        // 初始化内核 home_dir(App Group 容器):日志/缓存/FakeIP 持久化目录。
        // 每次 startTunnel 系统都会创建新的 ExtensionProvider 实例，singcast 也是新创建的。
        guard let home = Self.appGroupContainerPath() else {
            throw ExtensionError.missingHomeDir
        }
        let data = try JSONSerialization.data(withJSONObject: ["home_dir": home])
        guard let jsonStr = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "ExtensionProvider",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to encode home_dir to UTF-8"]
            )
        }
        try singcast.init_(jsonStr)
        // RPC server 与内核 init 一起启停:内核初始化后立即开放 RPC 接口。
        if let rpcPath = Self.appGroupSocketPath() {
            try singcast.startIpcServer(rpcPath)
        }
        singcast.setTunFd(dup(rawFd))
        registerProviders()
        try singcast.start(withContent: configContent, ruleSetProxy: ruleSetProxy)
        startDefaultInterfaceMonitor()
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        stopDefaultInterfaceMonitor()
        // 内核随 Extension 进程同生命周期：VPN 停止时彻底销毁内核，释放所有资源
        singcast.destroy()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard let payload = try? JSONSerialization.jsonObject(with: messageData) as? [String: String],
              let configContent = payload["configContent"] else {
            completionHandler?(Self.encodeReloadResult(error: "invalid config payload"))
            return
        }
        let ruleSetProxy = payload["ruleSetProxy"] ?? ""

        // Extension 进程存活意味着 VPN 已开启，TUN fd 一定可用
        guard let tunFd = extractTunFd() ?? getTunnelFileDescriptor() else {
            // 理论上不会走到这里，除非系统异常
            completionHandler?(Self.encodeReloadResult(error: "TUN fd extraction failed"))
            return
        }
        
        singcast.setTunFd(dup(tunFd))
        do {
            try singcast.start(withContent: configContent, ruleSetProxy: ruleSetProxy)
            completionHandler?(Self.encodeReloadResult())
        } catch {
            completionHandler?(Self.encodeReloadResult(error: "\(error)"))
        }
    }

    /// 序列化 reload 结果回传主 App(成功 {"ok":true};失败 {"ok":false,"error":"…"})。
    private static func encodeReloadResult(error: String? = nil) -> Data {
        let obj: [String: Any] = error.map { ["ok": false, "error": $0] } ?? ["ok": true]
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }

    // MARK: - Provider registration

    private func registerProviders() {
        singcast.setInterfaceProvider(InterfaceProviderAdapter())
        singcast.setWiFiStateProvider(WiFiStateProviderAdapter())
    }

    // MARK: - App Group RPC socket

    /// App Group 共享容器根目录。主 App 与 Extension 解析到同一容器。
    private static func appGroupContainerPath() -> String? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.cn.mapleafgo.singcast"
        )?.path
    }

    /// App Group 共享容器里的 RPC socket 路径(容器根下 command.sock)。
    private static func appGroupSocketPath() -> String? {
        guard let container = appGroupContainerPath() else { return nil }
        return (container as NSString).appendingPathComponent("command.sock")
    }

    // MARK: - TUN fd extraction

    /// Extract fd from NEPacketTunnelProvider's packetFlow via KVO.
    /// Falls back to getTunnelFileDescriptor if KVO fails (private API may change).
    private func extractTunFd() -> Int32? {
        let flow = packetFlow as AnyObject
        guard let socket = flow.value(forKey: "socket") as AnyObject?,
              let fd = socket.value(forKey: "fileDescriptor") as? Int32,
              fd >= 0 else {
            return nil
        }
        return fd
    }

    /// Fallback: iterate file descriptors to find the tunnel fd.
    private func getTunnelFileDescriptor() -> Int32? {
        // Darwin 默认每进程 fd soft limit 256，tunnel fd 在系统初始化阶段分配，
        // 实测落在 5-32 范围内；上限 64 足够覆盖且避免扫到无关 fd。
        for fd in 5..<64 {
            var addr = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let result = withUnsafeMutablePointer(to: &addr) { p -> Int32 in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    getsockname(Int32(fd), $0, &len)
                }
            }
            if result == 0 {
                return Int32(fd)
            }
        }
        return nil
    }

    // MARK: - Default interface monitor

    private func startDefaultInterfaceMonitor() {
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(path)
        }
        monitor.start(queue: DispatchQueue.global())
    }

    private func handlePathUpdate(_ path: Network.NWPath) {
        guard path.status != .unsatisfied,
              let iface = path.availableInterfaces.first
        else {
            singcast.updateDefaultInterface("", index: -1, expensive: false)
            return
        }
        singcast.updateDefaultInterface(iface.name, index: Int64(iface.index), expensive: path.isExpensive)
    }

    private func stopDefaultInterfaceMonitor() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }
}

enum ExtensionError: Error {
    case missingConfig
    case tunnelSetupFailed
    case missingHomeDir
}

// MARK: - gomobile provider adapters

class InterfaceProviderAdapter: NSObject, MobileInterfaceProviderProtocol {
    func getInterfaces() -> String {
        return InterfaceReporter.getInterfacesJSON()
    }
}

class WiFiStateProviderAdapter: NSObject, MobileWiFiStateProviderProtocol {
    func getWiFiState() -> String {
        return InterfaceReporter.getWiFiStateJSON()
    }
}
