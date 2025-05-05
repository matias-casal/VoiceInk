import Foundation
import AppKit
import os

class ActiveWindowService: ObservableObject {
    static let shared = ActiveWindowService()
    @Published var currentApplication: NSRunningApplication?
    private var enhancementService: AIEnhancementService?
    private let browserURLService = BrowserURLService.shared
    
    private let logger = Logger(
        subsystem: "com.bootweb.VoiceInk",
        category: "browser.detection"
    )
    
    private init() {}
    
    func configure(with enhancementService: AIEnhancementService) {
        self.enhancementService = enhancementService
    }
    
    func applyConfigurationForCurrentApp() async {
        // If power mode is disabled, don't do anything
        guard PowerModeManager.shared.isPowerModeEnabled else {
            print("🔌 Power Mode is disabled globally - skipping configuration application")
            return
        }

        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = frontmostApp.bundleIdentifier else { return }
        
        print("🎯 Active Application: \(frontmostApp.localizedName ?? "Unknown") (\(bundleIdentifier))")
        await MainActor.run {
            currentApplication = frontmostApp
        }
        
        // Check if the current app is a supported browser
        if let browserType = BrowserType.allCases.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            logger.debug("🌐 Detected Browser: \(browserType.displayName)")
            
            do {
                // Try to get the current URL
                logger.debug("📝 Attempting to get URL from \(browserType.displayName)")
                let currentURL = try await browserURLService.getCurrentURL(from: browserType)
                logger.debug("📍 Successfully got URL: \(currentURL)")
                
                // Check for URL-specific configuration
                if let (config, urlConfig) = PowerModeManager.shared.getConfigurationForURL(currentURL) {
                    logger.debug("⚙️ Found URL Configuration: \(config.appName) - URL: \(urlConfig.url)")
                    // Apply URL-specific configuration
                    var updatedConfig = config
                    updatedConfig.selectedPrompt = urlConfig.promptId
                    await applyConfiguration(updatedConfig)
                    return
                } else {
                    logger.debug("📝 No URL configuration found for: \(currentURL)")
                }
            } catch {
                logger.error("❌ Failed to get URL from \(browserType.displayName): \(error.localizedDescription)")
            }
        }
        
        // Get configuration for the current app or use default if none exists
        let config = PowerModeManager.shared.getConfiguration(for: bundleIdentifier) ?? PowerModeManager.shared.defaultConfig
        print("⚡️ Using Configuration: \(config.appName) (AI Enhancement: \(config.isAIEnhancementEnabled ? "Enabled" : "Disabled"))")
        await applyConfiguration(config)
    }
    
    private func applyConfiguration(_ config: PowerModeConfig) async {
        guard let enhancementService = enhancementService else { return }
        
        await MainActor.run {
            // Only apply settings if power mode is enabled globally
            if PowerModeManager.shared.isPowerModeEnabled {
                // Apply AI enhancement settings
                enhancementService.isEnhancementEnabled = config.isAIEnhancementEnabled
                
                // Handle prompt selection
                if config.isAIEnhancementEnabled {
                    if let promptId = config.selectedPrompt,
                       let uuid = UUID(uuidString: promptId) {
                        print("🎯 Applied Prompt: \(enhancementService.allPrompts.first(where: { $0.id == uuid })?.title ?? "Unknown")")
                        enhancementService.selectedPromptId = uuid
                    } else {
                        // Auto-select first prompt if none is selected and AI is enabled
                        if let firstPrompt = enhancementService.allPrompts.first {
                            print("🎯 Auto-selected Prompt: \(firstPrompt.title)")
                            enhancementService.selectedPromptId = firstPrompt.id
                        }
                    }
                }
            } else {
                print("🔌 Power Mode is disabled globally - skipping configuration application")
                return
            }
        }
    }
} 
