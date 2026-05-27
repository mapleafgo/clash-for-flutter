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

    private let singcast = FfiSingcast()
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
            let ipv6 = NEIPv6Settings(addresses: ["fdfe:dcba:9876::1"], prefixLengths: [128])
            ipv6.includedRoutes = [NEIPv6Route.default()]
            settings.ipv6Settings = ipv6
        }
        settings.dnsSettings = NEDNSSettings(servers: ["8.8.8.8", "8.8.4.4"])
        settings.mtu = 9000
        try await setTunnelNetworkSettings(settings)

        guard let rawFd = extractTunFd() ?? getTunnelFileDescriptor() else {
            throw ExtensionError.tunnelSetupFailed
        }

        singcast.setTunFd(dup(rawFd))
        InterfaceReporter.report(singcast)
        try singcast.startWithContent(configContent, ruleSetProxy: ruleSetProxy)
        startDefaultInterfaceMonitor()
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        stopDefaultInterfaceMonitor()
        try? singcast.stop()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard let payload = try? JSONSerialization.jsonObject(with: messageData) as? [String: String],
              let configContent = payload["configContent"] else {
            completionHandler?(nil)
            return
        }
        let ruleSetProxy = payload["ruleSetProxy"] ?? ""

        // Kernel closes the fd during hot reload; dup so packetFlow's original stays valid.
        if let tunFd = extractTunFd() ?? getTunnelFileDescriptor() {
            singcast.setTunFd(dup(tunFd))
        }
        InterfaceReporter.report(singcast)
        try? singcast.startWithContent(configContent, ruleSetProxy: ruleSetProxy)
        completionHandler?(nil)
    }

    // MARK: - TUN fd extraction

    /// Extract fd from NEPacketTunnelProvider's packetFlow via KVO.
    private func extractTunFd() -> Int32? {
        let flow = packetFlow as AnyObject
        if let socket = flow.value(forKey: "socket") as AnyObject?,
           let fd = socket.value(forKey: "fileDescriptor") as? Int32 {
            return fd
        }
        return nil
    }

    /// Fallback: iterate file descriptors to find the tunnel fd.
    private func getTunnelFileDescriptor() -> Int32? {
        for fd in 3..<1024 {
            var addr = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            if getsockname(fd, &addr, &len) == 0 {
                return Int32(fd)
            }
        }
        return nil
    }

    // MARK: - Default interface monitor

    private func startDefaultInterfaceMonitor() {
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        let semaphore = DispatchSemaphore(value: 0)
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(path)
            semaphore.signal()
            monitor.pathUpdateHandler = { [weak self] path in
                self?.handlePathUpdate(path)
            }
        }
        monitor.start(queue: DispatchQueue.global())
        semaphore.wait()
    }

    private func handlePathUpdate(_ path: NWPath) {
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
}
