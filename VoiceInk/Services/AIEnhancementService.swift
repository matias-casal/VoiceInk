import Foundation
import os
import SwiftData
import AppKit

enum EnhancementMode {
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
            
            currentCaptureTask?.cancel()
            
            if isEnhancementEnabled && useScreenCaptureContext {
                currentCaptureTask = Task {
                    await captureScreenContext()
                }
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
    
    @Published var assistantTriggerWord: String {
        didSet {
            UserDefaults.standard.set(assistantTriggerWord, forKey: "assistantTriggerWord")
        }
    }
    
    @Published var customPrompts: [CustomPrompt] {
        didSet {
            if let encoded = try? JSONEncoder().encode(customPrompts.filter { !$0.isPredefined }) {
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
        PredefinedPrompts.createDefaultPrompts() + customPrompts.filter { !$0.isPredefined }
    }
    
    private let aiService: AIService
    private let screenCaptureService: ScreenCaptureService
    private var currentCaptureTask: Task<Void, Never>?
    private let maxRetries = 3
    private let baseTimeout: TimeInterval = 4
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
        self.assistantTriggerWord = UserDefaults.standard.string(forKey: "assistantTriggerWord") ?? "hey"
        
        if let savedPromptsData = UserDefaults.standard.data(forKey: "customPrompts"),
           let decodedPrompts = try? JSONDecoder().decode([CustomPrompt].self, from: savedPromptsData) {
            self.customPrompts = decodedPrompts
        } else {
            self.customPrompts = []
        }
        
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
    
    private func determineMode(text: String) -> EnhancementMode {
        text.lowercased().hasPrefix(assistantTriggerWord.lowercased()) ? .aiAssistant : .transcriptionEnhancement
    }
    
    private func getSystemMessage(for mode: EnhancementMode) -> String {
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
        
        switch mode {
        case .transcriptionEnhancement:
            if let activePrompt = activePrompt,
               activePrompt.id == PredefinedPrompts.assistantPromptId {
                return AIPrompts.assistantMode + contextSection
            }
            
            var systemMessage = String(format: AIPrompts.customPromptTemplate, activePrompt!.promptText)
            systemMessage += contextSection
            return systemMessage

        case .aiAssistant:
            return AIPrompts.assistantMode + contextSection
        }
    }
    
    private func makeRequest(text: String, retryCount: Int = 0) async throws -> String {
        guard isConfigured else {
            logger.error("AI Enhancement: API not configured")
            throw EnhancementError.notConfigured
        }
        
        guard !text.isEmpty else {
            logger.error("AI Enhancement: Empty text received")
            throw EnhancementError.emptyText
        }
        
        let formattedText = "\n<TRANSCRIPT>\n\(text)\n</TRANSCRIPT>"
        let mode = determineMode(text: text)
        let systemMessage = getSystemMessage(for: mode)
        
        logger.notice("🛰️ Sending to AI provider: \(self.aiService.selectedProvider.rawValue)\nSystem Message: \(systemMessage)\nUser Message: \(formattedText)")
        
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
                    throw EnhancementError.serverError
                default:
                    throw EnhancementError.apiError
                }
            } catch let error as EnhancementError {
                throw error
            } catch {
                if retryCount < maxRetries {
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retryCount)) * 1_000_000_000))
                    return try await makeRequest(text: text, retryCount: retryCount + 1)
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
                    throw EnhancementError.serverError
                default:
                    throw EnhancementError.apiError
                }
            } catch let error as EnhancementError {
                throw error
            } catch {
                if retryCount < maxRetries {
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retryCount)) * 1_000_000_000))
                    return try await makeRequest(text: text, retryCount: retryCount + 1)
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
                    throw EnhancementError.serverError
                default:
                    throw EnhancementError.apiError
                }
                
            } catch let error as EnhancementError {
                throw error
            } catch {
                if retryCount < maxRetries {
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retryCount)) * 1_000_000_000))
                    return try await makeRequest(text: text, retryCount: retryCount + 1)
                }
                throw EnhancementError.networkError
            }
        }
    }
    
    func enhance(_ text: String) async throws -> String {
        logger.notice("🚀 Starting AI enhancement for text (\(text.count) characters)")
        var retryCount = 0
        while retryCount < maxRetries {
            do {
                let result = try await makeRequest(text: text, retryCount: retryCount)
                logger.notice("✅ AI enhancement completed successfully (\(result.count) characters)")
                return result
            } catch EnhancementError.rateLimitExceeded where retryCount < maxRetries - 1 {
                logger.notice("⚠️ Rate limit exceeded, retrying AI enhancement (attempt \(retryCount + 1) of \(self.maxRetries))")
                retryCount += 1
                try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retryCount)) * 1_000_000_000))
                continue
            } catch {
                logger.notice("❌ AI enhancement failed: \(error.localizedDescription)")
                throw error
            }
        }
        logger.notice("❌ AI enhancement failed: maximum retries exceeded")
        throw EnhancementError.maxRetriesExceeded
    }
    
    func captureScreenContext() async {
        guard useScreenCaptureContext else { return }
        
        if let capturedText = await screenCaptureService.captureAndExtractText() {
            await MainActor.run {
                self.objectWillChange.send()
            }
        }
    }
    
    func addPrompt(title: String, promptText: String, icon: PromptIcon = .documentFill, description: String? = nil) {
        let newPrompt = CustomPrompt(title: title, promptText: promptText, icon: icon, description: description, isPredefined: false)
        customPrompts.append(newPrompt)
        if customPrompts.count == 1 {
            selectedPromptId = newPrompt.id
        }
    }
    
    func updatePrompt(_ prompt: CustomPrompt) {
        if prompt.isPredefined { return }
        
        if let index = customPrompts.firstIndex(where: { $0.id == prompt.id }) {
            customPrompts[index] = prompt
        }
    }
    
    func deletePrompt(_ prompt: CustomPrompt) {
        if prompt.isPredefined { return }
        
        customPrompts.removeAll { $0.id == prompt.id }
        if selectedPromptId == prompt.id {
            selectedPromptId = allPrompts.first?.id
        }
    }
    
    func setActivePrompt(_ prompt: CustomPrompt) {
        selectedPromptId = prompt.id
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


