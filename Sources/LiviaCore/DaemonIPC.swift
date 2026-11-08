import Foundation
import Darwin

public final class DaemonIPC: @unchecked Sendable {
    public static let shared = DaemonIPC()
    public static let defaultSocketPath = "/var/run/livia.sock"
    public static let launchDaemonPlistPath = "/Library/LaunchDaemons/com.livia.daemon.plist"
    public static let launchDaemonLabel = "com.livia.daemon"
    
    private let socketPath: String
    
    public init(socketPath: String = DaemonIPC.defaultSocketPath) {
        self.socketPath = socketPath
    }
    
    // MARK: - Client Methods
    
    /// Comprueba si el daemon en segundo plano con privilegios root está activo
    public func isDaemonRunning() -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        
        // Timeout de 1 segundo para no bloquear la interfaz
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            _ = socketPath.withCString { strncpy(raw, $0, 104) }
        }
        
        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connectRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, addrLen)
            }
        }
        
        guard connectRes == 0 else { return false }
        
        let ping = "PING\n"
        _ = ping.withCString { write(fd, $0, strlen($0)) }
        
        var buffer = [CChar](repeating: 0, count: 64)
        let readBytes = read(fd, &buffer, 63)
        if readBytes > 0 {
            let response = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }.trimmingCharacters(in: .whitespacesAndNewlines)
            return response == "PONG"
        }
        
        return false
    }
    
    /// Solicita al daemon de kernel la ejecución de una liberación profunda (sudo purge)
    public func requestDeepPurge() -> Result<Int64, Error> {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            return .failure(NSError(domain: "DaemonIPC", code: 1, userInfo: [NSLocalizedDescriptionKey: "No se pudo crear el socket"]))
        }
        defer { close(fd) }
        
        // Timeout amplio de 20 segundos ya que el kernel purge puede demorar unos segundos
        var timeout = timeval(tv_sec: 20, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            _ = socketPath.withCString { strncpy(raw, $0, 104) }
        }
        
        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connectRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, addrLen)
            }
        }
        
        guard connectRes == 0 else {
            return .failure(NSError(domain: "DaemonIPC", code: 2, userInfo: [NSLocalizedDescriptionKey: "El daemon de Livia no está respondiendo"]))
        }
        
        let cmd = "PURGE\n"
        _ = cmd.withCString { write(fd, $0, strlen($0)) }
        
        var buffer = [CChar](repeating: 0, count: 256)
        let readBytes = read(fd, &buffer, 255)
        guard readBytes > 0 else {
            return .failure(NSError(domain: "DaemonIPC", code: 3, userInfo: [NSLocalizedDescriptionKey: "Respuesta vacía del daemon"]))
        }
        
        let response = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }.trimmingCharacters(in: .whitespacesAndNewlines)
        // Protocolo: "OK <bytesLiberados>" o "ERROR <mensaje>"
        if response.hasPrefix("OK") {
            let parts = response.split(separator: " ")
            if parts.count >= 2, let bytes = Int64(parts[1]) {
                return .success(bytes)
            }
            return .success(0)
        } else {
            return .failure(NSError(domain: "DaemonIPC", code: 4, userInfo: [NSLocalizedDescriptionKey: response]))
        }
    }
    
    // MARK: - Server (Daemon) Methods
    
    /// Ejecuta el servidor daemon (debe correrse con privilegios root)
    public func runServer() {
        unlink(socketPath)
        
        let serverFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFd >= 0 else {
            perror("Error al crear socket")
            exit(1)
        }
        defer {
            close(serverFd)
            unlink(socketPath)
        }
        
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            _ = socketPath.withCString { strncpy(raw, $0, 104) }
        }
        
        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverFd, $0, addrLen)
            }
        }
        
        guard bindRes == 0 else {
            perror("Error en bind del socket")
            exit(1)
        }
        
        // Permitir que cualquier usuario local pueda comunicarse con el socket
        chmod(socketPath, 0o666)
        
        guard listen(serverFd, 10) == 0 else {
            perror("Error en listen")
            exit(1)
        }
        
        print("[Livia Daemon] Servidor activo escuchando en \(socketPath)")
        
        // Loop principal del daemon
        while true {
            var clientAddr = sockaddr_un()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            let clientFd = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(serverFd, $0, &clientAddrLen)
                }
            }
            
            guard clientFd >= 0 else { continue }
            
            var buffer = [CChar](repeating: 0, count: 256)
            let readBytes = read(clientFd, &buffer, 255)
            if readBytes > 0 {
                let cmd = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }.trimmingCharacters(in: .whitespacesAndNewlines)
                
                switch cmd {
                case "PING":
                    let reply = "PONG\n"
                    _ = reply.withCString { write(clientFd, $0, strlen($0)) }
                    
                case "STATUS":
                    let reply = "RUNNING\n"
                    _ = reply.withCString { write(clientFd, $0, strlen($0)) }
                    
                case "PURGE":
                    let before = SystemMemoryMonitor.shared.getSnapshot()
                    // Ejecutar /usr/sbin/purge como root
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/sbin/purge")
                    do {
                        try process.run()
                        process.waitUntilExit()
                        let after = SystemMemoryMonitor.shared.getSnapshot()
                        let freed = Int64(after.availableBytes) - Int64(before.availableBytes)
                        let reply = "OK \(freed)\n"
                        _ = reply.withCString { write(clientFd, $0, strlen($0)) }
                    } catch {
                        let reply = "ERROR \(error.localizedDescription)\n"
                        _ = reply.withCString { write(clientFd, $0, strlen($0)) }
                    }
                    
                default:
                    let reply = "ERROR Comando desconocido\n"
                    _ = reply.withCString { write(clientFd, $0, strlen($0)) }
                }
            }
            
            close(clientFd)
        }
    }
    
    // MARK: - LaunchDaemon Plist Generation
    
    public static func generateLaunchDaemonPlist(executablePath: String = "/usr/local/bin/livia") -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(launchDaemonLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(executablePath)</string>
                <string>daemon</string>
                <string>--run</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardOutPath</key>
            <string>/var/log/livia.log</string>
            <key>StandardErrorPath</key>
            <string>/var/log/livia_error.log</string>
        </dict>
        </plist>
        """
    }
}
