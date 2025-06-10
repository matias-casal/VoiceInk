import Foundation

extension WhisperState {
    var usableModels: [any TranscriptionModel] {
        allAvailableModels.filter { model in
            switch model.provider {
            case .local:
                return availableModels.contains { $0.name == model.name }
            case .groq:
                let key = UserDefaults.standard.string(forKey: "GROQAPIKey")
                return key != nil && !key!.isEmpty
            case .elevenLabs:
                let key = UserDefaults.standard.string(forKey: "ElevenLabsAPIKey")
                return key != nil && !key!.isEmpty
            }
        }
    }
} 
