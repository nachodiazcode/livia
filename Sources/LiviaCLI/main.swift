import Foundation
import LiviaCore

@main
struct LiviaCLI {
    static func main() async {
        let args = CommandLine.arguments.dropFirst()
        let command = args.first ?? "status"
        
        switch command {
        case "status", "-s", "--status":
            showStatus()
            
        case "clean", "purge", "-c", "--clean":
            let isPrivileged = args.contains("--privileged") || args.contains("-p")
            cleanMemory(forcePrivileged: isPrivileged)
            
        case "top", "-t", "--top":
            showTopProcesses()
            
        case "watch", "-w", "--watch":
            watchLoop()
            
        case "daemon":
            handleDaemonCommand(subcommand: args.dropFirst().first ?? "status")
            
        case "help", "-h", "--help":
            showHelp()
            
        default:
            print("Comando desconocido: '\(command)'")
            showHelp()
            exit(1)
        }
    }
    
    // MARK: - Status
    
    static func showStatus() {
        let snapshot = SystemMemoryMonitor.shared.getSnapshot()
        let health = SmartEngine.shared.calculateHealth(snapshot: snapshot)
        let isDaemonActive = DaemonIPC.shared.isDaemonRunning()
        
        print("\n\u{001B}[1;36m🌿 LIVIA - Monitor & Optimizador Inteligente de RAM\u{001B}[0m")
        print("\u{001B}[90m────────────────────────────────────────────────────────\u{001B}[0m")
        
        // Barra gráfica de uso
        let totalBars = 30
        let usedRatio = snapshot.usedPercentage / 100.0
        let filledBars = Int(usedRatio * Double(totalBars))
        let emptyBars = max(0, totalBars - filledBars)
        
        let colorCode: String
        if snapshot.usedPercentage > 85.0 {
            colorCode = "\u{001B}[1;31m" // Rojo
        } else if snapshot.usedPercentage > 65.0 {
            colorCode = "\u{001B}[1;33m" // Amarillo
        } else {
            colorCode = "\u{001B}[1;32m" // Verde
        }
        
        let bar = colorCode + String(repeating: "█", count: filledBars) + "\u{001B}[90m" + String(repeating: "░", count: emptyBars) + "\u{001B}[0m"
        print(String(format: "Uso de RAM:  [%@]  %.1f%%", bar, snapshot.usedPercentage))
        print(String(format: "Salud RAM:   \u{001B}[1m%@ (%d/100)\u{001B}[0m - %@", health.statusTitle, health.score, health.recommendation))
        
        print("\n\u{001B}[1mDesglose de Memoria:\u{001B}[0m")
        print(String(format: "  • Total Física:        %10@", snapshot.formattedTotal))
        print(String(format: "  • Usada (Activa+Wired): %10@", snapshot.formattedUsed))
        print(String(format: "  • Caché Inactiva:      %10@", snapshot.formattedInactive))
        print(String(format: "  • Purgable (Cache VM): %10@", snapshot.formattedPurgeable))
        print(String(format: "  • Libre Inmediata:     %10@", snapshot.formattedFree))
        print(String(format: "  • Total Disponible:    %10@ \u{001B}[90m(Libre + Inactiva)\u{001B}[0m", snapshot.formattedAvailable))
        print(String(format: "  • Swap en Disco:       %10@", snapshot.formattedSwapUsed))
        print(String(format: "  • Presión del Kernel:  %10@", snapshot.pressureLevel.title))
        
        let daemonStr = isDaemonActive ? "\u{001B}[32m● Conectado (Deep Purge Habilitado)\u{001B}[0m" : "\u{001B}[33m○ No instalado (Modo Usuario)\u{001B}[0m"
        print(String(format: "  • Daemon de Kernel:    %@", daemonStr))
        
        print("\n\u{001B}[1mTop 5 Procesos con Mayor Consumo:\u{001B}[0m")
        let procs = SystemMemoryMonitor.shared.getTopProcesses(limit: 5)
        for p in procs {
            print(String(format: "  [%5d] %-28@  %10@", p.pid, p.name, p.formattedRAM))
        }
        
        print("\n\u{001B}[90mEjecuta 'livia clean' para liberar caché ahora o 'livia --help' para opciones.\u{001B}[0m\n")
    }
    
    // MARK: - Clean
    
    static func cleanMemory(forcePrivileged: Bool) {
        print("\n\u{001B}[1;36m🌿 Livia está optimizando la memoria...\u{001B}[0m")
        let before = SystemMemoryMonitor.shared.getSnapshot()
        print(String(format: "  Memoria disponible antes:  %@", before.formattedAvailable))
        print(String(format: "  Caché inactiva acumulada:   %@", before.formattedInactive))
        
        let result = MemoryCleaner.shared.clean(forcePrivileged: forcePrivileged)
        SmartEngine.shared.recordCleanup(result: result)
        
        print("\n\u{001B}[1;32m✓ Optimización completada con éxito\u{001B}[0m")
        print(String(format: "  Método:                   %@", result.method.rawValue))
        print(String(format: "  Memoria disponible ahora:  %@", result.afterSnapshot.formattedAvailable))
        print(String(format: "  RAM liberada en total:    \u{001B}[1;32m%@\u{001B}[0m", result.formattedFreed))
        print(String(format: "  Tiempo de ejecución:      %.2f segundos", result.durationSeconds))
        print("")
    }
    
    // MARK: - Top
    
    static func showTopProcesses() {
        print("\n\u{001B}[1;36m🌿 Top Procesos por Consumo de RAM (libproc directo):\u{001B}[0m")
        print("\u{001B}[90m────────────────────────────────────────────────────────\u{001B}[0m")
        let procs = SystemMemoryMonitor.shared.getTopProcesses(limit: 15)
        print(String(format: "  %-7@ %-35@ %12@", "PID", "NOMBRE DEL PROCESO", "MEMORIA"))
        print("\u{001B}[90m  ──────────────────────────────────────────────────────\u{001B}[0m")
        for p in procs {
            print(String(format: "  [%5d] %-35@ %12@", p.pid, p.name, p.formattedRAM))
        }
        print("")
    }
    
    // MARK: - Watch Loop
    
    static func watchLoop() {
        print("\u{001B}[2J\u{001B}[H") // Limpiar pantalla
        print("\u{001B}[1;36m🌿 Livia Watch Mode - Supervisión Activa con Limpieza Inteligente\u{001B}[0m")
        print("\u{001B}[90mPresiona Ctrl+C para salir.\u{001B}[0m\n")
        
        while true {
            let snapshot = SystemMemoryMonitor.shared.getSnapshot()
            let decision = SmartEngine.shared.evaluateAutoClean(snapshot: snapshot)
            
            showStatus()
            
            switch decision {
            case .shouldClean(let reason):
                print("\u{001B}[1;33m[Auto-Clean] Disparando limpieza: \(reason)\u{001B}[0m")
                cleanMemory(forcePrivileged: false)
            case .skip(let reason):
                print("\u{001B}[90m[Auto-Clean] En espera: \(reason)\u{001B}[0m")
            }
            
            sleep(4)
            print("\u{001B}[2J\u{001B}[H")
        }
    }
    
    // MARK: - Daemon Subcommands
    
    static func handleDaemonCommand(subcommand: String) {
        switch subcommand {
        case "status":
            let isRunning = DaemonIPC.shared.isDaemonRunning()
            if isRunning {
                print("\u{001B}[1;32m● El Daemon de Livia está ACTIVO y respondiendo en \(DaemonIPC.defaultSocketPath)\u{001B}[0m")
            } else {
                print("\u{001B}[1;33m○ El Daemon de Livia no está activo.\u{001B}[0m")
                print("Para instalarlo y habilitar Deep Purge continuo ejecuta:")
                print("  sudo livia daemon --install")
            }
            
        case "--run", "run":
            guard geteuid() == 0 else {
                print("\u{001B}[1;31mError: El modo daemon requiere privilegios de root.\u{001B}[0m")
                print("Ejecuta con 'sudo livia daemon --run'")
                exit(1)
            }
            print("[Livia] Iniciando servicio root en segundo plano...")
            DaemonIPC.shared.runServer()
            
        case "--install", "install":
            installDaemon()
            
        case "--uninstall", "uninstall":
            uninstallDaemon()
            
        default:
            print("Subcomando daemon no reconocido: \(subcommand)")
            print("Opciones: status, install, uninstall, run")
        }
    }
    
    static func installDaemon() {
        guard geteuid() == 0 else {
            print("\u{001B}[1;33mPara instalar el servicio de sistema LaunchDaemon se requieren permisos de administrador.\u{001B}[0m")
            print("Por favor ejecuta: \u{001B}[1msudo livia daemon --install\u{001B}[0m")
            return
        }
        
        let binaryPath = CommandLine.arguments[0]
        let destBinary = "/usr/local/bin/livia"
        
        // Copiar binario a /usr/local/bin si no está allí
        if binaryPath != destBinary {
            try? FileManager.default.createDirectory(atPath: "/usr/local/bin", withIntermediateDirectories: true)
            try? FileManager.default.removeItem(atPath: destBinary)
            do {
                try FileManager.default.copyItem(atPath: binaryPath, toPath: destBinary)
                chmod(destBinary, 0o755)
                print("✓ Binario instalado en \(destBinary)")
            } catch {
                print("Aviso: No se pudo copiar a \(destBinary): \(error.localizedDescription)")
            }
        }
        
        let plistContent = DaemonIPC.generateLaunchDaemonPlist(executablePath: destBinary)
        let plistPath = DaemonIPC.launchDaemonPlistPath
        
        do {
            try plistContent.write(toFile: plistPath, atomically: true, encoding: .utf8)
            chmod(plistPath, 0o644)
            chown(plistPath, 0, 0) // root:wheel
            
            // Cargar con launchctl
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["load", "-w", plistPath]
            try process.run()
            process.waitUntilExit()
            
            print("\u{001B}[1;32m✓ LaunchDaemon instalado y cargado con éxito en \(plistPath)\u{001B}[0m")
            print("El daemon ahora mantendrá limpia tu RAM en segundo plano permanentemente.")
        } catch {
            print("\u{001B}[1;31mError al instalar plist: \(error.localizedDescription)\u{001B}[0m")
        }
    }
    
    static func uninstallDaemon() {
        guard geteuid() == 0 else {
            print("\u{001B}[1;33mSe requieren permisos de administrador para desinstalar el daemon.\u{001B}[0m")
            print("Por favor ejecuta: \u{001B}[1msudo livia daemon --uninstall\u{001B}[0m")
            return
        }
        
        let plistPath = DaemonIPC.launchDaemonPlistPath
        if FileManager.default.fileExists(atPath: plistPath) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["unload", "-w", plistPath]
            try? process.run()
            process.waitUntilExit()
            
            try? FileManager.default.removeItem(atPath: plistPath)
            unlink(DaemonIPC.defaultSocketPath)
            print("\u{001B}[1;32m✓ LaunchDaemon desinstalado con éxito.\u{001B}[0m")
        } else {
            print("El daemon no estaba instalado.")
        }
    }
    
    // MARK: - Help
    
    static func showHelp() {
        print("""
        
        \u{001B}[1;36mLIVIA - Optimizador de Memoria RAM Nativo para macOS\u{001B}[0m
        Especialmente diseñado para mantener Macs de 8GB ágiles, frescos y sin lag.
        
        \u{001B}[1mUSO:\u{001B}[0m
          livia [comando] [opciones]
          
        \u{001B}[1mCOMANDOS DISPONIBLES:\u{001B}[0m
          \u{001B}[1;32mstatus\u{001B}[0m               Muestra el diagnóstico completo de la memoria RAM y salud del sistema (por defecto)
          \u{001B}[1;32mclean\u{001B}[0m, \u{001B}[1;32mpurge\u{001B}[0m         Libera cachés y memoria inactiva inmediatamente
          \u{001B}[1;32mtop\u{001B}[0m                  Muestra los procesos que más memoria están consumiendo
          \u{001B}[1;32mwatch\u{001B}[0m                Modo monitor continuo en tiempo real con limpieza automática inteligente
          \u{001B}[1;32mdaemon status\u{001B}[0m        Comprueba el estado del servicio en segundo plano
          \u{001B}[1;32mdaemon --install\u{001B}[0m     Instala el LaunchDaemon de root para Deep Purge continuo sin contraseña
          \u{001B}[1;32mdaemon --uninstall\u{001B}[0m   Desinstala el LaunchDaemon del sistema
          \u{001B}[1;32mhelp\u{001B}[0m                 Muestra esta ayuda
          
        \u{001B}[1mOPCIONES:\u{001B}[0m
          -p, --privileged     Fuerza la ejecución con permisos de administrador (AppleScript)
          -w, --watch          Activa el modo observación continua
        
        """)
    }
}
