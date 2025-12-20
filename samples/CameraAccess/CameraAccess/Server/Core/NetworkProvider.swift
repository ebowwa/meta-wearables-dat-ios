import Foundation
import Network

/// Protocol for providing network information
public protocol NetworkProviding {
    /// Get the best available IP address for external access
    func getBestIPAddress() -> String?
    
    /// Get all available IP addresses
    func getAllIPAddresses() -> [String]
    
    /// Check if the device is connected to a network
    var isConnected: Bool { get }
}

/// Default implementation of NetworkProvider for iOS
public final class NetworkProvider: NetworkProviding {
    
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.asg.networkprovider")
    private var currentPath: NWPath?
    
    public init() {
        self.monitor = NWPathMonitor()
        self.monitor.pathUpdateHandler = { [weak self] path in
            self?.currentPath = path
        }
        self.monitor.start(queue: queue)
    }
    
    deinit {
        monitor.cancel()
    }
    
    public var isConnected: Bool {
        return currentPath?.status == .satisfied
    }
    
    /// Get the best IP address for the server (prefers WiFi)
    public func getBestIPAddress() -> String? {
        var address: String?
        
        // Get list of all interfaces on the local machine
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return nil
        }
        
        defer { freeifaddrs(ifaddr) }
        
        // Iterate through linked list of interfaces
        var ptr = firstAddr
        while true {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            
            // Check for IPv4 interface
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                
                // Prefer en0 (WiFi) or en1
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        socklen_t(0),
                        NI_NUMERICHOST
                    )
                    address = String(cString: hostname)
                    if name == "en0" {
                        break // Prefer en0 (WiFi)
                    }
                }
            }
            
            guard let next = interface.ifa_next else { break }
            ptr = next
        }
        
        return address
    }
    
    /// Get all available IP addresses
    public func getAllIPAddresses() -> [String] {
        var addresses: [String] = []
        
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return addresses
        }
        
        defer { freeifaddrs(ifaddr) }
        
        var ptr = firstAddr
        while true {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            
            if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(
                    interface.ifa_addr,
                    socklen_t(interface.ifa_addr.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    socklen_t(0),
                    NI_NUMERICHOST
                )
                let address = String(cString: hostname)
                if !address.isEmpty && !address.hasPrefix("127.") && !address.hasPrefix("::1") {
                    addresses.append(address)
                }
            }
            
            guard let next = interface.ifa_next else { break }
            ptr = next
        }
        
        return addresses
    }
}
