import AppKit
import SwiftUI
import LiviaCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var eventMonitor: Any?
    private var timer: Timer?
    
    let viewModel = LiviaViewModel()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ejecutar como accesorio (sin icono en el Dock, solo en la barra de menús)
        NSApp.setActivationPolicy(.accessory)
        
        setupStatusItem()
        setupPopover()
        setupBackgroundMonitoring()
    }
    
    // MARK: - Status Bar Item
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            updateMenuBarButton(button: button)
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
    }
    
    private func updateMenuBarButton(button: NSStatusBarButton) {
        let snapshot = viewModel.snapshot
        let pct = Int(snapshot.usedPercentage)
        
        // Icono nativo de SF Symbols o indicador
        let symbolName: String
        if snapshot.usedPercentage > 85 {
            symbolName = "flame.fill"
        } else if snapshot.usedPercentage > 65 {
            symbolName = "leaf.arrow.triangle.circlepath"
        } else {
            symbolName = "leaf.fill"
        }
        
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Livia")?.withSymbolConfiguration(config) {
            image.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
        }
        
        button.title = " \(pct)%"
        button.toolTip = "Livia - RAM: \(pct)% Usada (\(snapshot.formattedAvailable) disponible)"
    }
    
    // MARK: - Popover Setup
    
    private func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 520)
        popover.behavior = .transient
        popover.animates = true
        
        let contentView = ContentView(viewModel: viewModel)
        popover.contentViewController = NSHostingController(rootView: contentView)
        self.popover = popover
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Actualizar datos al abrir
            viewModel.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    
    // MARK: - Background Monitoring & Auto-Clean
    
    private func setupBackgroundMonitoring() {
        // Monitoreo periódico cada 4 segundos
        timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.viewModel.refresh()
                if let button = self.statusItem?.button {
                    self.updateMenuBarButton(button: button)
                }
                self.viewModel.checkAutoClean()
            }
        }
        
        // Reacción inmediata a eventos de presión de memoria del kernel
        SystemMemoryMonitor.shared.onPressureChange = { [weak self] level in
            Task { @MainActor [weak self] in
                self?.viewModel.handlePressureChange(level)
            }
        }
    }
}
