import SwiftUI
import LiviaCore

struct ContentView: View {
    @ObservedObject var viewModel: LiviaViewModel
    
    var body: some View {
        VStack(spacing: 14) {
            // MARK: - Header
            headerView
            
            Divider()
            
            // MARK: - Main Memory Overview
            memoryGaugeCard
            
            // MARK: - Primary Action Button
            actionButton
            
            // MARK: - Smart Auto-Clean & Daemon Status
            smartEngineSection
            
            // MARK: - Top RAM Consuming Apps
            topAppsSection
            
            Divider()
            
            // MARK: - Footer
            footerView
        }
        .padding(16)
        .frame(width: 360)
        .background(VisualEffectView().ignoresSafeArea())
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack {
            Image(systemName: "leaf.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.teal)
            
            VStack(alignment: .leading, spacing: 1) {
                Text("Livia")
                    .font(.system(size: 15, weight: .bold))
                Text("Respiro para tu Mac de 8GB")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Health Score Badge
            let health = SmartEngine.shared.calculateHealth(snapshot: viewModel.snapshot)
            HStack(spacing: 5) {
                Circle()
                    .fill(healthColor(health.statusColor))
                    .frame(width: 8, height: 8)
                Text("\(health.score)% \(health.statusTitle)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(12)
        }
    }
    
    private var memoryGaugeCard: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Memoria Disponible")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(viewModel.snapshot.formattedAvailable)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Uso Total")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(String(format: "%.0f%% de %@", viewModel.snapshot.usedPercentage, viewModel.snapshot.formattedTotal))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            
            // Segmented Memory Bar
            GeometryReader { geometry in
                let total = max(1.0, Double(viewModel.snapshot.totalBytes))
                let activeRatio = Double(viewModel.snapshot.activeBytes) / total
                let wiredRatio = Double(viewModel.snapshot.wiredBytes) / total
                let compressedRatio = Double(viewModel.snapshot.compressedBytes) / total
                let inactiveRatio = Double(viewModel.snapshot.inactiveBytes) / total
                let freeRatio = max(0.0, 1.0 - (activeRatio + wiredRatio + compressedRatio + inactiveRatio))
                
                HStack(spacing: 2) {
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: max(2, geometry.size.width * activeRatio))
                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: max(2, geometry.size.width * wiredRatio))
                    Rectangle()
                        .fill(Color.purple)
                        .frame(width: max(2, geometry.size.width * compressedRatio))
                    Rectangle()
                        .fill(Color.yellow.opacity(0.85))
                        .frame(width: max(2, geometry.size.width * inactiveRatio))
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: max(2, geometry.size.width * freeRatio))
                }
                .cornerRadius(4)
            }
            .frame(height: 10)
            
            // Leyenda de colores compacta
            HStack(spacing: 12) {
                legendItem(color: .blue, title: "Activa", value: viewModel.snapshot.formattedActive)
                legendItem(color: .orange, title: "Wired", value: viewModel.snapshot.formattedWired)
                legendItem(color: .yellow, title: "Caché", value: viewModel.snapshot.formattedInactive)
                legendItem(color: .green, title: "Libre", value: viewModel.snapshot.formattedFree)
            }
            .font(.system(size: 9))
        }
        .padding(12)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(10)
    }
    
    private var actionButton: some View {
        VStack(spacing: 4) {
            Button(action: {
                viewModel.cleanNow(forcePrivileged: false)
            }) {
                HStack(spacing: 8) {
                    if viewModel.isCleaning {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 13, weight: .bold))
                    }
                    
                    Text(viewModel.isCleaning ? "Optimizando..." : "Liberar Memoria Ahora")
                        .font(.system(size: 13, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .foregroundColor(.white)
                .background(
                    LinearGradient(
                        colors: viewModel.isCleaning ? [Color.gray, Color.gray.opacity(0.8)] : [Color.teal, Color.blue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isCleaning)
            
            if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.teal)
                    .transition(.opacity)
            }
        }
    }
    
    private var smartEngineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(isOn: $viewModel.isAutoCleanEnabled) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.badge.automatic.fill")
                            .foregroundColor(.teal)
                            .font(.system(size: 12))
                        Text("Auto-Limpieza Inteligente")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .toggleStyle(.switch)
                
                Spacer()
            }
            
            HStack(spacing: 6) {
                if viewModel.isDaemonRunning {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 11))
                    Text("Kernel Deep Purge Activo (0% Overhead)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                } else {
                    Image(systemName: "shield.slash")
                        .foregroundColor(.orange)
                        .font(.system(size: 11))
                    Text("Modo Estándar (Modo Usuario)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button("Habilitar") {
                        viewModel.installDaemon()
                    }
                    .font(.system(size: 10, weight: .bold))
                    .buttonStyle(.link)
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
    }
    
    private var topAppsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Apps con Mayor Consumo")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("Top 5")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 5) {
                ForEach(viewModel.topProcesses) { proc in
                    HStack(spacing: 8) {
                        Image(systemName: "app.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.blue.opacity(0.7))
                        
                        Text(proc.name)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        
                        Spacer()
                        
                        Text(proc.formattedRAM)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
    }
    
    private var footerView: some View {
        HStack {
            if viewModel.totalFreedSession > 0 {
                Text("Liberado hoy: \(MemoryFormatter.formatBytes(viewModel.totalFreedSession))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.teal)
            } else {
                Text("Livia 1.0 • macOS Nativo")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Salir") {
                NSApp.terminate(nil)
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
    }
    
    private func legendItem(color: Color, title: String, value: String) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(title)
                .foregroundColor(.secondary)
            Text(value)
                .fontWeight(.medium)
        }
    }
    
    private func healthColor(_ color: String) -> Color {
        switch color {
        case "green": return .green
        case "yellow": return .yellow
        case "orange": return .orange
        case "red": return .red
        default: return .green
        }
    }
}

// MARK: - Native Vibrancy Visual Effect View
struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .popover
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
