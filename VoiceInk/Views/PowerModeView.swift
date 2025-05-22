import SwiftUI

// Configuration Mode Enum
enum ConfigurationMode {
    case add
    case edit(PowerModeConfig)
    case editDefault(PowerModeConfig)
    
    var isAdding: Bool {
        if case .add = self { return true }
        return false
    }
    
    var isEditingDefault: Bool {
        if case .editDefault = self { return true }
        return false
    }
    
    var title: String {
        switch self {
        case .add: return "Add Configuration"
        case .editDefault: return "Edit Default Configuration"
        case .edit: return "Edit Configuration"
        }
    }
}

// Configuration Type
enum ConfigurationType {
    case application
    case website
}

// Main Configuration Sheet
struct ConfigurationSheet: View {
    let mode: ConfigurationMode
    @Binding var isPresented: Bool
    let powerModeManager: PowerModeManager
    @EnvironmentObject var enhancementService: AIEnhancementService
    
    // State for configuration
    @State private var configurationType: ConfigurationType = .application
    @State private var selectedAppURL: URL?
    @State private var isAIEnhancementEnabled: Bool
    @State private var selectedPromptId: UUID?
    @State private var installedApps: [(url: URL, name: String, bundleId: String, icon: NSImage)] = []
    @State private var searchText = ""
    
    // Website configuration state
    @State private var websiteURL: String = ""
    @State private var websiteName: String = ""
    
    private var filteredApps: [(url: URL, name: String, bundleId: String, icon: NSImage)] {
        if searchText.isEmpty {
            return installedApps
        }
        return installedApps.filter { app in
            app.name.localizedCaseInsensitiveContains(searchText) ||
            app.bundleId.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    init(mode: ConfigurationMode, isPresented: Binding<Bool>, powerModeManager: PowerModeManager) {
        self.mode = mode
        self._isPresented = isPresented
        self.powerModeManager = powerModeManager
        
        switch mode {
        case .add:
            _isAIEnhancementEnabled = State(initialValue: true)
            _selectedPromptId = State(initialValue: nil)
        case .edit(let config), .editDefault(let config):
            _isAIEnhancementEnabled = State(initialValue: config.isAIEnhancementEnabled)
            _selectedPromptId = State(initialValue: config.selectedPrompt.flatMap { UUID(uuidString: $0) })
            if case .edit(let config) = mode {
                // Initialize website configuration if it exists
                if let urlConfig = config.urlConfigs?.first {
                    _configurationType = State(initialValue: .website)
                    _websiteURL = State(initialValue: urlConfig.url)
                    _websiteName = State(initialValue: config.appName)
                } else {
                    _configurationType = State(initialValue: .application)
                    _selectedAppURL = State(initialValue: NSWorkspace.shared.urlForApplication(withBundleIdentifier: config.bundleIdentifier))
                }
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(mode.title)
                    .font(.headline)
                Spacer()
            }
            .padding()
            
            Divider()
            
            if mode.isAdding {
                // Configuration Type Selector
                Picker("Configuration Type", selection: $configurationType) {
                    Text("Application").tag(ConfigurationType.application)
                    Text("Website").tag(ConfigurationType.website)
                }
                
                .padding()
                
                if configurationType == .application {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search applications...", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(8)
                    .background(Color(.windowBackgroundColor).opacity(0.4))
                    .cornerRadius(8)
                    .padding()
                    
                    // App Grid
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 16)], spacing: 16) {
                            ForEach(filteredApps.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }), id: \.bundleId) { app in
                                AppGridItem(
                                    app: app,
                                    isSelected: app.url == selectedAppURL,
                                    action: { selectedAppURL = app.url }
                                )
                            }
                        }
                        .padding()
                    }
                } else {
                    // Website Configuration
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Website Name")
                                .font(.headline)
                            TextField("Enter website name", text: $websiteName)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Website URL")
                                .font(.headline)
                            TextField("Enter website URL (e.g., google.com)", text: $websiteURL)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding()
                }
            }
            
            // Configuration Form
            if let config = getConfigForForm() {
                if let appURL = !mode.isEditingDefault ? NSWorkspace.shared.urlForApplication(withBundleIdentifier: config.bundleIdentifier) : nil {
                    AppConfigurationFormView(
                        appName: config.appName,
                        appIcon: NSWorkspace.shared.icon(forFile: appURL.path),
                        isDefaultConfig: mode.isEditingDefault,
                        isAIEnhancementEnabled: $isAIEnhancementEnabled,
                        selectedPromptId: $selectedPromptId
                    )
                } else {
                    AppConfigurationFormView(
                        appName: nil,
                        appIcon: nil,
                        isDefaultConfig: mode.isEditingDefault,
                        isAIEnhancementEnabled: $isAIEnhancementEnabled,
                        selectedPromptId: $selectedPromptId
                    )
                }
            }
            
            Divider()
            
            // Bottom buttons
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Spacer()
                
                Button(mode.isAdding ? "Add" : "Save") {
                    saveConfiguration()
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(mode.isAdding && !canSave)
            }
            .padding()
        }
        .frame(width: 600)
        .frame(maxHeight: mode.isAdding ? 700 : 600)
        .onAppear {
            print("🔍 ConfigurationSheet appeared - Mode: \(mode)")
            if mode.isAdding {
                print("🔍 Loading installed apps...")
                loadInstalledApps()
            }
        }
    }
    
    private var canSave: Bool {
        if configurationType == .application {
            return selectedAppURL != nil
        } else {
            return !websiteURL.isEmpty && !websiteName.isEmpty
        }
    }
    
    private func getConfigForForm() -> PowerModeConfig? {
        switch mode {
        case .add:
            if configurationType == .application {
                guard let url = selectedAppURL,
                      let bundle = Bundle(url: url),
                      let bundleId = bundle.bundleIdentifier else { return nil }
                
                let appName = bundle.infoDictionary?["CFBundleName"] as? String ??
                             bundle.infoDictionary?["CFBundleDisplayName"] as? String ??
                             "Unknown App"
                
                return PowerModeConfig(
                    bundleIdentifier: bundleId,
                    appName: appName,
                    isAIEnhancementEnabled: isAIEnhancementEnabled,
                    selectedPrompt: selectedPromptId?.uuidString
                )
            } else {
                // Create a special PowerModeConfig for websites
                let urlConfig = URLConfig(url: websiteURL, promptId: selectedPromptId?.uuidString)
                return PowerModeConfig(
                    bundleIdentifier: "website.\(UUID().uuidString)",
                    appName: websiteName,
                    isAIEnhancementEnabled: isAIEnhancementEnabled,
                    selectedPrompt: selectedPromptId?.uuidString,
                    urlConfigs: [urlConfig]
                )
            }
        case .edit(let config), .editDefault(let config):
            return config
        }
    }
    
    private func loadInstalledApps() {
        // Get both user-installed and system applications
        let userAppURLs = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask)
        let systemAppURLs = FileManager.default.urls(for: .applicationDirectory, in: .systemDomainMask)
        let allAppURLs = userAppURLs + systemAppURLs
        
        let apps = allAppURLs.flatMap { baseURL -> [URL] in
            let enumerator = FileManager.default.enumerator(
                at: baseURL,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            
            return enumerator?.compactMap { item -> URL? in
                guard let url = item as? URL,
                      url.pathExtension == "app" else { return nil }
                return url
            } ?? []
        }
        
        installedApps = apps.compactMap { url in
            guard let bundle = Bundle(url: url),
                  let bundleId = bundle.bundleIdentifier,
                  let name = (bundle.infoDictionary?["CFBundleName"] as? String) ??
                            (bundle.infoDictionary?["CFBundleDisplayName"] as? String) else {
                return nil
            }
            
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            return (url: url, name: name, bundleId: bundleId, icon: icon)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    private func saveConfiguration() {
        if isAIEnhancementEnabled && selectedPromptId == nil {
            selectedPromptId = enhancementService.allPrompts.first?.id
        }
        
        switch mode {
        case .add:
            if let config = getConfigForForm() {
                powerModeManager.addConfiguration(config)
            }
        case .edit(let config), .editDefault(let config):
            var updatedConfig = config
            updatedConfig.isAIEnhancementEnabled = isAIEnhancementEnabled
            updatedConfig.selectedPrompt = selectedPromptId?.uuidString
            
            // Update URL configurations if this is a website config
            if configurationType == .website {
                let urlConfig = URLConfig(url: cleanURL(websiteURL), promptId: selectedPromptId?.uuidString)
                updatedConfig.urlConfigs = [urlConfig]
                updatedConfig.appName = websiteName
            }
            
            powerModeManager.updateConfiguration(updatedConfig)
        }
        
        isPresented = false
    }
    
    private func cleanURL(_ url: String) -> String {
        var cleanedURL = url.lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
        
        // Remove trailing slash if present
        if cleanedURL.last == "/" {
            cleanedURL.removeLast()
        }
        
        return cleanedURL
    }
}

// Main View
struct PowerModeView: View {
    @StateObject private var powerModeManager = PowerModeManager.shared
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @State private var showingConfigSheet = false {
        didSet {
            print("🔍 showingConfigSheet changed to: \(showingConfigSheet)")
        }
    }
    @State private var configurationMode: ConfigurationMode? {
        didSet {
            print("🔍 configurationMode changed to: \(String(describing: configurationMode))")
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Power Mode Toggle Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Enable Power Mode")
                            .font(.headline)
                        
                        InfoTip(
                            title: "Power Mode",
                            message: "Create app-specific or URL-specific configurations that automatically apply when using those apps or websites.",
                            learnMoreURL: "https://www.youtube.com/watch?v=cEepexxgf6Y&t=10s"
                        )
                        
                        Spacer()
                        Toggle("", isOn: $powerModeManager.isPowerModeEnabled)
                            .toggleStyle(SwitchToggleStyle(tint: .blue))
                            .labelsHidden()
                            .scaleEffect(1.2)
                            .onChange(of: powerModeManager.isPowerModeEnabled) { oldValue, newValue in
                                powerModeManager.savePowerModeEnabled()
                            }
                    }
                }
                .padding(.horizontal)
                
                if powerModeManager.isPowerModeEnabled {
                    // Default Configuration Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Default Configuration")
                            .font(.headline)
                        
                        ConfiguredAppRow(
                            config: powerModeManager.defaultConfig,
                            isEditing: configurationMode?.isEditingDefault ?? false,
                            action: { 
                                configurationMode = .editDefault(powerModeManager.defaultConfig)
                                showingConfigSheet = true
                            }
                        )
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.windowBackgroundColor).opacity(0.4)))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor.opacity(0.2), lineWidth: 1))
                    }
                    .padding(.horizontal)
                    
                    // Apps Section
                    VStack(spacing: 16) {
                        if powerModeManager.configurations.isEmpty {
                            PowerModeEmptyStateView(
                                showAddModal: $showingConfigSheet,
                                configMode: $configurationMode
                            )
                        } else {
                            Text("Power Mode Configurations")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                            
                            ConfiguredAppsGrid(powerModeManager: powerModeManager)
                            
                            Button(action: { 
                                print("🔍 Add button clicked - Setting config mode and showing sheet")
                                configurationMode = .add
                                print("🔍 Configuration mode set to: \(String(describing: configurationMode))")
                                showingConfigSheet = true
                                print("🔍 showingConfigSheet set to: \(showingConfigSheet)")
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Add New Mode")
                                        .font(.system(size: 13, weight: .medium))
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                            .tint(Color(NSColor.controlAccentColor))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .help("Add a new mode")
                            .padding(.top, 12)
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .sheet(isPresented: $showingConfigSheet, onDismiss: { 
            print("🔍 Sheet dismissed - Clearing configuration mode")
            configurationMode = nil 
        }) {
            Group {
                if let mode = configurationMode {
                    ConfigurationSheet(
                        mode: mode,
                        isPresented: $showingConfigSheet,
                        powerModeManager: powerModeManager
                    )
                    .environmentObject(enhancementService)
                    .onAppear {
                        print("🔍 Creating ConfigurationSheet with mode: \(mode)")
                    }
                }
            }
        }
    }
}
