import Foundation

public enum MemoryPressureLevel: Int, Sendable, Codable {
    case normal = 1
    case warning = 2
    case critical = 4
    
    public var title: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Moderada"
        case .critical: return "Crítica"
        }
    }
}

public struct MemorySnapshot: Sendable, Codable {
    public let totalBytes: UInt64
    public let freeBytes: UInt64
    public let activeBytes: UInt64
    public let inactiveBytes: UInt64
    public let wiredBytes: UInt64
    public let compressedBytes: UInt64
    public let purgeableBytes: UInt64
    public let swapTotalBytes: UInt64
    public let swapUsedBytes: UInt64
    public let pressureLevel: MemoryPressureLevel
    public let timestamp: Date
    
    public init(
        totalBytes: UInt64,
        freeBytes: UInt64,
        activeBytes: UInt64,
        inactiveBytes: UInt64,
        wiredBytes: UInt64,
        compressedBytes: UInt64,
        purgeableBytes: UInt64,
        swapTotalBytes: UInt64,
        swapUsedBytes: UInt64,
        pressureLevel: MemoryPressureLevel,
        timestamp: Date = Date()
    ) {
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.activeBytes = activeBytes
        self.inactiveBytes = inactiveBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.purgeableBytes = purgeableBytes
        self.swapTotalBytes = swapTotalBytes
        self.swapUsedBytes = swapUsedBytes
        self.pressureLevel = pressureLevel
        self.timestamp = timestamp
    }
    
    /// Memoria utilizada efectivamente (ocupada por apps, sistema y compresión)
    public var usedBytes: UInt64 {
        // En Darwin VM: Usada = Wired + Active + Compressed
        return min(totalBytes, wiredBytes + activeBytes + compressedBytes)
    }
    
    /// Memoria que se puede considerar disponible (libre inmediata + inactiva + purgeable)
    public var availableBytes: UInt64 {
        return min(totalBytes, freeBytes + inactiveBytes + purgeableBytes)
    }
    
    /// Porcentaje de uso (0.0 a 100.0)
    public var usedPercentage: Double {
        guard totalBytes > 0 else { return 0.0 }
        return (Double(usedBytes) / Double(totalBytes)) * 100.0
    }
    
    /// Porcentaje libre (0.0 a 100.0)
    public var availablePercentage: Double {
        return max(0.0, 100.0 - usedPercentage)
    }
    
    public var formattedTotal: String { MemoryFormatter.formatBytes(totalBytes) }
    public var formattedUsed: String { MemoryFormatter.formatBytes(usedBytes) }
    public var formattedFree: String { MemoryFormatter.formatBytes(freeBytes) }
    public var formattedAvailable: String { MemoryFormatter.formatBytes(availableBytes) }
    public var formattedActive: String { MemoryFormatter.formatBytes(activeBytes) }
    public var formattedInactive: String { MemoryFormatter.formatBytes(inactiveBytes) }
    public var formattedWired: String { MemoryFormatter.formatBytes(wiredBytes) }
    public var formattedCompressed: String { MemoryFormatter.formatBytes(compressedBytes) }
    public var formattedPurgeable: String { MemoryFormatter.formatBytes(purgeableBytes) }
    public var formattedSwapUsed: String { MemoryFormatter.formatBytes(swapUsedBytes) }
}

public struct ProcessInfoItem: Identifiable, Sendable, Codable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let name: String
    public let residentBytes: UInt64
    
    public init(pid: Int32, name: String, residentBytes: UInt64) {
        self.pid = pid
        self.name = name
        self.residentBytes = residentBytes
    }
    
    public var formattedRAM: String {
        MemoryFormatter.formatBytes(residentBytes)
    }
}

public enum PurgeMethod: String, Sendable, Codable {
    case rootDaemon = "Daemon de Kernel (Deep Purge)"
    case privilegedCommand = "Comando Privilegiado"
    case userSpace = "Optimización Modo Usuario"
    case simulated = "Simulación"
}

public struct PurgeResult: Sendable, Codable {
    public let freedBytes: Int64
    public let durationSeconds: Double
    public let method: PurgeMethod
    public let beforeSnapshot: MemorySnapshot
    public let afterSnapshot: MemorySnapshot
    public let timestamp: Date
    public let success: Bool
    public let message: String
    
    public init(
        freedBytes: Int64,
        durationSeconds: Double,
        method: PurgeMethod,
        beforeSnapshot: MemorySnapshot,
        afterSnapshot: MemorySnapshot,
        timestamp: Date = Date(),
        success: Bool = true,
        message: String = ""
    ) {
        self.freedBytes = freedBytes
        self.durationSeconds = durationSeconds
        self.method = method
        self.beforeSnapshot = beforeSnapshot
        self.afterSnapshot = afterSnapshot
        self.timestamp = timestamp
        self.success = success
        self.message = message
    }
    
    public var formattedFreed: String {
        if freedBytes <= 0 {
            return "0 MB (Caché ya optimizada)"
        }
        return MemoryFormatter.formatBytes(UInt64(freedBytes))
    }
}

public enum MemoryFormatter {
    public static func formatBytes(_ bytes: UInt64) -> String {
        let kb = Double(bytes) / 1024.0
        let mb = kb / 1024.0
        let gb = mb / 1024.0
        
        if gb >= 1.0 {
            return String(format: "%.2f GB", gb)
        } else if mb >= 1.0 {
            return String(format: "%.1f MB", mb)
        } else if kb >= 1.0 {
            return String(format: "%.0f KB", kb)
        } else {
            return "\(bytes) B"
        }
    }
}
