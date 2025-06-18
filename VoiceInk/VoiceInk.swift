import SwiftUI
import SwiftData
import Sparkle
import AppKit
import OSLog

@main
struct VoiceInkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let container: ModelContainer
    
    @StateObject private var whisperState: WhisperState
    @StateObject private var hotkeyManager: HotkeyManager
    @StateObject private var updaterViewModel: UpdaterViewModel
    @StateObject private var menuBarManager: MenuBarManager
    @StateObject private var aiService = AIService()
    @StateObject private var enhancementService: AIEnhancementService
    @StateObject private var activeWindowService = ActiveWindowService.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    // Audio cleanup manager for automatic deletion of old audio files
    private let audioCleanupManager = AudioCleanupManager.shared
    
    init() {
        do {
            let schema = Schema([
                Transcription.self
            ])
            
            // Create app-specific Application Support directory URL
            let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("com.bootweb.VoiceInk", isDirectory: true)
            
            // Create the directory if it doesn't exist
            try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
            
            // Configure SwiftData to use the conventional location
            let storeURL = appSupportURL.appendingPathComponent("default.store")
            let modelConfiguration = ModelConfiguration(schema: schema, url: storeURL)
            
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            
            // Print SwiftData storage location
            if let url = container.mainContext.container.configurations.first?.url {
                print("💾 SwiftData storage location: \(url.path)")
            }
            
        } catch {
            fatalError("Failed to create ModelContainer for Transcription: \(error.localizedDescription)")
        }
        
        // Initialize services with proper sharing of instances
        let aiService = AIService()
        _aiService = StateObject(wrappedValue: aiService)
        
        let updaterViewModel = UpdaterViewModel()
        _updaterViewModel = StateObject(wrappedValue: updaterViewModel)
        
        let enhancementService = AIEnhancementService(aiService: aiService, modelContext: container.mainContext)
        _enhancementService = StateObject(wrappedValue: enhancementService)
        
        let whisperState = WhisperState(modelContext: container.mainContext, enhancementService: enhancementService)
        _whisperState = StateObject(wrappedValue: whisperState)
        
        let hotkeyManager = HotkeyManager(whisperState: whisperState)
        _hotkeyManager = StateObject(wrappedValue: hotkeyManager)
        
        let menuBarManager = MenuBarManager(
            updaterViewModel: updaterViewModel,
            whisperState: whisperState,
            container: container,
            enhancementService: enhancementService,
            aiService: aiService,
            hotkeyManager: hotkeyManager
        )
        _menuBarManager = StateObject(wrappedValue: menuBarManager)
        
        // Configure ActiveWindowService with enhancementService
        let activeWindowService = ActiveWindowService.shared
        activeWindowService.configure(with: enhancementService)
        activeWindowService.configureWhisperState(whisperState)
        _activeWindowService = StateObject(wrappedValue: activeWindowService)
    }
    
    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
                    .environmentObject(whisperState)
                    .environmentObject(hotkeyManager)
                    .environmentObject(updaterViewModel)
                    .environmentObject(menuBarManager)
                    .environmentObject(aiService)
                    .environmentObject(enhancementService)
                    .modelContainer(container)
                    .onAppear {
                        // DISABLED: updaterViewModel.silentlyCheckForUpdates() - Custom fork doesn't need updates
                        
                        // Start the automatic audio cleanup process
                        audioCleanupManager.startAutomaticCleanup(modelContext: container.mainContext)
                    }
                    .background(WindowAccessor { window in
                        WindowManager.shared.configureWindow(window)
                    })
                    .onDisappear {
                        whisperState.unloadModel()
                        
                        // Stop the automatic audio cleanup process
                        audioCleanupManager.stopAutomaticCleanup()
                    }
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .environmentObject(hotkeyManager)
                    .environmentObject(whisperState)
                    .environmentObject(aiService)
                    .environmentObject(enhancementService)
                    .frame(minWidth: 880, minHeight: 780)
                    .cornerRadius(16)
                    .clipped()
                    .background(WindowAccessor { window in
                        // Ensure this is called only once or is idempotent
                        if window.title != "VoiceInk Onboarding" { // Prevent re-configuration
                            WindowManager.shared.configureOnboardingPanel(window)
                        }
                    })
            }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updaterViewModel: updaterViewModel)
            }
        }
        
        MenuBarExtra {
            MenuBarView()
                .environmentObject(whisperState)
                .environmentObject(hotkeyManager)
                .environmentObject(menuBarManager)
                .environmentObject(updaterViewModel)
                .environmentObject(aiService)
                .environmentObject(enhancementService)
        } label: {
            let image: NSImage = {
                let ratio = $0.size.height / $0.size.width
                $0.size.height = 22
                $0.size.width = 22 / ratio
                return $0
            }(NSImage(named: "menuBarIcon")!)

            Image(nsImage: image)
        }
        .menuBarExtraStyle(.menu)
        
        #if DEBUG
        WindowGroup("Debug") {
            Button("Toggle Menu Bar Only") {
                menuBarManager.isMenuBarOnly.toggle()
            }
        }
        #endif
    }
}

class UpdaterViewModel: NSObject, ObservableObject, SPUUpdaterDelegate {
    private var updaterController: SPUStandardUpdaterController!
    
    @Published var canCheckForUpdates = false
    
    override init() {
        // Primero llamamos a super.init() antes de usar self
        super.init()
        
        // Ahora podemos usar self de forma segura
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        
        // DISABLE automatic update checking - app uses custom fork
        updaterController.updater.automaticallyChecksForUpdates = false
        updaterController.updater.updateCheckInterval = 0
        
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
    
    func checkForUpdates() {
        // DISABLED: Manual update checking disabled for custom fork
        // updaterController.checkForUpdates(nil)
        print("INFO: Manual update checking disabled - running custom fork")
    }
    
    func silentlyCheckForUpdates() {
        // DISABLED: Update checking disabled for custom fork
        // updaterController.updater.checkForUpdatesInBackground()
        print("INFO: Update checking disabled - running custom fork")
    }
    
    // MARK: - SPUUpdaterDelegate
    
    func updater(_ updater: SPUUpdater, shouldDownloadUpdate item: SUAppcastItem, reply: @escaping (Bool) -> Void) {
        // Indica a Sparkle que no descargue la actualización.
        // El usuario podría ser notificado de que hay una actualización disponible (dependiendo de la configuración de Sparkle y userDriverDelegate),
        // pero la descarga/instalación se impedirá aquí.
        reply(false)
        
        // Opcionalmente, se podría registrar este evento o informar al usuario de una manera personalizada.
        print("INFO: Se encontró la actualización \(item.versionString), pero la descarga está deshabilitada.")
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject var updaterViewModel: UpdaterViewModel
    
    var body: some View {
        Button("Check for Updates…", action: updaterViewModel.checkForUpdates)
            .disabled(!updaterViewModel.canCheckForUpdates)
    }
}

struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                callback(window)
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}



