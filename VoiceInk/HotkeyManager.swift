import Foundation
import KeyboardShortcuts
import Carbon
import AppKit
import CoreGraphics

extension KeyboardShortcuts.Name {
    static let toggleMiniRecorder = Self("toggleMiniRecorder")
    static let escapeRecorder = Self("escapeRecorder")
    static let toggleEnhancement = Self("toggleEnhancement")
    // Prompt selection shortcuts
    static let selectPrompt1 = Self("selectPrompt1")
    static let selectPrompt2 = Self("selectPrompt2")
    static let selectPrompt3 = Self("selectPrompt3")
    static let selectPrompt4 = Self("selectPrompt4")
    static let selectPrompt5 = Self("selectPrompt5")
    static let selectPrompt6 = Self("selectPrompt6")
    static let selectPrompt7 = Self("selectPrompt7")
    static let selectPrompt8 = Self("selectPrompt8")
    static let selectPrompt9 = Self("selectPrompt9")
}

@MainActor
class HotkeyManager: ObservableObject {
    @Published var isListening = false
    @Published var isShortcutConfigured = false
    @Published var isPushToTalkEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isPushToTalkEnabled, forKey: "isPushToTalkEnabled")
            resetKeyStates()
            setupKeyMonitor()
        }
    }
    @Published var pushToTalkKey: PushToTalkKey {
        didSet {
            UserDefaults.standard.set(pushToTalkKey.rawValue, forKey: "pushToTalkKey")
            resetKeyStates()
        }
    }
    
    private var whisperState: WhisperState
    private var currentKeyState = false
    private var visibilityTask: Task<Void, Never>?
    
    // Change from single monitor to separate local and global monitors
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var f5KeyDownMonitor: Any? // Monitor for F5 key press
    
    // Key handling properties
    private var keyPressStartTime: Date?
    private let briefPressThreshold = 1.0 // 1 second threshold for brief press
    private var isHandsFreeMode = false   // Track if we're in hands-free recording mode

    // Add cooldown management
    private var lastShortcutTriggerTime: Date?
    private let shortcutCooldownInterval: TimeInterval = 0.5 // 500ms cooldown
    
    private var fnDebounceTask: Task<Void, Never>?
    private var pendingFnKeyState: Bool? = nil
    
    // Para el event tap de la tecla de micrófono/F5
    private var mediaKeyEventTap: CFMachPort?
    private var mediaKeyRunLoopSource: CFRunLoopSource?
    @Published var keyCodeForAlert: Int? = nil // Para mostrar el keyCode en un Alert

    enum PushToTalkKey: String, CaseIterable {
        case rightOption = "rightOption"
        case leftOption = "leftOption"
        case leftControl = "leftControl"
        case rightControl = "rightControl"
        case fn = "fn"
        case rightCommand = "rightCommand"
        case rightShift = "rightShift"
        
        var displayName: String {
            switch self {
            case .rightOption: return "Right Option (⌥)"
            case .leftOption: return "Left Option (⌥)"
            case .leftControl: return "Left Control (⌃)"
            case .rightControl: return "Right Control (⌃)"
            case .fn: return "Fn"
            case .rightCommand: return "Right Command (⌘)"
            case .rightShift: return "Right Shift (⇧)"
            }
        }
        
        var keyCode: CGKeyCode {
            switch self {
            case .rightOption: return 0x3D
            case .leftOption: return 0x3A
            case .leftControl: return 0x3B
            case .rightControl: return 0x3E
            case .fn: return 0x3F
            case .rightCommand: return 0x36
            case .rightShift: return 0x3C
            }
        }
    }
    
    init(whisperState: WhisperState) {
        self.isPushToTalkEnabled = UserDefaults.standard.bool(forKey: "isPushToTalkEnabled")
        self.pushToTalkKey = PushToTalkKey(rawValue: UserDefaults.standard.string(forKey: "pushToTalkKey") ?? "") ?? .rightCommand
        self.whisperState = whisperState
        
        updateShortcutStatus()
        setupEnhancementShortcut()
        setupVisibilityObserver()
        setupF5Monitor()
    }
    
    private func resetKeyStates() {
        currentKeyState = false
        keyPressStartTime = nil
        isHandsFreeMode = false
    }
    
    private func setupVisibilityObserver() {
        visibilityTask = Task { @MainActor in
            for await isVisible in whisperState.$isMiniRecorderVisible.values {
                if isVisible {
                    setupEscapeShortcut()
                    KeyboardShortcuts.setShortcut(.init(.e, modifiers: .command), for: .toggleEnhancement)
                    setupPromptShortcuts()
                } else {
                    removeEscapeShortcut()
                    removeEnhancementShortcut()
                    removePromptShortcuts()
                }
            }
        }
    }
    
    private func setupKeyMonitor() {
        removeKeyMonitor()
        
        guard isPushToTalkEnabled else { return }
        
        // Global monitor for capturing flags when app is in background
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return }
            
            Task { @MainActor in
                await self.handleNSKeyEvent(event)
            }
        }
        
        // Local monitor for capturing flags when app has focus
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return event }
            
            Task { @MainActor in
                await self.handleNSKeyEvent(event)
            }
            
            return event // Return the event to allow normal processing
        }
    }
    
    private func removeKeyMonitor() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }
    
    private func handleNSKeyEvent(_ event: NSEvent) async {
        let keycode = event.keyCode
        let flags = event.modifierFlags
        
        // Check if the target key is pressed based on the modifier flags
        var isKeyPressed = false
        var isTargetKey = false
        
        switch pushToTalkKey {
        case .rightOption, .leftOption:
            isKeyPressed = flags.contains(.option)
            isTargetKey = keycode == pushToTalkKey.keyCode
        case .leftControl, .rightControl:
            isKeyPressed = flags.contains(.control)
            isTargetKey = keycode == pushToTalkKey.keyCode
        case .fn:
            isKeyPressed = flags.contains(.function)
            isTargetKey = keycode == pushToTalkKey.keyCode
            // Debounce only for Fn key
            if isTargetKey {
                pendingFnKeyState = isKeyPressed
                fnDebounceTask?.cancel()
                fnDebounceTask = Task { [pendingState = isKeyPressed] in
                    try? await Task.sleep(nanoseconds: 75_000_000) // 75ms
                    // Only act if the state hasn't changed during debounce
                    if pendingFnKeyState == pendingState {
                        await MainActor.run {
                            self.processPushToTalkKey(isKeyPressed: pendingState)
                        }
                    }
                }
                return
            }
        case .rightCommand:
            isKeyPressed = flags.contains(.command)
            isTargetKey = keycode == pushToTalkKey.keyCode
        case .rightShift:
            isKeyPressed = flags.contains(.shift)
            isTargetKey = keycode == pushToTalkKey.keyCode
        }
        
        guard isTargetKey else { return }
        processPushToTalkKey(isKeyPressed: isKeyPressed)
    }
    
    private func processPushToTalkKey(isKeyPressed: Bool) {
        guard isKeyPressed != currentKeyState else { return }
        currentKeyState = isKeyPressed
        
        // Key is pressed down
        if isKeyPressed {
            keyPressStartTime = Date()
            
            // If we're in hands-free mode, stop recording
            if isHandsFreeMode {
                isHandsFreeMode = false
                Task { @MainActor in await whisperState.handleToggleMiniRecorder() }
                return
            }
            
            // Show recorder if not already visible
            if !whisperState.isMiniRecorderVisible {
                Task { @MainActor in await whisperState.handleToggleMiniRecorder() }
            }
        } 
        // Key is released
        else {
            let now = Date()
            
            // Calculate press duration
            if let startTime = keyPressStartTime {
                let pressDuration = now.timeIntervalSince(startTime)
                
                if pressDuration < briefPressThreshold {
                    // For brief presses, enter hands-free mode
                    isHandsFreeMode = true
                    // Continue recording - do nothing on release
                } else {
                    // For longer presses, stop and transcribe
                    Task { @MainActor in await whisperState.handleToggleMiniRecorder() }
                }
            }
            
            keyPressStartTime = nil
        }
    }
    
    private func setupEscapeShortcut() {
        KeyboardShortcuts.setShortcut(.init(.escape), for: .escapeRecorder)
        KeyboardShortcuts.onKeyDown(for: .escapeRecorder) { [weak self] in
            Task { @MainActor in
                guard let self = self,
                      await self.whisperState.isMiniRecorderVisible else { return }
                
                SoundManager.shared.playEscSound()
                await self.whisperState.dismissMiniRecorder()
            }
        }
    }
    
    private func removeEscapeShortcut() {
        KeyboardShortcuts.setShortcut(nil, for: .escapeRecorder)
    }
    
    private func setupEnhancementShortcut() {
        KeyboardShortcuts.onKeyDown(for: .toggleEnhancement) { [weak self] in
            Task { @MainActor in
                guard let self = self,
                      await self.whisperState.isMiniRecorderVisible,
                      let enhancementService = await self.whisperState.getEnhancementService() else { return }
                enhancementService.isEnhancementEnabled.toggle()
            }
        }
    }
    
    private func setupPromptShortcuts() {
        // Set up Command+1 through Command+9 shortcuts with proper key definitions
        KeyboardShortcuts.setShortcut(.init(.one, modifiers: .command), for: .selectPrompt1)
        KeyboardShortcuts.setShortcut(.init(.two, modifiers: .command), for: .selectPrompt2)
        KeyboardShortcuts.setShortcut(.init(.three, modifiers: .command), for: .selectPrompt3)
        KeyboardShortcuts.setShortcut(.init(.four, modifiers: .command), for: .selectPrompt4)
        KeyboardShortcuts.setShortcut(.init(.five, modifiers: .command), for: .selectPrompt5)
        KeyboardShortcuts.setShortcut(.init(.six, modifiers: .command), for: .selectPrompt6)
        KeyboardShortcuts.setShortcut(.init(.seven, modifiers: .command), for: .selectPrompt7)
        KeyboardShortcuts.setShortcut(.init(.eight, modifiers: .command), for: .selectPrompt8)
        KeyboardShortcuts.setShortcut(.init(.nine, modifiers: .command), for: .selectPrompt9)
        
        // Setup handlers for each shortcut
        setupPromptHandler(for: .selectPrompt1, index: 0)
        setupPromptHandler(for: .selectPrompt2, index: 1)
        setupPromptHandler(for: .selectPrompt3, index: 2)
        setupPromptHandler(for: .selectPrompt4, index: 3)
        setupPromptHandler(for: .selectPrompt5, index: 4)
        setupPromptHandler(for: .selectPrompt6, index: 5)
        setupPromptHandler(for: .selectPrompt7, index: 6)
        setupPromptHandler(for: .selectPrompt8, index: 7)
        setupPromptHandler(for: .selectPrompt9, index: 8)
    }
    
    private func setupPromptHandler(for shortcutName: KeyboardShortcuts.Name, index: Int) {
        KeyboardShortcuts.onKeyDown(for: shortcutName) { [weak self] in
            Task { @MainActor in
                guard let self = self,
                      await self.whisperState.isMiniRecorderVisible,
                      let enhancementService = await self.whisperState.getEnhancementService() else { return }
                
                let prompts = enhancementService.allPrompts
                if index < prompts.count {
                    // Enable AI enhancement if it's not already enabled
                    if !enhancementService.isEnhancementEnabled {
                        enhancementService.isEnhancementEnabled = true
                    }
                    // Switch to the selected prompt
                    enhancementService.setActivePrompt(prompts[index])
                }
            }
        }
    }
    
    private func removePromptShortcuts() {
        // Remove Command+1 through Command+9 shortcuts
        KeyboardShortcuts.setShortcut(nil, for: .selectPrompt1)
        KeyboardShortcuts.setShortcut(nil, for: .selectPrompt2)
        KeyboardShortcuts.setShortcut(nil, for: .selectPrompt3)
        KeyboardShortcuts.setShortcut(nil, for: .selectPrompt4)
        KeyboardShortcuts.setShortcut(nil, for: .selectPrompt5)
        KeyboardShortcuts.setShortcut(nil, for: .selectPrompt6)
        KeyboardShortcuts.setShortcut(nil, for: .selectPrompt7)
        KeyboardShortcuts.setShortcut(nil, for: .selectPrompt8)
        KeyboardShortcuts.setShortcut(nil, for: .selectPrompt9)
    }
    
    private func removeEnhancementShortcut() {
        KeyboardShortcuts.setShortcut(nil, for: .toggleEnhancement)
    }
    
    func updateShortcutStatus() {
        isShortcutConfigured = KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder) != nil
        if isShortcutConfigured {
            setupShortcutHandler()
            setupKeyMonitor()
        } else {
            removeKeyMonitor()
        }
    }
    
    
    private func setupShortcutHandler() {
        KeyboardShortcuts.onKeyUp(for: .toggleMiniRecorder) { [weak self] in
            Task { @MainActor in
                await self?.handleShortcutTriggered()
            }
        }
    }
    
    private func handleShortcutTriggered() async {
        // Check cooldown
        if let lastTrigger = lastShortcutTriggerTime,
           Date().timeIntervalSince(lastTrigger) < shortcutCooldownInterval {
            return // Still in cooldown period
        }
        
        // Update last trigger time
        lastShortcutTriggerTime = Date()
        
        // Handle the shortcut
        await whisperState.handleToggleMiniRecorder()
    }
    
    deinit {
        visibilityTask?.cancel()
        Task { @MainActor in
            removeKeyMonitor()
            removeEscapeShortcut()
            removeEnhancementShortcut()
            removeF5Monitor()
        }
    }
    
    // MARK: - F5 Key Monitor / Microphone Key Event Tap

    // La función callback ahora es global (globalMediaKeyTapCallback)

    private func setupF5Monitor() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)

        if !accessEnabled {
            print("AVISO: Permisos de accesibilidad no concedidos. El tap para la tecla F5/Micrófono podría no funcionar o no suprimir eventos.")
        }

        removeF5Monitor()

        // Escuchamos eventos .keyDown. Las teclas multimedia especiales se envían como eventos keyDown
        // con keyCodes específicos.
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        let unsafeSelf = Unmanaged.passUnretained(self).toOpaque()

        mediaKeyEventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, 
            place: .headInsertEventTap,
            options: .defaultTap, 
            eventsOfInterest: CGEventMask(eventMask),
            callback: globalMediaKeyTapCallback, // Usamos la función global
            userInfo: unsafeSelf
        )

        if let tap = mediaKeyEventTap {
            mediaKeyRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            if let source = mediaKeyRunLoopSource {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
                print("CGEventTap para teclas (F5/Micrófono) configurado para keyDown.")
            } else {
                print("Error: No se pudo crear CFRunLoopSource para el mediaKeyEventTap.")
                mediaKeyEventTap = nil 
            }
        } else {
            print("Error: No se pudo crear el CGEventTap para teclas.")
        }
    }

    private func removeF5Monitor() {
        if let tap = mediaKeyEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            // La documentación sugiere que CFMachPortInvalidate y CFRunLoopRemoveSource
            // deben hacerse, pero a veces pueden causar problemas si no se manejan
            // con cuidado con el ciclo de vida del run loop.
            // Por ahora, solo deshabilitamos. Si hay problemas de recursos, revisaremos esto.
            // CFRunLoopRemoveSource(CFRunLoopGetCurrent(), mediaKeyRunLoopSource, .commonModes)
            // CFMachPortInvalidate(tap) // Esto liberaría el tap.
            mediaKeyRunLoopSource = nil
            mediaKeyEventTap = nil
            print("CGEventTap para teclas multimedia (F5/Micrófono) deshabilitado y removido (referencias).")
        }
    }
    
    // MARK: - Push-to-Talk Key Monitor

}

// --- INICIO DE LA FUNCIÓN GLOBAL ---
// Definimos la función callback a nivel global, FUERA de cualquier clase.
func globalMediaKeyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let manager = refcon?.assumingMemoryBound(to: HotkeyManager.self).pointee else {
        // Si no podemos obtener la instancia del manager debido a un problema con refcon,
        // es más seguro pasar el evento sin modificar.
        return Unmanaged.passUnretained(event)
    }

    if type == .keyDown {
        let cgKeyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        // Intentamos convertir CGEvent a NSEvent para obtener el subtipo si está disponible.
        if let nsEvent = NSEvent(cgEvent: event) {
            // Comprobamos si es el subtipo de las teclas de control auxiliares (multimedia).
            if nsEvent.subtype.rawValue == 8 { // NX_SUBTYPE_AUX_CONTROL_BUTTONS
                print("CGEventTap - AUX_CONTROL_BUTTON KeyDown: cgKeyCode \\(cgKeyCode)")

                // Actualizamos la propiedad en el hilo principal para mostrar el Alert en la UI.
                DispatchQueue.main.async {
                    manager.keyCodeForAlert = Int(cgKeyCode)
                }

                // ----- INICIO DE LA LÓGICA DE ACCIÓN (cuando conozcamos el código) -----
                // UNA VEZ QUE CONOZCAS EL cgKeyCode DE TU TECLA DE MICRÓFONO, REEMPLAZA XX_KEY_CODE_XX
                // let IDENTIFIED_DICTATION_KEY_CODE: Int64 = XX_KEY_CODE_XX 
                // if cgKeyCode == IDENTIFIED_DICTATION_KEY_CODE {
                //     Task { @MainActor in
                //         // Asegúrate de que manager.whisperState esté disponible y sea seguro de usar.
                //         await manager.whisperState.handleToggleMiniRecorder()
                //     }
                //     // Devolvemos nil para SUPRIMIR el evento original.
                //     // ESTO REQUIERE PERMISOS DE ACCESIBILIDAD.
                //     return nil
                // }
                // ----- FIN DE LA LÓGICA DE ACCIÓN -----
            } else {
                // Opcional: manejar o imprimir otros eventos keyDown si es necesario para depuración.
                // print("CGEventTap - Non-AUX KeyDown: cgKeyCode \\(cgKeyCode)")
            }
        } else {
             // Si la conversión a NSEvent falla, al menos tenemos el cgKeyCode.
             // Esto podría ser suficiente para identificar la tecla si el subtipo no es crucial.
             print("CGEventTap - KeyDown (NSEvent conversion failed): cgKeyCode \\(cgKeyCode)")
             DispatchQueue.main.async {
                 manager.keyCodeForAlert = Int(cgKeyCode)
             }
        }
    }
    // Si no es el evento que nos interesa (ej. no es keyDown o no es la tecla específica),
    // pasamos el evento sin modificar para que el sistema lo procese normalmente.
    return Unmanaged.passUnretained(event)
}
// --- FIN DE LA FUNCIÓN GLOBAL ---
