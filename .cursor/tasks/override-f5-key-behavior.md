# Task: Override F5 Key Behavior for VoiceInk Shortcut

Status: Planning // Ready for Execution Confirmation

## Task Understanding

The user wants to configure the VoiceInk application to use the F5 key as a global keyboard shortcut. When VoiceInk is running, pressing F5 should trigger a specific action within the application (likely related to audio/dictation input) and should suppress the default system behavior associated with the F5 key (e.g., toggling Dictation). The `KeyboardShortcuts` library, already present in the project, is the appropriate tool for this.

## Research Findings

- The project includes the `KeyboardShortcuts` library and uses it extensively for managing application shortcuts.
- `VoiceInk/HotkeyManager.swift` is the central place where shortcuts are defined, set, and handled.
- The primary action for toggling the app's recording/dictation interface appears to be `whisperState.handleToggleMiniRecorder()`, which is currently triggered by the `.toggleMiniRecorder` shortcut.
- The manager uses `KeyboardShortcuts.Name` to define shortcuts, `KeyboardShortcuts.setShortcut()` to assign default keys, and `KeyboardShortcuts.onKeyDown/Up()` to listen for events.
- There's separate logic for Push-to-Talk using modifier keys via `NSEvent` monitors, but standard shortcuts like the one requested use `KeyboardShortcuts`.
- `SettingsView.swift` allows users to customize the `.toggleMiniRecorder` shortcut using `KeyboardShortcuts.Recorder`.
- Apple's documentation confirms F5 can be linked to system Dictation, but `KeyboardShortcuts` should intercept this when the app registers F5 globally. [Cómo usar las teclas de función en la Mac - Soporte técnico de Apple](https://support.apple.com/es-lamr/102439)
- The existing `.toggleMiniRecorder` shortcut might conflict or be redundant if F5 is also used for a similar purpose. We should clarify if F5 should _replace_ the existing configurable shortcut or be an _additional_, fixed shortcut. Assuming the goal is an _additional_, dedicated F5 shortcut for now.

## Reflection and Context Expansion

- **Reasoning (CoT)**: The integration involves modifying `HotkeyManager.swift` to handle F5 specifically.
  1.  Define a new, dedicated `KeyboardShortcuts.Name` (e.g., `f5DictationToggle`) to avoid conflicts with the user-configurable `.toggleMiniRecorder`.
  2.  Assign F5 as the default key for this new name using `KeyboardShortcuts.setShortcut(.init(.f5), for: .f5DictationToggle)` during initialization.
  3.  Add a listener `KeyboardShortcuts.onKeyDown(for: .f5DictationToggle)` that directly calls the core action `whisperState.handleToggleMiniRecorder()`. Using `onKeyDown` provides immediate feedback. This bypasses the specific cooldown logic tied to `handleShortcutTriggered` unless we decide later to integrate it.
  4.  This shortcut will be fixed to F5 and won't be exposed in the Settings UI for user configuration.
  5.  Consider explicitly unsetting the shortcut in `deinit` using `KeyboardShortcuts.setShortcut(nil, for: .f5DictationToggle)`.
- **Context Needed**: Sufficient context gathered from `HotkeyManager.swift`.
- **Chosen Path**: Implement the F5 shortcut as a separate, non-configurable global hotkey within `HotkeyManager`.

## Roadmap

- [x] **Define Shortcut Name**: En `HotkeyManager.swift`, dentro de la extensión `KeyboardShortcuts.Name`, añadir `static let f5DictationToggle = Self("f5DictationToggle")`.
- [x] **Set Default and Listener**: En `HotkeyManager.swift`, dentro de `init` o una nueva función de configuración llamada desde `init` (ej. `setupGlobalShortcuts`), añadir:
  - `KeyboardShortcuts.setShortcut(.init(.f5), for: .f5DictationToggle)`
  - `KeyboardShortcuts.onKeyDown(for: .f5DictationToggle) { [weak self] in Task { @MainActor in await self?.whisperState.handleToggleMiniRecorder() } }`
- [x] **Cleanup**: En `HotkeyManager.swift`, dentro de `deinit`, añadir `KeyboardShortcuts.setShortcut(nil, for: .f5DictationToggle)` para desregistrar el atajo al finalizar.
- [ ] **Testing**: Ejecutar la aplicación y verificar:
  - [ ] Pulsar F5 llama a `whisperState.handleToggleMiniRecorder()` (ej. muestra/oculta el mini grabador).
  - [ ] Pulsar F5 _no_ activa la función de Dictado por defecto de macOS mientras `VoiceInk` se ejecuta.
  - [ ] El atajo F5 funciona globalmente (incluso si `VoiceInk` no es la aplicación activa).
  - [ ] El atajo configurable (`.toggleMiniRecorder`) sigue funcionando como antes.
  - [ ] La funcionalidad Push-to-Talk (si está activada) no se ve afectada.
