import SwiftUI
import LaunchAtLogin
import SwiftData
import AppKit

class MenuBarManager: ObservableObject {
    @Published var isMenuBarOnly: Bool {
        didSet {
            UserDefaults.standard.set(isMenuBarOnly, forKey: "IsMenuBarOnly")
            updateAppActivationPolicy()
        }
    }
    
    private var updaterViewModel: UpdaterViewModel
    private var whisperState: WhisperState
    private var container: ModelContainer
    private var enhancementService: AIEnhancementService
    private var aiService: AIService
    private var hotkeyManager: HotkeyManager
    private var mainWindow: NSWindow?
    
    init(updaterViewModel: UpdaterViewModel, 
         whisperState: WhisperState, 
         container: ModelContainer,
         enhancementService: AIEnhancementService,
         aiService: AIService,
         hotkeyManager: HotkeyManager) {
        self.isMenuBarOnly = UserDefaults.standard.bool(forKey: "IsMenuBarOnly")
        self.updaterViewModel = updaterViewModel
        self.whisperState = whisperState
        self.container = container
        self.enhancementService = enhancementService
        self.aiService = aiService
        self.hotkeyManager = hotkeyManager
        updateAppActivationPolicy()
    }
    
    func toggleMenuBarOnly() {
        isMenuBarOnly.toggle()
    }
    
    private func detectActiveScreen() -> NSScreen? {
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
    
    private func updateAppActivationPolicy() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if self.isMenuBarOnly && self.mainWindow != nil {
                self.mainWindow?.close()
                self.mainWindow = nil
            }
            
            if self.isMenuBarOnly {
                NSApp.setActivationPolicy(.accessory)
            } else {
                NSApp.setActivationPolicy(.regular)
            }
        }
    }
    
    func openMainWindowAndNavigate(to destination: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if self.isMenuBarOnly {
                NSApp.setActivationPolicy(.accessory)
            } else {
                NSApp.setActivationPolicy(.regular)
            }
            
            NSApp.activate(ignoringOtherApps: true)
            
            if let existingWindow = self.mainWindow, !existingWindow.isVisible {
                self.mainWindow = nil
            }
            
            if self.mainWindow == nil {
                self.mainWindow = self.createMainWindow()
            }
            
            guard let window = self.mainWindow else { return }
            
            window.makeKeyAndOrderFront(nil)
            self.centerWindowOnActiveScreen(window)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(
                    name: .navigateToDestination,
                    object: nil,
                    userInfo: ["destination": destination]
                )
            }
        }
    }
    
    private func centerWindowOnActiveScreen(_ window: NSWindow) {
        guard let activeScreen = detectActiveScreen() else { return }
        
        let screenFrame = activeScreen.visibleFrame
        let windowSize = window.frame.size
        let xPosition = (screenFrame.width - windowSize.width) / 2 + screenFrame.minX
        let yPosition = (screenFrame.height - windowSize.height) / 2 + screenFrame.minY
        
        window.setFrameOrigin(NSPoint(x: xPosition, y: yPosition))
    }
    
    private func createMainWindow() -> NSWindow {
        let contentView = ContentView()
            .environmentObject(whisperState)
            .environmentObject(hotkeyManager)
            .environmentObject(self)
            .environmentObject(updaterViewModel)
            .environmentObject(enhancementService)
            .environmentObject(aiService)
            .environment(\.modelContext, ModelContext(container))
        
        let hostingView = NSHostingView(rootView: contentView)
        let window = WindowManager.shared.createMainWindow(contentView: hostingView)
        
        let delegate = WindowDelegate { [weak self] in
            self?.mainWindow = nil
        }
        window.delegate = delegate
        
        return window
    }
}

// Window delegate to handle window closing
class WindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    
    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init()
    }
    
    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

extension Notification.Name {
    static let navigateToDestination = Notification.Name("navigateToDestination")
}
