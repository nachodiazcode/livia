import Foundation
import SwiftUI
import LiviaCore

@MainActor
final class LiviaViewModel: ObservableObject {
    @Published var snapshot: MemorySnapshot
    @Published var topProcesses: [ProcessInfoItem] = []
    @Published var isCleaning: Bool = false
    @Published var lastCleanResult: PurgeResult?
    @Published var isDaemonRunning: Bool = false
    @Published var isAutoCleanEnabled: Bool = true {
        didSet {
            SmartEngine.shared.isAutoCleanEnabled = isAutoCleanEnabled
        }
    }
    @Published var totalFreedSession: UInt64 = 0
    @Published var statusMessage: String = ""
    
    init() {
        self.snapshot = SystemMemoryMonitor.shared.getSnapshot()
        self.isDaemonRunning = DaemonIPC.shared.isDaemonRunning()
        self.refresh()
    }
    
    func refresh() {
        self.snapshot = SystemMemoryMonitor.shared.getSnapshot()
        self.topProcesses = SystemMemoryMonitor.shared.getTopProcesses(limit: 5)
        self.isDaemonRunning = DaemonIPC.shared.isDaemonRunning()
        self.totalFreedSession = SmartEngine.shared.totalFreedBytes
    }
    
    func cleanNow(forcePrivileged: Bool = false) {
        guard !isCleaning else { return }
        isCleaning = true
        statusMessage = "Optimizando memoria RAM..."
        
        Task.detached(priority: .userInitiated) {
            let result = MemoryCleaner.shared.clean(forcePrivileged: forcePrivileged)
            SmartEngine.shared.recordCleanup(result: result)
            
            await MainActor.run {
                self.isCleaning = false
                self.lastCleanResult = result
                self.refresh()
                
                if result.freedBytes > 0 {
                    self.statusMessage = "¡\(result.formattedFreed) liberados con éxito!"
                } else {
                    self.statusMessage = "Caché de memoria ya optimizada"
                }
            }
        }
    }
    
    func checkAutoClean() {
        guard isAutoCleanEnabled && !isCleaning else { return }
        let decision = SmartEngine.shared.evaluateAutoClean(snapshot: snapshot)
        
        switch decision {
        case .shouldClean(let reason):
            print("[Livia AutoClean] \(reason)")
            cleanNow(forcePrivileged: false)
        case .skip:
            break
        }
    }
    
    func handlePressureChange(_ level: MemoryPressureLevel) {
        refresh()
        if level == .critical && isAutoCleanEnabled {
            cleanNow(forcePrivileged: false)
        }
    }
    
    func installDaemon() {
        let script = "do shell script \"/usr/local/bin/livia daemon --install\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        process.waitUntilExit()
        refresh()
    }
    
    func terminateProcess(pid: Int32) {
        kill(pid, SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.refresh()
        }
    }
}
