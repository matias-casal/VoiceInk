import SwiftUI
import AppKit

class WindowManager {
    static let shared = WindowManager()
    
    private init() {}
    
    func detectActiveScreen() -> NSScreen? {
        // Method 1: Try to get screen from active window bounds
        if let activeWindow = getActiveWindowInfo() {
            let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
            
            if let windowDict = windowList.first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == activeWindow.windowID }),
               let boundsDict = windowDict[kCGWindowBounds as String] as? [String: Any],
               let x = boundsDict["X"] as? CGFloat,
               let y = boundsDict["Y"] as? CGFloat,
               let width = boundsDict["Width"] as? CGFloat,
               let height = boundsDict["Height"] as? CGFloat {
                
                let windowCenter = CGPoint(x: x + width/2, y: y + height/2)
                return NSScreen.screens.first { screen in
                    screen.frame.contains(windowCenter)
                }
            }
        }
        
        // Method 2: Get screen from mouse cursor location
        let mouseLocation = NSEvent.mouseLocation
        if let screenWithMouse = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return screenWithMouse
        }
        
        // Method 3: Fallback to main screen
        return NSScreen.main
    }
    
    private func getActiveWindowInfo() -> (title: String, ownerName: String, windowID: CGWindowID)? {
        let windowListInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        
        if let frontWindow = windowListInfo.first(where: { info in
            let layer = info[kCGWindowLayer as String] as? Int32 ?? 0
            let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
            return layer == 0 && ownerName != "VoiceInk" && !ownerName.contains("Dock") && !ownerName.contains("Menu Bar")
        }) {
            let title = frontWindow[kCGWindowName as String] as? String ?? "Unknown"
            let ownerName = frontWindow[kCGWindowOwnerName as String] as? String ?? "Unknown"
            let windowID = frontWindow[kCGWindowNumber as String] as? CGWindowID ?? 0
            
            return (title: title, ownerName: ownerName, windowID: windowID)
        }
        
        return nil
    }
    
    func configureWindow(_ window: NSWindow) {
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.title = "VoiceInk"
        window.collectionBehavior = [.fullScreenPrimary]
        window.level = .normal
        window.isOpaque = true
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 0, height: 0)
        window.orderFrontRegardless()
    }
    
    func configureOnboardingPanel(_ window: NSWindow) {
        window.styleMask = [.borderless, .fullSizeContentView, .resizable]
        window.isMovableByWindowBackground = true
        window.level = .normal
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.title = "VoiceInk Onboarding"
        window.isOpaque = false
        window.minSize = NSSize(width: 900, height: 780)
        window.orderFrontRegardless()
    }
    
    func createMainWindow(contentView: NSView) -> NSWindow {
        let defaultSize = NSSize(width: 940, height: 780)
        let activeScreen = detectActiveScreen()
        let screenFrame = activeScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
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
        
        let delegate = WindowStateDelegate()
        window.delegate = delegate
        
        return window
    }
}

class WindowStateDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        window.orderOut(nil)
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        guard let _ = notification.object as? NSWindow else { return }
        NSApp.activate(ignoringOtherApps: true)
    }
} 
