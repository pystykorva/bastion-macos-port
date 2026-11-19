// PortScanner.swift - TCP port scanning on the router

import Foundation

enum PortScanner {
    
    private static let gatewayPorts: [(port: Int, service: String)] = [
        (21, "FTP"), (22, "SSH"), (23, "Telnet"), (53, "DNS"),
        (80, "HTTP (admin page)"), (443, "HTTPS (admin page)"),
        (4567, "TR-069 (provider management)"), (5000, "UPnP / web service"),
        (7547, "TR-069 / CWMP"), (8080, "HTTP (alternate admin)"),
        (8291, "MikroTik Winbox"), (8443, "HTTPS (alternate admin)"),
        (9000, "Web service"), (30005, "TR-069 alt"),
    ]
    
    static func probeGateway(_ host: String) async -> (openPorts: [(port: Int, service: String)], results: [Int: String]) {
        let semaphore = DispatchSemaphore(value: 16) // max 16 concurrent probes
        
        var tasks: [Task<(port: Int, service: String, state: String), Never>] = []
        
        for portInfo in gatewayPorts {
            tasks.append(Task.detached {
                semaphore.wait()
                defer { semaphore.signal() }
                
                let state = await Self.probePort(host, port: portInfo.port)
                return (port: portInfo.port, service: portInfo.service, state: state)
            })
        }
        
        // Collect results sequentially — no concurrent mutation
        var openPorts: [(port: Int, service: String)] = []
        var results: [Int: String] = [:]
        
        for task in tasks {
            let result = await task.value
            results[result.port] = result.state
            
            if result.state == "open" {
                openPorts.append((port: result.port, service: result.service))
            }
        }
        
        return (openPorts, results)
    }
    
    private static func probePort(_ host: String, port: Int) async -> String {
        return await withCheckedContinuation { continuation in
            // The probe can complete via the normal path OR the timeout path.
            // Exactly one of them must resume the continuation — resuming a
            // checked continuation twice is a fatal runtime error.
            final class ResumeBox: @unchecked Sendable {
                private let lock = NSLock()
                private var resumed = false
                private let continuation: CheckedContinuation<String, Never>
                init(_ continuation: CheckedContinuation<String, Never>) {
                    self.continuation = continuation
                }
                func resume(_ value: String) {
                    lock.lock()
                    guard !resumed else {
                        lock.unlock()
                        return
                    }
                    resumed = true
                    lock.unlock()
                    continuation.resume(returning: value)
                }
            }
            let box = ResumeBox(continuation)
            
            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = ["-c", "echo > /dev/tcp/\(host)/\(port) 2>/dev/null && echo open || echo closed"]
            
            let output = Pipe()
            task.standardOutput = output
            
            let timeout = DispatchTime.now() + .seconds(2)
            
            task.launch()
            
            DispatchQueue.global().asyncAfter(deadline: timeout) {
                if task.isRunning {
                    task.terminate()
                    box.resume("filtered")
                }
            }
            
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let response = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "filtered"
            
            task.waitUntilExit()
            box.resume(response)
        }
    }
}

