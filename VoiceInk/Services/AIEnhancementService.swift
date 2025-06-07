import Foundation
import os
import SwiftData
import AppKit

enum EnhancementPrompt {
    case transcriptionEnhancement
    case aiAssistant
}

class AIEnhancementService: ObservableObject {
    private let logger = Logger(
        subsystem: "com.bootweb.VoiceInk",
        category: "aienhancement"
    )
    
    @Published var isEnhancementEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnhancementEnabled, forKey: "isAIEnhancementEnabled")
            if isEnhancementEnabled && selectedPromptId == nil {
                selectedPromptId = customPrompts.first?.id
            }
        }
    }        
    @Published var useClipboardContext: Bool {
        didSet {
            UserDefaults.standard.set(useClipboardContext, forKey: "useClipboardContext")
        }
    }
    
    @Published var useScreenCaptureContext: Bool {
        didSet {
            UserDefaults.standard.set(useScreenCaptureContext, forKey: "useScreenCaptureContext")
        }
    }
    
    @Published var customPrompts: [CustomPrompt] {
        didSet {
            if let encoded = try? JSONEncoder().encode(customPrompts) {
                UserDefaults.standard.set(encoded, forKey: "customPrompts")
            }
        }
    }
    
    @Published var selectedPromptId: UUID? {
        didSet {
            UserDefaults.standard.set(selectedPromptId?.uuidString, forKey: "selectedPromptId")
        }
    }
    
    var activePrompt: CustomPrompt? {
        allPrompts.first { $0.id == selectedPromptId }
    }
    
    var allPrompts: [CustomPrompt] {
        return customPrompts
    }
    
    private let aiService: AIService
    private let screenCaptureService: ScreenCaptureService
    private let maxRetries = 3
    private let baseTimeout: TimeInterval = 10
    private let rateLimitInterval: TimeInterval = 1.0
    private var lastRequestTime: Date?
    private let modelContext: ModelContext
    
    init(aiService: AIService = AIService(), modelContext: ModelContext) {
        self.aiService = aiService
        self.modelContext = modelContext
        self.screenCaptureService = ScreenCaptureService()
        
        self.isEnhancementEnabled = UserDefaults.standard.bool(forKey: "isAIEnhancementEnabled")
        self.useClipboardContext = UserDefaults.standard.bool(forKey: "useClipboardContext")
        self.useScreenCaptureContext = UserDefaults.standard.bool(forKey: "useScreenCaptureContext")
        
        // Use migration service to load prompts, preserving existing data
        self.customPrompts = PromptMigrationService.migratePromptsIfNeeded()
        
        if let savedPromptId = UserDefaults.standard.string(forKey: "selectedPromptId") {
            self.selectedPromptId = UUID(uuidString: savedPromptId)
        }
        
        if isEnhancementEnabled && (selectedPromptId == nil || !allPrompts.contains(where: { $0.id == selectedPromptId })) {
            self.selectedPromptId = allPrompts.first?.id
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAPIKeyChange),
            name: .aiProviderKeyChanged,
            object: nil
        )
        
        initializePredefinedPrompts()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleAPIKeyChange() {
        DispatchQueue.main.async {
            self.objectWillChange.send()
            if !self.aiService.isAPIKeyValid {
                self.isEnhancementEnabled = false
            }
        }
    }
    
    func getAIService() -> AIService? {
        return aiService
    }
    
    var isConfigured: Bool {
        aiService.isAPIKeyValid
    }
    
    private func waitForRateLimit() async throws {
        if let lastRequest = lastRequestTime {
            let timeSinceLastRequest = Date().timeIntervalSince(lastRequest)
            if timeSinceLastRequest < rateLimitInterval {
                try await Task.sleep(nanoseconds: UInt64((rateLimitInterval - timeSinceLastRequest) * 1_000_000_000))
            }
        }
        lastRequestTime = Date()
    }
    
    private func getSystemMessage(for mode: EnhancementPrompt) -> String {
        let clipboardContext = if useClipboardContext,
                              let clipboardText = NSPasteboard.general.string(forType: .string),
                              !clipboardText.isEmpty {
            "\n\nAvailable Clipboard Context: \(clipboardText)"
        } else {
            ""
        }
        
        let screenCaptureContext = if useScreenCaptureContext,
                                   let capturedText = screenCaptureService.lastCapturedText,
                                   !capturedText.isEmpty {
            "\n\nActive Window Context: \(capturedText)"
        } else {
            ""
        }
        
        let contextSection = if !clipboardContext.isEmpty || !screenCaptureContext.isEmpty {
            "\n\n\(AIPrompts.contextInstructions)\n\n<CONTEXT_INFORMATION>\(clipboardContext)\(screenCaptureContext)\n</CONTEXT_INFORMATION>"
        } else {
            ""
        }
        
        guard let activePrompt = activePrompt else {
            return AIPrompts.assistantMode + contextSection
        }
        
        if activePrompt.id == PredefinedPrompts.assistantPromptId {
            return activePrompt.promptText + contextSection
        }
        
        var systemMessage = String(format: AIPrompts.customPromptTemplate, activePrompt.promptText)
        systemMessage += contextSection
        return systemMessage
    }
    
    private func makeRequest(text: String, mode: EnhancementPrompt, retryCount: Int = 0) async throws -> String {
        guard isConfigured else {
            logger.error("AI Enhancement: API not configured")
            throw EnhancementError.notConfigured
        }
        
        guard !text.isEmpty else {
            logger.error("AI Enhancement: Empty text received")
            throw EnhancementError.emptyText
        }
        
        let formattedText = "\n<TRANSCRIPT>\n\(text)\n</TRANSCRIPT>"
        
        // Log individual contexts if enabled and available
        if useClipboardContext, let clipboardText = NSPasteboard.general.string(forType: .string), !clipboardText.isEmpty {
            logger.notice("Clipboard Context: \(clipboardText, privacy: .public)")
        }
        if useScreenCaptureContext, let capturedText = screenCaptureService.lastCapturedText, !capturedText.isEmpty {
            logger.notice("Screen Capture Context: \(capturedText, privacy: .public)")
        }
        
        let systemMessage = getSystemMessage(for: mode)
        
        logger.notice("🛰️ Sending to AI provider: \(self.aiService.selectedProvider.rawValue, privacy: .public)")
        logger.notice("System Message: \(systemMessage, privacy: .public)")
        logger.notice("User Message: \(formattedText, privacy: .public)")
        
        if aiService.selectedProvider == .ollama {
            do {
                let result = try await aiService.enhanceWithOllama(text: formattedText, systemPrompt: systemMessage)
                return result
            } catch let error as LocalAIError {
                switch error {
                case .serviceUnavailable:
                    throw EnhancementError.notConfigured
                case .modelNotFound:
                    throw EnhancementError.enhancementFailed
                case .serverError:
                    throw EnhancementError.serverError
                default:
                    throw EnhancementError.enhancementFailed
                }
            }
        }
        
        try await waitForRateLimit()
        
        switch aiService.selectedProvider {
        case .gemini:
            let baseEndpoint = "https://generativelanguage.googleapis.com/v1beta/models"
            let model = aiService.currentModel
            let fullURL = "\(baseEndpoint)/\(model):generateContent"
            
            var urlComponents = URLComponents(string: fullURL)!
            urlComponents.queryItems = [URLQueryItem(name: "key", value: aiService.apiKey)]
            
            guard let url = urlComponents.url else {
                throw EnhancementError.invalidResponse
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = baseTimeout * pow(2.0, Double(retryCount))
            
            let requestBody: [String: Any] = [
                "contents": [
                    [
                        "parts": [
                            ["text": systemMessage],
                            ["text": formattedText]
                        ]
                    ]
                ],
                "generationConfig": [
                    "temperature": 0.3,
                ]
            ]
            
            request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw EnhancementError.invalidResponse
                }
                
                switch httpResponse.statusCode {
                case 200:
                    guard let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let candidates = jsonResponse["candidates"] as? [[String: Any]],
                          let firstCandidate = candidates.first,
                          let content = firstCandidate["content"] as? [String: Any],
                          let parts = content["parts"] as? [[String: Any]],
                          let firstPart = parts.first,
                          let enhancedText = firstPart["text"] as? String else {
                        throw EnhancementError.enhancementFailed
                    }
                    
                    return enhancedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                case 401:
                    throw EnhancementError.authenticationFailed
                case 429:
                    throw EnhancementError.rateLimitExceeded
                case 500...599:
                    logger.error("Server error (HTTP \(httpResponse.statusCode)): \(String(data: data, encoding: .utf8) ?? "No response data")")
                    throw EnhancementError.serverError
                default:
                    throw EnhancementError.apiError
                }
            } catch let error as EnhancementError {
                throw error
            } catch {
                if retryCount < maxRetries {
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retryCount)) * 1_000_000_000))
                    return try await makeRequest(text: text, mode: mode, retryCount: retryCount + 1)
                }
                throw EnhancementError.networkError
            }
            
        case .anthropic:
            let requestBody: [String: Any] = [
                "model": aiService.currentModel,
                "max_tokens": 1024,
                "system": systemMessage,
                "messages": [
                    ["role": "user", "content": formattedText]
                ]
            ]
            
            var request = URLRequest(url: URL(string: aiService.selectedProvider.baseURL)!)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue(aiService.apiKey, forHTTPHeaderField: "x-api-key")
            request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.timeoutInterval = baseTimeout * pow(2.0, Double(retryCount))
            request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw EnhancementError.invalidResponse
                }
                
                switch httpResponse.statusCode {
                case 200:
                    guard let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let content = jsonResponse["content"] as? [[String: Any]],
                          let firstContent = content.first,
                          let enhancedText = firstContent["text"] as? String else {
                        throw EnhancementError.enhancementFailed
                    }
                    
                    return enhancedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                case 401:
                    throw EnhancementError.authenticationFailed
                case 429:
                    throw EnhancementError.rateLimitExceeded
                case 500...599:
                    logger.error("Server error (HTTP \(httpResponse.statusCode)): \(String(data: data, encoding: .utf8) ?? "No response data")")
                    throw EnhancementError.serverError
                default:
                    throw EnhancementError.apiError
                }
            } catch let error as EnhancementError {
                throw error
            } catch {
                if retryCount < maxRetries {
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retryCount)) * 1_000_000_000))
                    return try await makeRequest(text: text, mode: mode, retryCount: retryCount + 1)
                }
                throw EnhancementError.networkError
            }
            
        default:
            let url = URL(string: aiService.selectedProvider.baseURL)!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("Bearer \(aiService.apiKey)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = baseTimeout * pow(2.0, Double(retryCount))
            
            let messages: [[String: Any]] = [
                ["role": "system", "content": systemMessage],
                ["role": "user", "content": formattedText]
            ]
            
            let requestBody: [String: Any] = [
                "model": aiService.currentModel,
                "messages": messages,
                "temperature": 0.3,
                "frequency_penalty": 0.0,
                "presence_penalty": 0.0,
                "stream": false
            ]
            
            request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw EnhancementError.invalidResponse
                }
                
                switch httpResponse.statusCode {
                case 200:
                    guard let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let choices = jsonResponse["choices"] as? [[String: Any]],
                          let firstChoice = choices.first,
                          let message = firstChoice["message"] as? [String: Any],
                          let enhancedText = message["content"] as? String else {
                        throw EnhancementError.enhancementFailed
                    }
                    
                    return enhancedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                case 401:
                    throw EnhancementError.authenticationFailed
                case 429:
                    throw EnhancementError.rateLimitExceeded
                case 500...599:
                    logger.error("Server error (HTTP \(httpResponse.statusCode)): \(String(data: data, encoding: .utf8) ?? "No response data")")
                    throw EnhancementError.serverError
                default:
                    throw EnhancementError.apiError
                }
                
            } catch let error as EnhancementError {
                throw error
            } catch {
                if retryCount < maxRetries {
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retryCount)) * 1_000_000_000))
                    return try await makeRequest(text: text, mode: mode, retryCount: retryCount + 1)
                }
                throw EnhancementError.networkError
            }
        }
    }
    
    func enhance(_ text: String, duration: TimeInterval? = nil) async throws -> String {
        logger.notice("🚀 Starting AI enhancement for text (\(text.count) characters)")
        
        // Apply intelligent filter for short audio or low word count
        if shouldSkipEnhancement(text: text, duration: duration) {
            logger.notice("⏩ Skipping AI enhancement due to filter (short audio or few words), returning original transcription")
            return text
        }
        
        let enhancementPrompt: EnhancementPrompt = .transcriptionEnhancement
        
        var retryCount = 0
        while retryCount < maxRetries {
            do {
                let result = try await makeRequest(text: text, mode: enhancementPrompt, retryCount: retryCount)
                logger.notice("✅ AI enhancement completed successfully (\(result.count) characters)")
                return result
            } catch let error as EnhancementError {
                if shouldRetry(error: error, retryCount: retryCount) {
                    let errorType = switch error {
                    case .rateLimitExceeded: "Rate limit exceeded"
                    case .serverError: "Server error occurred"
                    case .networkError: "Network error occurred"
                    default: "Unknown error"
                    }
                    
                    logger.notice("⚠️ \(errorType), retrying AI enhancement (attempt \(retryCount + 1) of \(self.maxRetries))")
                    retryCount += 1
                    let delaySeconds = getRetryDelay(for: retryCount)
                    try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                    continue
                } else {
                    logger.notice("❌ AI enhancement failed: \(error.localizedDescription)")
                    throw error
                }
            } catch {
                logger.notice("❌ AI enhancement failed: \(error.localizedDescription)")
                throw error
            }
        }
        logger.notice("❌ AI enhancement failed: maximum retries exceeded")
        throw EnhancementError.maxRetriesExceeded
    }
    
    private func shouldSkipEnhancement(text: String, duration: TimeInterval?) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Filter 1: Check word count (less than 5 words)
        let words = trimmedText.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        if words.count < 5 {
            logger.notice("📊 Text has only \(words.count) words (< 5), skipping enhancement")
            return true
        }
        
        // Filter 2: Check audio duration (less than 2 seconds)
        if let duration = duration, duration < 2.0 {
            logger.notice("📊 Audio duration is \(String(format: "%.1f", duration))s (< 2.0s), skipping enhancement")
            return true
        }
        
        // Filter 3: Check character count (extremely short text)
        if trimmedText.count < 10 {
            logger.notice("📊 Text has only \(trimmedText.count) characters (< 10), skipping enhancement")
            return true
        }
        
        return false
    }
    
    func captureScreenContext() async {
        guard useScreenCaptureContext else { return }
        
        if let capturedText = await screenCaptureService.captureAndExtractText() {
            await MainActor.run {
                self.objectWillChange.send()
            }
        }
    }
    
    func addPrompt(title: String, promptText: String, icon: PromptIcon = .documentFill, description: String? = nil, triggerWords: [String] = []) {
        let newPrompt = CustomPrompt(title: title, promptText: promptText, icon: icon, description: description, isPredefined: false, triggerWords: triggerWords)
        customPrompts.append(newPrompt)
        if customPrompts.count == 1 {
            selectedPromptId = newPrompt.id
        }
    }
    
    func updatePrompt(_ prompt: CustomPrompt) {
        if let index = customPrompts.firstIndex(where: { $0.id == prompt.id }) {
            customPrompts[index] = prompt
        }
    }
    
    func deletePrompt(_ prompt: CustomPrompt) {
        customPrompts.removeAll { $0.id == prompt.id }
        if selectedPromptId == prompt.id {
            selectedPromptId = allPrompts.first?.id
        }
    }
    
    func setActivePrompt(_ prompt: CustomPrompt) {
        selectedPromptId = prompt.id
    }
    
    private func shouldRetry(error: EnhancementError, retryCount: Int) -> Bool {
        guard retryCount < maxRetries - 1 else { return false }
        
        switch error {
        case .rateLimitExceeded, .serverError, .networkError:
            return true
        default:
            return false
        }
    }
    
    private func getRetryDelay(for retryCount: Int) -> TimeInterval {
        return retryCount == 1 ? 1.0 : 2.0
    }
    
    private func initializePredefinedPrompts() {
        let predefinedTemplates = PredefinedPrompts.createDefaultPrompts()
        
        for template in predefinedTemplates {
            if let existingIndex = customPrompts.firstIndex(where: { $0.id == template.id }) {
                // Update existing predefined prompt: only update prompt text, preserve trigger word
                var updatedPrompt = customPrompts[existingIndex]
                updatedPrompt = CustomPrompt(
                    id: updatedPrompt.id,
                    title: template.title,
                    promptText: template.promptText, // Update from template
                    isActive: updatedPrompt.isActive,
                    icon: template.icon,
                    description: template.description,
                    isPredefined: true,
                    triggerWords: updatedPrompt.triggerWords // Preserve user's trigger words
                )
                customPrompts[existingIndex] = updatedPrompt
            } else {
                // Add new predefined prompt (no default trigger word)
                customPrompts.append(template)
            }
        }
    }
}

enum EnhancementError: Error {
    case notConfigured
    case emptyText
    case invalidResponse
    case enhancementFailed
    case authenticationFailed
    case rateLimitExceeded
    case serverError
    case apiError
    case networkError
    case maxRetriesExceeded
} 


