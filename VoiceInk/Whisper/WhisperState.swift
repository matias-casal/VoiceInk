import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import AppKit
import KeyboardShortcuts
import os

@MainActor
class WhisperState: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isModelLoaded = false
    @Published var canTranscribe = false
    @Published var isRecording = false
    @Published var loadedLocalModel: WhisperModel?
    @Published var currentTranscriptionModel: (any TranscriptionModel)?
    @Published var isModelLoading = false
    @Published var availableModels: [WhisperModel] = []
    @Published var allAvailableModels: [any TranscriptionModel] = PredefinedModels.models
    @Published var clipboardMessage = ""
    @Published var miniRecorderError: String?
    @Published var isProcessing = false
    @Published var shouldCancelRecording = false
    @Published var isTranscribing = false
    @Published var isAutoCopyEnabled: Bool = UserDefaults.standard.object(forKey: "IsAutoCopyEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isAutoCopyEnabled, forKey: "IsAutoCopyEnabled")
        }
    }
    @Published var recorderType: String = UserDefaults.standard.string(forKey: "RecorderType") ?? "mini" {
        didSet {
            UserDefaults.standard.set(recorderType, forKey: "RecorderType")
        }
    }
    
    @Published var isVisualizerActive = false
    

    
    @Published var isMiniRecorderVisible = false {
        didSet {
            if isMiniRecorderVisible {
                showRecorderPanel()
            } else {
                hideRecorderPanel()
            }
        }
    }
    
    var whisperContext: WhisperContext?
    let recorder = Recorder()
    var recordedFile: URL? = nil
    let whisperPrompt = WhisperPrompt()
    
    // Prompt detection service for trigger word handling
    private let promptDetectionService = PromptDetectionService()
    
    let modelContext: ModelContext
    
    // Transcription Services
    private var localTranscriptionService: LocalTranscriptionService
    private let cloudTranscriptionService = CloudTranscriptionService()
    
    private var modelUrl: URL? {
        let possibleURLs = [
            Bundle.main.url(forResource: "ggml-base.en", withExtension: "bin", subdirectory: "Models"),
            Bundle.main.url(forResource: "ggml-base.en", withExtension: "bin"),
            Bundle.main.bundleURL.appendingPathComponent("Models/ggml-base.en.bin")
        ]
        
        for url in possibleURLs {
            if let url = url, FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }
    
    private enum LoadError: Error {
        case couldNotLocateModel
    }
    
    let modelsDirectory: URL
    let recordingsDirectory: URL
    let enhancementService: AIEnhancementService?
    // Removed license validation - app is always Pro
    let logger = Logger(subsystem: "com.bootweb.VoiceInk", category: "WhisperState")
    var notchWindowManager: NotchWindowManager?
    var miniWindowManager: MiniWindowManager?
    
    // For model progress tracking
    @Published var downloadProgress: [String: Double] = [:]
    
    init(modelContext: ModelContext, enhancementService: AIEnhancementService? = nil) {
        self.modelContext = modelContext
        let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.bootweb.VoiceInk")
        
        self.modelsDirectory = appSupportDirectory.appendingPathComponent("WhisperModels")
        self.recordingsDirectory = appSupportDirectory.appendingPathComponent("Recordings")
        
        // Initialize services without whisperState reference first
        self.localTranscriptionService = LocalTranscriptionService(modelsDirectory: self.modelsDirectory)
        
        self.enhancementService = enhancementService
        // No license validation needed - app is always Pro
        
        super.init()
        
        // Set the whisperState reference after super.init()
        self.localTranscriptionService = LocalTranscriptionService(modelsDirectory: self.modelsDirectory, whisperState: self)
        
        setupNotifications()
        createModelsDirectoryIfNeeded()
        createRecordingsDirectoryIfNeeded()
        loadAvailableModels()
        loadCurrentTranscriptionModel()
        refreshAllAvailableModels()
    }
    
    private func createRecordingsDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            logger.error("Error creating recordings directory: \(error.localizedDescription)")
        }
    }
    
    func toggleRecord() async {
        if isRecording {
            logger.notice("🛑 Stopping recording")
            await MainActor.run {
                isRecording = false
                isVisualizerActive = false
            }
            await recorder.stopRecording()
            if let recordedFile {
                if !shouldCancelRecording {
                    await transcribeAudio(recordedFile)
                } else {
                    logger.info("🛑 Transcription and paste aborted in toggleRecord due to shouldCancelRecording flag.")
                    await MainActor.run {
                        isProcessing = false
                        isTranscribing = false
                        canTranscribe = true
                    }
                    await cleanupModelResources()
                }
            } else {
                logger.error("❌ No recorded file found after stopping recording")
            }
        } else {
            guard currentTranscriptionModel != nil else {
                await MainActor.run {
                    NotificationManager.shared.showNotification(
                        title: "No AI Model Selected",
                        message: "Please select a default AI model before recording.",
                        type: .error
                    )
                }
                return
            }
            shouldCancelRecording = false
            logger.notice("🎙️ Starting recording sequence...")
            requestRecordPermission { [self] granted in
                if granted {
                    Task {
                        do {
                            // --- Prepare temporary file URL within Application Support base directory ---
                            let baseAppSupportDirectory = self.recordingsDirectory.deletingLastPathComponent()
                            let file = baseAppSupportDirectory.appendingPathComponent("output.wav")
                            // Ensure the base directory exists
                            try? FileManager.default.createDirectory(at: baseAppSupportDirectory, withIntermediateDirectories: true)
                            // Clean up any old temporary file first
                            self.recordedFile = file

                            try await self.recorder.startRecording(toOutputFile: file)
                            self.logger.notice("✅ Audio engine started successfully.")

                            await MainActor.run {
                                self.isRecording = true
                                self.isVisualizerActive = true
                            }
                            
                            await ActiveWindowService.shared.applyConfigurationForCurrentApp()

                            // Only load model if it's a local model and not already loaded
                            if let model = self.currentTranscriptionModel, model.provider == .local {
                                if let localWhisperModel = self.availableModels.first(where: { $0.name == model.name }),
                                   self.whisperContext == nil {
                                    do {
                                        try await self.loadModel(localWhisperModel)
                                    } catch {
                                        self.logger.error("❌ Model loading failed: \(error.localizedDescription)")
                                    }
                                }
                            }

                            if let enhancementService = self.enhancementService,
                               enhancementService.useScreenCaptureContext {
                                await enhancementService.captureScreenContext()
                            }

                        } catch {
                            self.logger.error("❌ Failed to start recording: \(error.localizedDescription)")
                            await MainActor.run {
                                self.isRecording = false
                                self.isVisualizerActive = false
                            }
                            if let url = self.recordedFile {
                                try? FileManager.default.removeItem(at: url)
                                self.recordedFile = nil
                                self.logger.notice("🗑️ Cleaned up temporary recording file after failed start.")
                            }
                        }
                    }
                } else {
                    logger.error("❌ Recording permission denied.")
                }
            }
        }
    }
    
    private func requestRecordPermission(response: @escaping (Bool) -> Void) {
#if os(macOS)
        response(true)
#else
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            response(granted)
        }
#endif
    }
    
    // MARK: AVAudioRecorderDelegate
    
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error {
            Task {
                await handleRecError(error)
            }
        }
    }
    
    private func handleRecError(_ error: Error) {
        logger.error("Recording error: \(error.localizedDescription)")
        isRecording = false
    }
    
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task {
            await onDidFinishRecording(success: flag)
        }
    }
    
    private func onDidFinishRecording(success: Bool) {
        if !success {
            logger.error("Recording did not finish successfully")
        }
    }

    private func transcribeAudio(_ url: URL) async {
        if shouldCancelRecording {
            logger.info("🎤 Transcription and paste aborted at the beginning of transcribeAudio due to shouldCancelRecording flag.")
            await MainActor.run {
                isProcessing = false
                isTranscribing = false
                canTranscribe = true
            }
            await cleanupModelResources()
            return
        }
        
        await MainActor.run {
            isProcessing = true
            isTranscribing = true
            canTranscribe = false
        }
        
        defer {
            if shouldCancelRecording {
                Task {
                    await cleanupModelResources()
                }
            }
        }
        
        logger.notice("🔄 Starting transcription...")
        
        var permanentURL: URL?
        
        do {
            permanentURL = try saveRecordingPermanently(url)
            
            guard let model = currentTranscriptionModel else {
                throw WhisperStateError.transcriptionFailed
            }
            

            let transcriptionService: TranscriptionService = (model.provider == .local) ? localTranscriptionService : cloudTranscriptionService
            var text = try await transcriptionService.transcribe(audioURL: url, model: model)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if UserDefaults.standard.bool(forKey: "IsWordReplacementEnabled") {
                text = WordReplacementService.shared.applyReplacements(to: text)
            }
            
            let audioAsset = AVURLAsset(url: url)
            let actualDuration = CMTimeGetSeconds(try await audioAsset.load(.duration))
            var promptDetectionResult: PromptDetectionService.PromptDetectionResult? = nil
            let originalText = text
            
            // First clipboard copy: Raw transcription text (for external program storage)
            if isAutoCopyEnabled {
                let rawCopySuccess = ClipboardManager.copyToClipboard(originalText.trimmingCharacters(in: .whitespacesAndNewlines) + " ")
                if rawCopySuccess {
                    logger.notice("📋 Raw transcription copied to clipboard (first copy)")
                } else {
                    logger.error("❌ Failed to copy raw transcription to clipboard")
                }
            }
            
            if let enhancementService = enhancementService, enhancementService.isConfigured {
                let detectionResult = promptDetectionService.analyzeText(text, with: enhancementService)
                promptDetectionResult = detectionResult
                await promptDetectionService.applyDetectionResult(detectionResult, to: enhancementService)
            }
            
            if let enhancementService = enhancementService,
               enhancementService.isEnhancementEnabled,
               enhancementService.isConfigured {
                do {
                    if shouldCancelRecording { return }
                    let textForAI = promptDetectionResult?.processedText ?? text
                    let enhancedText = try await enhancementService.enhance(textForAI, duration: actualDuration)
                    let newTranscription = Transcription(
                        text: originalText,
                        duration: actualDuration,
                        enhancedText: enhancedText,
                        audioFileURL: permanentURL?.absoluteString
                    )
                    modelContext.insert(newTranscription)
                    try? modelContext.save()
                    text = enhancedText
                } catch {
                    let newTranscription = Transcription(
                        text: originalText,
                        duration: actualDuration,
                        audioFileURL: permanentURL?.absoluteString
                    )
                    modelContext.insert(newTranscription)
                    try? modelContext.save()
                }
            } else {
                let newTranscription = Transcription(
                    text: originalText,
                    duration: actualDuration,
                    audioFileURL: permanentURL?.absoluteString
                )
                modelContext.insert(newTranscription)
                try? modelContext.save()
            }
            
            // License system has been simplified - app is now Pro by default
            // Removed trial expired check as the upstream no longer has trial restrictions

            text += " "

            SoundManager.shared.playStopSound()
            if AXIsProcessTrusted() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    CursorPaster.pasteAtCursor(text, shouldPreserveClipboard: !self.isAutoCopyEnabled)
                }
            }
            
            // Second clipboard copy: Enhanced text (only if AI enhancement was applied)
            if isAutoCopyEnabled && enhancementService?.isEnhancementEnabled == true && text != originalText {
                let success = ClipboardManager.copyToClipboard(text)
                if success {
                    clipboardMessage = "Enhanced transcription copied to clipboard"
                    logger.notice("📋 Enhanced transcription copied to clipboard (second copy)")
                } else {
                    clipboardMessage = "Failed to copy enhanced transcription to clipboard"
                    logger.error("❌ Failed to copy enhanced transcription to clipboard")
                }
            } else if isAutoCopyEnabled && (enhancementService?.isEnhancementEnabled != true || text == originalText) {
                // If enhancement is disabled or text wasn't enhanced, update clipboard message accordingly
                clipboardMessage = "Raw transcription copied to clipboard"
            }
            try? FileManager.default.removeItem(at: url)
            
            if let result = promptDetectionResult,
               let enhancementService = enhancementService,
               result.shouldEnableAI {
                await promptDetectionService.restoreOriginalSettings(result, to: enhancementService)
            }
            
            await dismissMiniRecorder()
            await cleanupModelResources()
            
        } catch {
            if let permanentURL = permanentURL {
                do {
                    let audioAsset = AVURLAsset(url: permanentURL)
                    let duration = CMTimeGetSeconds(try await audioAsset.load(.duration))
                    
                    await MainActor.run {
                        let failedTranscription = Transcription(
                            text: "Transcription Failed: \(error.localizedDescription)",
                            duration: duration,
                            enhancedText: nil,
                            audioFileURL: permanentURL.absoluteString
                        )
                        
                        modelContext.insert(failedTranscription)
                        try? modelContext.save()
                    }
                } catch {
                    // Silently continue if failed transcription record can't be saved
                }
            }
            
            await MainActor.run {
                if permanentURL != nil {
                    NotificationManager.shared.showNotification(
                        title: "Transcription Failed",
                        message: "🔄 Tap to retry transcription",
                        type: .error,
                        onTap: { [weak self] in
                            Task {
                                await self?.retryLastTranscription()
                            }
                        }
                    )
                } else {
                    NotificationManager.shared.showNotification(
                        title: "Recording Failed",
                        message: "Could not save audio file. Please try recording again.",
                        type: .error
                    )
                }
            }
            
            await cleanupModelResources()
            await dismissMiniRecorder()
        }
    }

    private func saveRecordingPermanently(_ tempURL: URL) throws -> URL {
        let fileName = "\(UUID().uuidString).wav"
        let permanentURL = recordingsDirectory.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: tempURL, to: permanentURL)
        return permanentURL
    }
    
    func retryLastTranscription() async {
        do {
            let descriptor = FetchDescriptor<Transcription>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            let transcriptions = try modelContext.fetch(descriptor)
            
            guard let lastTranscription = transcriptions.first,
                  lastTranscription.text.hasPrefix("Transcription Failed"),
                  let audioURLString = lastTranscription.audioFileURL,
                  let audioURL = URL(string: audioURLString) else {
                return
            }
            
            guard let model = currentTranscriptionModel else {
                throw WhisperStateError.transcriptionFailed
            }
            
            let transcriptionService = AudioTranscriptionService(modelContext: modelContext, whisperState: self)
            let newTranscription = try await transcriptionService.retranscribeAudio(from: audioURL, using: model)
            
            await MainActor.run {
                NotificationManager.shared.showNotification(
                    title: "Transcription Successful",
                    message: "✅ Retry completed successfully",
                    type: .success
                )
                
                let textToPaste = newTranscription.enhancedText ?? newTranscription.text
                if AXIsProcessTrusted() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        CursorPaster.pasteAtCursor(textToPaste + " ", shouldPreserveClipboard: !self.isAutoCopyEnabled)
                    }
                }
            }
            
        } catch {
            await MainActor.run {
                NotificationManager.shared.showNotification(
                    title: "Retry Failed",
                    message: "Transcription failed again. Check your model and settings.",
                    type: .error
                )
            }
        }
    }

    // Loads the default transcription model from UserDefaults
    private func loadCurrentTranscriptionModel() {
        if let savedModelName = UserDefaults.standard.string(forKey: "CurrentTranscriptionModel"),
           let savedModel = allAvailableModels.first(where: { $0.name == savedModelName }) {
            currentTranscriptionModel = savedModel
        }
    }

    // Function to set any transcription model as default
    func setDefaultTranscriptionModel(_ model: any TranscriptionModel) {
        self.currentTranscriptionModel = model
        UserDefaults.standard.set(model.name, forKey: "CurrentTranscriptionModel")
        
        // For cloud models, clear the old loadedLocalModel
        if model.provider != .local {
            self.loadedLocalModel = nil
        }
        
        // Enable transcription for cloud models immediately since they don't need loading
        if model.provider != .local {
            self.canTranscribe = true
            self.isModelLoaded = true
        }
        
        logger.info("Default transcription model set to: \(model.name) (\(model.provider.rawValue))")
        
        // Post notification about the model change
        NotificationCenter.default.post(name: .didChangeModel, object: nil, userInfo: ["modelName": model.name])
    }

    func getEnhancementService() -> AIEnhancementService? {
        return enhancementService
    }
    
    func refreshAllAvailableModels() {
        let currentModelId = currentTranscriptionModel?.id
        allAvailableModels = PredefinedModels.models
        
        // If there was a current default model, find its new version in the refreshed list and update it.
        // This handles cases where the default model was edited.
        if let currentId = currentModelId,
           let updatedModel = allAvailableModels.first(where: { $0.id == currentId })
        {
            setDefaultTranscriptionModel(updatedModel)
        }
    }
}

struct WhisperModel: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    var coreMLEncoderURL: URL? // Path to the unzipped .mlmodelc directory
    var isCoreMLDownloaded: Bool { coreMLEncoderURL != nil }
    
    var downloadURL: String {
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)"
    }
    
    var filename: String {
        "\(name).bin"
    }
    
    // Core ML related properties
    var coreMLZipDownloadURL: String? {
        // Only non-quantized models have Core ML versions
        guard !name.contains("q5") && !name.contains("q8") else { return nil }
        return "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(name)-encoder.mlmodelc.zip"
    }
    
    var coreMLEncoderDirectoryName: String? {
        guard coreMLZipDownloadURL != nil else { return nil }
        return "\(name)-encoder.mlmodelc"
    }
}

private class TaskDelegate: NSObject, URLSessionTaskDelegate {
    private let continuation: CheckedContinuation<Void, Never>
    
    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        continuation.resume()
    }
}

extension Notification.Name {
    static let toggleMiniRecorder = Notification.Name("toggleMiniRecorder")
    static let didChangeModel = Notification.Name("didChangeModel")
}
