import SwiftUI
import AppKit

class WindowManager {
    static let shared = WindowManager()
    
    private init() {}
    
    func configureWindow(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.title = "VoiceInk"
        
        // Add additional window configuration for better state management
        window.collectionBehavior = [.fullScreenPrimary]
        
        // Ensure proper window level and ordering
        window.level = .normal
        window.orderFrontRegardless()
    }
    
    func createMainWindow(contentView: NSView) -> NSWindow {
        // Use a standard size that fits well on most displays
        let defaultSize = NSSize(width: 1200, height: 800)
        
        // Get the main screen frame to help with centering
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        
        // Create window with centered position
        let xPosition = (screenFrame.width - defaultSize.width) / 2 + screenFrame.minX
        let yPosition = (screenFrame.height - defaultSize.height) / 2 + screenFrame.minY
        
        let window = NSWindow(
            contentRect: NSRect(x: xPosition, y: yPosition, width: defaultSize.width, height: defaultSize.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        configureWindow(window)
        window.contentView = contentView
        
        // Set up window delegate to handle window state changes
        let delegate = WindowStateDelegate()
        window.delegate = delegate
        
        return window
    }
}

// Add window delegate to handle window state changes
class WindowStateDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        // Ensure window is properly hidden when closed
        window.orderOut(nil)
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        // Ensure window is properly activated
        guard let _ = notification.object as? NSWindow else { return }
        NSApp.activate(ignoringOtherApps: true)
    }
} 
