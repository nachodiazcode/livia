import AppKit
import SwiftUI
import LiviaCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private var timer: Timer?
    
    let viewModel = LiviaViewModel()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ejecutar como aplicación visible regular con acceso a barra de menú
        NSApp.setActivationPolicy(.regular)
        
        setupStatusItem()
        setupWindow()
        setupBackgroundMonitoring()
        
        // Levantar la ventana inmediatamente al abrir en primer plano
        showWindow()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }
    
    // MARK: - Status Bar Item
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            updateMenuBarButton(button: button)
            button.action = #selector(toggleWindow(_:))
            button.target = self
        }
    }
    
    private func updateMenuBarButton(button: NSStatusBarButton) {
        let snapshot = viewModel.snapshot
        let pct = Int(snapshot.usedPercentage)
        
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
    
    // MARK: - Window Setup
    
    private func setupWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 530),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Livia"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.delegate = self
        
        let contentView = ContentView(viewModel: viewModel)
        window.contentView = NSHostingView(rootView: contentView)
        self.window = window
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Al hacer clic en la X roja, ocultar la ventana pero continuar corriendo en segundo plano
        window.orderOut(nil)
        return false
    }
    
    @objc func toggleWindow(_ sender: AnyObject?) {
        if window.isVisible {
            window.orderOut(nil)
        } else {
            showWindow()
        }
    }
    
    func showWindow() {
        viewModel.refresh()
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
