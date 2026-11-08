import Foundation
import Darwin
import CoreGraphics

public final class SystemMemoryMonitor: @unchecked Sendable {
    public static let shared = SystemMemoryMonitor()
    
    private var pressureSource: DispatchSourceMemoryPressure?
    public var onPressureChange: (@Sendable (MemoryPressureLevel) -> Void)?
    
    public init() {
        setupPressureMonitoring()
    }
    
    deinit {
        pressureSource?.cancel()
    }
    
    private func setupPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical, .normal],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let data = source.data
            let level: MemoryPressureLevel
            if data.contains(.critical) {
                level = .critical
            } else if data.contains(.warning) {
                level = .warning
            } else {
                level = .normal
            }
            self.onPressureChange?(level)
        }
        source.resume()
        self.pressureSource = source
    }
    
    /// Obtiene una instantánea completa del estado de la memoria RAM del sistema
    public func getSnapshot() -> MemorySnapshot {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let hostPort = mach_host_self()
        
        let kerr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        
        var pageSize: vm_size_t = 16384
        _ = host_page_size(hostPort, &pageSize)
        let ps = UInt64(pageSize)
        
        // Memoria Física Total
        var totalRAM: UInt64 = 0
        var totalRAMSize = MemoryLayout<UInt64>.size
        _ = sysctlbyname("hw.memsize", &totalRAM, &totalRAMSize, nil, 0)
        if totalRAM == 0 {
            totalRAM = 8 * 1024 * 1024 * 1024 // Fallback a 8GB
        }
        
        // Uso de Swap
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        _ = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0)
        
        // Presión de Memoria
        var pressureInt: Int32 = 1
        var pressureIntSize = MemoryLayout<Int32>.size
        _ = sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureInt, &pressureIntSize, nil, 0)
        let pressureLevel = MemoryPressureLevel(rawValue: Int(pressureInt)) ?? .normal
        
        guard kerr == KERN_SUCCESS else {
            return MemorySnapshot(
                totalBytes: totalRAM,
                freeBytes: 0,
                activeBytes: 0,
                inactiveBytes: 0,
                wiredBytes: 0,
                compressedBytes: 0,
                purgeableBytes: 0,
                swapTotalBytes: swap.xsu_total,
                swapUsedBytes: swap.xsu_used,
                pressureLevel: pressureLevel
            )
        }
        
        return MemorySnapshot(
            totalBytes: totalRAM,
            freeBytes: UInt64(stats.free_count) * ps,
            activeBytes: UInt64(stats.active_count) * ps,
            inactiveBytes: UInt64(stats.inactive_count) * ps,
            wiredBytes: UInt64(stats.wire_count) * ps,
            compressedBytes: UInt64(stats.compressor_page_count) * ps,
            purgeableBytes: UInt64(stats.purgeable_count) * ps,
            swapTotalBytes: swap.xsu_total,
            swapUsedBytes: swap.xsu_used,
            pressureLevel: pressureLevel
        )
    }
    
    /// Obtiene la lista de los procesos que más memoria RAM consumen usando APIs de libproc del kernel
    public func getTopProcesses(limit: Int = 5) -> [ProcessInfoItem] {
        var pids = [pid_t](repeating: 0, count: 2048)
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(MemoryLayout<pid_t>.size * pids.count))
        let numPids = Int(bytes) / MemoryLayout<pid_t>.size
        
        var results: [ProcessInfoItem] = []
        let currentPid = getpid()
        
        for i in 0..<numPids {
            let pid = pids[i]
            if pid <= 0 || pid == currentPid { continue }
            
            var info = proc_taskallinfo()
            let size = MemoryLayout<proc_taskallinfo>.size
            let result = proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &info, Int32(size))
            guard result == size else { continue }
            
            let resident = info.ptinfo.pti_resident_size
            guard resident > 10 * 1024 * 1024 else { continue } // Ignorar menos de 10 MB
            
            var buffer = [CChar](repeating: 0, count: 4096)
            let pathResult = proc_pidpath(pid, &buffer, 4096)
            var name = ""
            if pathResult > 0 {
                let path = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                name = (path as NSString).lastPathComponent
            } else {
                var nameBuffer = [CChar](repeating: 0, count: 256)
                proc_name(pid, &nameBuffer, 256)
                name = nameBuffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            }
            
            if name.isEmpty { name = "Process \(pid)" }
            results.append(ProcessInfoItem(pid: pid, name: name, residentBytes: resident))
        }
        
        results.sort { $0.residentBytes > $1.residentBytes }
        return Array(results.prefix(limit))
    }
    
    /// Segundos transcurridos desde la última interacción de mouse o teclado del usuario
    public func getUserIdleTime() -> Double {
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
    
    /// Comprueba si el usuario está inactivo (útil para limpiezas silenciosas sin interrumpir)
    public func isUserIdle(thresholdSeconds: Double = 60.0) -> Bool {
        return getUserIdleTime() >= thresholdSeconds
    }
}
