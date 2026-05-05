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
    private static let scanBatchSize = 32

    static func localSubnet() -> String? {
        localSubnets().first
    }

    static func localSubnets() -> [String] {
        var addrList: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&addrList) == 0, let first = addrList else { return [] }
        defer { freeifaddrs(addrList) }

        var subnets: [String] = []
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while ptr != nil {
            defer { ptr = ptr!.pointee.ifa_next }
            guard let address = ptr!.pointee.ifa_addr,
                  address.pointee.sa_family == AF_INET
            else { continue }

            let flags = Int32(ptr!.pointee.ifa_flags)
            guard flags & IFF_UP != 0,
                  flags & IFF_LOOPBACK == 0
            else { continue }

            let addr = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var addrCopy = addr.sin_addr
            inet_ntop(AF_INET, &addrCopy, &buf, socklen_t(INET_ADDRSTRLEN))
            let ip = String(cString: buf)
            let parts = ip.split(separator: ".")
            guard parts.count == 4,
                  parts[0] != "127",
                  !(parts[0] == "169" && parts[1] == "254")
            else { continue }

            let subnet = "\(parts[0]).\(parts[1]).\(parts[2])."
            if !subnets.contains(subnet) {
                subnets.append(subnet)
            }
        }
        return subnets
    }

    private static func scanHost(
        subnet: String,
        host: Int,
        session: URLSession
    ) async -> ScanResult? {
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

    private static func scanBatch(
        subnet: String,
        hosts: ClosedRange<Int>,
        session: URLSession
    ) async -> [ScanResult] {
        await withTaskGroup(of: ScanResult?.self) { group in
            for host in hosts {
                group.addTask {
                    await scanHost(subnet: subnet, host: host, session: session)
                }
            }

            var results: [ScanResult] = []
            for await result in group {
                if let result {
                    results.append(result)
                }
            }
            return results
        }
    }

    static func scan() async -> [ScanResult] {
        let subnets = localSubnets()
        guard !subnets.isEmpty else { return [] }

        let session = URLSession(configuration: {
            let c = URLSessionConfiguration.ephemeral
            c.timeoutIntervalForRequest = timeout
            return c
        }())

        var results: [ScanResult] = []
        for subnet in subnets {
            for batchStart in stride(from: 1, through: 254, by: scanBatchSize) {
                let batchEnd = min(batchStart + scanBatchSize - 1, 254)
                let batchResults = await scanBatch(
                    subnet: subnet,
                    hosts: batchStart...batchEnd,
                    session: session
                )
                results.append(contentsOf: batchResults)
            }
        }
        return results.sorted { $0.url < $1.url }
    }
}
