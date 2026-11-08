import Foundation

public final class SmartEngine: @unchecked Sendable {
    public static let shared = SmartEngine()
    
    // Configuración
    public var isAutoCleanEnabled: Bool = true
    public var cooldownIntervalSeconds: Double = 180.0 // 3 minutos de descanso mínimo
    public var inactiveThresholdMB: Double = 1400.0 // 1.4 GB de caché inactiva
    public var idleThresholdSeconds: Double = 60.0 // 1 minuto de inactividad de usuario
    
    // Telemetría y estadísticas de sesión
    public private(set) var totalFreedBytes: UInt64 = 0
    public private(set) var cleanupsCount: Int = 0
    public private(set) var lastCleanupDate: Date?
    public private(set) var lastResult: PurgeResult?
    
    private let lock = NSLock()
    
    public init() {}
    
    // MARK: - Health Score
    
    public struct HealthReport: Sendable {
        public let score: Int // 0 a 100
        public let statusTitle: String
        public let statusColor: String // "green", "yellow", "orange", "red"
        public let recommendation: String
    }
    
    /// Calcula un puntaje de salud de memoria (0 a 100) adaptado para Mac de 8GB
    public func calculateHealth(snapshot: MemorySnapshot) -> HealthReport {
        var score = 0
        
        // 1. Presión del Kernel (máximo 40 pts)
        switch snapshot.pressureLevel {
        case .normal:
            score += 40
        case .warning:
            score += 15
        case .critical:
            score += 0
        }
        
        // 2. Uso de Swap (máximo 35 pts)
        let swapMB = Double(snapshot.swapUsedBytes) / (1024.0 * 1024.0)
        if swapMB < 50.0 {
            score += 35
        } else if swapMB < 500.0 {
            score += 25
        } else if swapMB < 1500.0 {
            score += 12
        } else {
            score += 0
        }
        
        // 3. Porcentaje de memoria libre / disponible (máximo 25 pts)
        let availPct = snapshot.availablePercentage
        if availPct > 35.0 {
            score += 25
        } else if availPct > 20.0 {
            score += 18
        } else if availPct > 10.0 {
            score += 8
        } else {
            score += 2
        }
        
        let finalScore = max(0, min(100, score))
        let title: String
        let color: String
        let rec: String
        
        if finalScore >= 80 {
            title = "Excelente"
            color = "green"
            rec = "Tu Mac respira con holgura. Rendimiento máximo."
        } else if finalScore >= 60 {
            title = "Bueno"
            color = "yellow"
            rec = "Memoria estable. No se requiere intervención inmediata."
        } else if finalScore >= 40 {
            title = "Apretada"
            color = "orange"
            rec = "Caché acumulándose. Se recomienda liberar memoria."
        } else {
            title = "Crítica"
            color = "red"
            rec = "Alta presión de RAM. Livia liberará memoria para evitar congelamiento."
        }
        
        return HealthReport(score: finalScore, statusTitle: title, statusColor: color, recommendation: rec)
    }
    
    // MARK: - Auto Clean Evaluator
    
    public enum AutoCleanDecision {
        case shouldClean(reason: String)
        case skip(reason: String)
    }
    
    /// Evalúa de manera inteligente si conviene disparar una limpieza automática ahora
    public func evaluateAutoClean(snapshot: MemorySnapshot) -> AutoCleanDecision {
        guard isAutoCleanEnabled else {
            return .skip(reason: "Limpieza automática desactivada por el usuario")
        }
        
        // Comprobar Cooldown para cuidar el disco SSD
        if let last = lastCleanupDate {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < cooldownIntervalSeconds {
                let remaining = Int(cooldownIntervalSeconds - elapsed)
                return .skip(reason: "En período de descanso (cooldown: \(remaining)s restantes)")
            }
        }
        
        // 1. Condición de Emergencia: Presión Crítica
        if snapshot.pressureLevel == .critical {
            return .shouldClean(reason: "Presión crítica de memoria detectada por el kernel")
        }
        
        let inactiveMB = Double(snapshot.inactiveBytes) / (1024.0 * 1024.0)
        let isIdle = SystemMemoryMonitor.shared.isUserIdle(thresholdSeconds: idleThresholdSeconds)
        
        // 2. Condición Ideal: Usuario inactivo y suficiente caché acumulada
        if isIdle && inactiveMB >= inactiveThresholdMB {
            return .shouldClean(reason: "Usuario inactivo y \(Int(inactiveMB)) MB de caché inactiva lista para liberar")
        }
        
        // 3. Condición de advertencia moderada con usuario inactivo
        if isIdle && snapshot.pressureLevel == .warning {
            return .shouldClean(reason: "Presión moderada mientras el equipo está en reposo")
        }
        
        // 4. Si el usuario está trabajando activamente, evitamos interrumpir
        if !isIdle && inactiveMB >= (inactiveThresholdMB * 1.5) {
            return .skip(reason: "Esperando momento de inactividad para no causar micro-interrupciones")
        }
        
        return .skip(reason: "Niveles de memoria dentro de rangos normales")
    }
    
    // MARK: - Record Keeping
    
    public func recordCleanup(result: PurgeResult) {
        lock.lock()
        defer { lock.unlock() }
        
        lastCleanupDate = Date()
        lastResult = result
        cleanupsCount += 1
        if result.freedBytes > 0 {
            totalFreedBytes += UInt64(result.freedBytes)
        }
    }
    
    public var formattedTotalFreed: String {
        MemoryFormatter.formatBytes(totalFreedBytes)
    }
}
