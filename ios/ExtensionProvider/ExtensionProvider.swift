import Foundation
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

    override func startTunnel(options: [String: NSObject]?) async throws {
        guard let configContent = options?["configContent"] as? String else {
            throw ExtensionError.missingConfig
        }
        let ruleSetProxy = options?["ruleSetProxy"] as? String ?? ""
        let tunEnabled = options?["tunEnabled"] as? Bool ?? true

        if tunEnabled {
            // Configure tunnel network settings
            let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
            let ipv4 = NEIPv4Settings(addresses: ["172.18.0.1"], subnetMasks: ["255.255.255.252"])
            ipv4.includedRoutes = [NEIPv4Route.default()]
            settings.ipv4Settings = ipv4
            settings.dnsSettings = NEDNSSettings(servers: ["8.8.8.8", "8.8.4.4"])
            settings.mtu = 9000

            try await setTunnelNetworkSettings(settings)

            // Extract TUN file descriptor from the packet flow.
            guard let tunFd = extractTunFd() ?? getTunnelFileDescriptor() else {
                throw ExtensionError.tunnelSetupFailed
            }

            singcast.setTunFd(tunFd)
        }

        try singcast.startWithContent(configContent, ruleSetProxy: ruleSetProxy)
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        try? singcast.stop()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
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
}

enum ExtensionError: Error {
    case missingConfig
    case tunnelSetupFailed
}
