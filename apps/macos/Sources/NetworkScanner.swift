import Foundation

struct ScanResult: Identifiable, Equatable {
    let id = UUID()
    let url: String
    let model: String
    let device: String

    var display: String { "\(url) — \(model) (\(device))" }
}

actor NetworkScanner {
    private static let port = 8765
    private static let timeout: TimeInterval = 1.5

    static func localSubnet() -> String? {
        var addrList: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&addrList) == 0, let first = addrList else { return nil }
        defer { freeifaddrs(addrList) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while ptr != nil {
            let name = String(cString: ptr!.pointee.ifa_name)
            if name == "en0" || name == "en1" {
                let family = ptr!.pointee.ifa_addr.pointee.sa_family
                if family == AF_INET {
                    let addr = ptr!.pointee.ifa_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                    var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    var addrCopy = addr.sin_addr
                    inet_ntop(AF_INET, &addrCopy, &buf, socklen_t(INET_ADDRSTRLEN))
                    let ip = String(cString: buf)
                    let parts = ip.split(separator: ".")
                    if parts.count == 4 {
                        return "\(parts[0]).\(parts[1]).\(parts[2])."
                    }
                }
            }
            ptr = ptr!.pointee.ifa_next
        }
        return nil
    }

    static func scan() async -> [ScanResult] {
        guard let subnet = localSubnet() else { return [] }

        let session = URLSession(configuration: {
            let c = URLSessionConfiguration.ephemeral
            c.timeoutIntervalForRequest = timeout
            return c
        }())

        return await withTaskGroup(of: ScanResult?.self) { group in
            for host in 1...254 {
                group.addTask {
                    let url = "http://\(subnet)\(host):\(port)/health"
                    guard let reqURL = URL(string: url) else { return nil }
                    var req = URLRequest(url: reqURL)
                    req.httpMethod = "GET"
                    req.timeoutInterval = timeout

                    do {
                        let (data, response) = try await session.data(for: req)
                        guard let http = response as? HTTPURLResponse,
                              http.statusCode == 200,
                              let health = try? JSONDecoder().decode(HealthResponse.self, from: data)
                        else { return nil }
                        return ScanResult(
                            url: "http://\(subnet)\(host):\(port)",
                            model: health.model,
                            device: health.device
                        )
                    } catch {
                        return nil
                    }
                }
            }

            var results: [ScanResult] = []
            for await result in group {
                if let r = result { results.append(r) }
            }
            return results
        }
    }
}
