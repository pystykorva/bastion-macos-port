// SpeedTest.swift - Internet speed test via Cloudflare

import Foundation

enum SpeedEngine {
    
    private static let cloudflareBase = "https://speed.cloudflare.com"
    
    struct SpeedResult {
        var pingMs: Double?
        var jitterMs: Double?
        var downloadMbps: Double?
        var uploadMbps: Double?
    }
    
    static func runTest() async -> SpeedResult {
        var result = SpeedResult()
        
        // Ping test
        let pingTimes = await measurePings()
        if !pingTimes.isEmpty {
            result.pingMs = Double(pingTimes.reduce(0, +)) / Double(pingTimes.count)
            let sorted = pingTimes.sorted()
            if sorted.count > 1 {
                result.jitterMs = Double(sorted[sorted.count - 1] - sorted[0])
            }
        }
        
        // Download test
        result.downloadMbps = await measureDownload()
        
        return result
    }
    
    private static func measurePings() async -> [Double] {
        var times: [Double] = []
        
        for _ in 0..<12 {
            let start = DispatchTime.now()
            do {
                var request = URLRequest(url: URL(string: "\(cloudflareBase)/cdn-cgi/trace")!)
                request.httpMethod = "GET"
                request.timeoutInterval = 5.0
                _ = try await URLSession.shared.data(for: request)
            } catch {
                continue
            }
            let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
            times.append(Double(elapsed) / 1_000_000.0)
        }
        
        return times
    }
    
    private static func measureDownload() async -> Double? {
        let sizes = [2_000_000, 10_000_000]
        
        for size in sizes {
            do {
                let url = URL(string: "\(cloudflareBase)/download/\(size)")!
                var request = URLRequest(url: url)
                request.timeoutInterval = 60.0
                
                let start = DispatchTime.now()
                let (data, _) = try await URLSession.shared.data(for: request)
                let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
                
                if elapsed > 0 {
                    let mbps = Double(data.count) * 8.0 / 1_000_000.0 / (Double(elapsed) / 1_000_000_000.0)
                    return mbps
                }
            } catch {
                continue
            }
        }
        
        return nil
    }
}

