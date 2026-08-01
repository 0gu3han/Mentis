import Foundation
import Darwin

/// Discovers the Mentis Flask server on the local network via Bonjour (_mentis._tcp.).
final class ServerDiscovery: NSObject {

    static let shared = ServerDiscovery()
    private override init() { super.init() }

    private var browser: NetServiceBrowser?
    private var pendingServices: [NetService] = []
    private var completion: ((String) -> Void)?

    /// Start browsing. `onFound` is called on the main thread when a server resolves.
    func start(onFound: @escaping (String) -> Void) {
        completion = onFound
        let b = NetServiceBrowser()
        b.delegate = self
        b.searchForServices(ofType: "_mentis._tcp.", inDomain: "local.")
        browser = b
    }

    func stop() {
        browser?.stop()
        browser = nil
        pendingServices.removeAll()
        completion = nil
    }

    // Extract the first IPv4 address from resolved NetService addresses data
    private func ipv4(from service: NetService) -> String? {
        guard let addresses = service.addresses else { return nil }
        for data in addresses {
            let storage = data.withUnsafeBytes { ptr -> sockaddr_storage in
                var s = sockaddr_storage()
                withUnsafeMutableBytes(of: &s) { dst in
                    dst.copyMemory(from: ptr)
                }
                return s
            }
            if Int32(storage.ss_family) == AF_INET {
                var addr = sockaddr_in()
                withUnsafeBytes(of: storage) { src in
                    withUnsafeMutableBytes(of: &addr) { dst in
                        dst.copyMemory(from: src)
                    }
                }
                var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var inAddr = addr.sin_addr
                if inet_ntop(AF_INET, &inAddr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil {
                    return String(cString: buf)
                }
            }
        }
        return nil
    }
}

extension ServerDiscovery: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser,
                           didFind service: NetService,
                           moreComing: Bool) {
        pendingServices.append(service)
        service.delegate = self
        service.resolve(withTimeout: 8)
    }
}

extension ServerDiscovery: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let cb = completion else { return }

        // Prefer raw IP address — avoids .local hostname resolution issues
        let host: String
        if let ip = ipv4(from: sender) {
            host = ip
        } else {
            var h = sender.hostName ?? ""
            if h.hasSuffix(".") { h = String(h.dropLast()) }
            guard !h.isEmpty else { return }
            host = h
        }

        let url = "http://\(host):\(sender.port)"
        DispatchQueue.main.async { cb(url) }
        stop()
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        pendingServices.removeAll { $0 === sender }
    }
}
