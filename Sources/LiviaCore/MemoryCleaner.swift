import Foundation
import Darwin

public final class MemoryCleaner: @unchecked Sendable {
    public static let shared = MemoryCleaner()
    
    public init() {}
    
    /// Realiza una limpieza inteligente utilizando el mejor método disponible
    /// (Daemon de Kernel si está instalado, o Modo Usuario si no lo está).
    public func clean(forcePrivileged: Bool = false) -> PurgeResult {
        let startTime = Date()
        let beforeSnapshot = SystemMemoryMonitor.shared.getSnapshot()
        
        var methodUsed: PurgeMethod = .userSpace
        var purgeSuccess = true
        var message = ""
        
        if DaemonIPC.shared.isDaemonRunning() {
            // El daemon está activo y corriendo como root: la forma más rápida y sin contraseñas
            methodUsed = .rootDaemon
            let res = DaemonIPC.shared.requestDeepPurge()
            switch res {
            case .success:
                message = "Liberación profunda completada vía Kernel Daemon"
            case .failure(let err):
                purgeSuccess = false
                message = "Error en daemon: \(err.localizedDescription). Reintentando modo usuario..."
                executeUserSpacePurge()
                methodUsed = .userSpace
            }
        } else if forcePrivileged {
            // Se solicitó modo administrador bajo demanda vía AppleScript
            methodUsed = .privilegedCommand
            let script = "do shell script \"/usr/sbin/purge\" with administrator privileges"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    message = "Liberación profunda completada con privilegios de administrador"
                } else {
                    purgeSuccess = false
                    message = "Cancelado o error de autenticación. Aplicando modo usuario..."
                    executeUserSpacePurge()
                    methodUsed = .userSpace
                }
            } catch {
                purgeSuccess = false
                message = "Error: \(error.localizedDescription)"
                executeUserSpacePurge()
                methodUsed = .userSpace
            }
        } else {
            // Modo usuario seguro (sin contraseñas): optimiza cachés de usuario y evicción virtual
            methodUsed = .userSpace
            executeUserSpacePurge()
            message = "Cachés de sistema y búferes temporales optimizados (Modo Usuario)"
        }
        
        // Pausa breve para permitir que el kernel actualice sus contadores de VM
        usleep(300_000) // 300ms
        
        let afterSnapshot = SystemMemoryMonitor.shared.getSnapshot()
        let duration = Date().timeIntervalSince(startTime)
        
        // Cálculo de memoria liberada:
        // Se mide por el aumento de memoria disponible (Libre + Inactiva utilizable)
        // o disminución de memoria usada
        let beforeUsed = Int64(beforeSnapshot.usedBytes)
        let afterUsed = Int64(afterSnapshot.usedBytes)
        var freed = beforeUsed - afterUsed
        
        if freed <= 0 {
            // Alternativamente medimos el aumento de memoria libre directa
            let beforeFree = Int64(beforeSnapshot.freeBytes)
            let afterFree = Int64(afterSnapshot.freeBytes)
            freed = max(0, afterFree - beforeFree)
        }
        
        return PurgeResult(
            freedBytes: freed,
            durationSeconds: duration,
            method: methodUsed,
            beforeSnapshot: beforeSnapshot,
            afterSnapshot: afterSnapshot,
            success: purgeSuccess,
            message: message
        )
    }
    
    /// Optimización en espacio de usuario:
    /// 1. Limpieza de caché de directorio y nombres (dscacheutil)
    /// 2. Limpieza de miniaturas y vistas previas (qlmanage)
    /// 3. Evicción de páginas inactivas y purgeable de memoria virtual
    private func executeUserSpacePurge() {
        // 1. Limpiar caché DNS y servicios de directorio
        let ds = Process()
        ds.executableURL = URL(fileURLWithPath: "/usr/bin/dscacheutil")
        ds.arguments = ["-flushcache"]
        try? ds.run()
        ds.waitUntilExit()
        
        // 2. Limpiar caché de QuickLook
        let ql = Process()
        ql.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        ql.arguments = ["-r", "cache"]
        try? ql.run()
        ql.waitUntilExit()
        
        // 3. Evicción progresiva de memoria inactiva
        let snapshot = SystemMemoryMonitor.shared.getSnapshot()
        let inactiveMB = Int(Double(snapshot.inactiveBytes) / (1024.0 * 1024.0))
        
        // Determinamos un tamaño seguro para no provocar swap excesivo:
        // Máximo el 60% de la memoria inactiva o 800 MB
        let targetMB = min(max(100, Int(Double(inactiveMB) * 0.6)), 800)
        let chunkSize = 64 * 1024 * 1024 // 64 MB
        let numChunks = max(1, targetMB / 64)
        
        var allocatedPointers: [UnsafeMutableRawPointer] = []
        let pageSize = 16384 // 16 KB en Apple Silicon
        
        for _ in 0..<numChunks {
            if let ptr = malloc(chunkSize) {
                let bytePtr = ptr.bindMemory(to: UInt8.self, capacity: chunkSize)
                // Tocar una dirección por cada página física para activar la asignación
                for offset in stride(from: 0, to: chunkSize, by: pageSize) {
                    bytePtr[offset] = 0xAA
                }
                allocatedPointers.append(ptr)
            }
        }
        
        // Liberar inmediatamente todas las páginas
        for ptr in allocatedPointers {
            free(ptr)
        }
    }
}
