import SwiftUI
import AppKit

class NotificationManager {
    static let shared = NotificationManager()

    private var notificationWindow: NSPanel?
    private var dismissTimer: Timer?

    private init() {}

    @MainActor
    func showNotification(
        title: String,
        message: String,
        type: AppNotificationView.NotificationType,
        duration: TimeInterval = 8.0,
        onTap: (() -> Void)? = nil
    ) {
        dismissTimer?.invalidate()
        dismissTimer = nil

        if let existingWindow = notificationWindow {
            existingWindow.close()
            notificationWindow = nil
        }
        
        // Play esc sound for error notifications
        if type == .error {
            SoundManager.shared.playEscSound()
        }
        
        let notificationView = AppNotificationView(
            title: title, 
            message: message, 
            type: type,
            duration: duration,
            onClose: { [weak self] in
                Task { @MainActor in
                    self?.dismissNotification()
                }
            },
            onTap: onTap
        )
        let hostingController = NSHostingController(rootView: notificationView)
        let size = hostingController.view.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.contentView = hostingController.view
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level.mainMenu
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        
        positionWindow(panel)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil as Any?)
        
        self.notificationWindow = panel
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        })
        
        // Schedule a new timer to dismiss the new notification.
        dismissTimer = Timer.scheduledTimer(
            withTimeInterval: duration,
            repeats: false
        ) { [weak self] _ in
            self?.dismissNotification()
        }
    }

    @MainActor
    private func positionWindow(_ window: NSWindow) {
        let activeScreen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let screenRect = activeScreen.visibleFrame
        let windowRect = window.frame
        
        let x = screenRect.maxX - windowRect.width - 20
        let y = screenRect.maxY - windowRect.height - 20
        
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    @MainActor
    func dismissNotification() {
        guard let window = notificationWindow else { return }
        
        notificationWindow = nil
        
        dismissTimer?.invalidate()
        dismissTimer = nil
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.close()

        })
    }
} 