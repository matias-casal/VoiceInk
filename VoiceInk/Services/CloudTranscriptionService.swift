import Foundation
import os

enum CloudTranscriptionError: Error, LocalizedError {
    case unsupportedProvider
    case missingAPIKey
    case invalidAPIKey
    case audioFileNotFound
    case apiRequestFailed(statusCode: Int, message: String)
    case networkError(Error)
    case noTranscriptionReturned
    case dataEncodingError
    
    var errorDescription: String? {
        switch self {
        case .unsupportedProvider:
            return "The model provider is not supported by this service."
        case .missingAPIKey:
            return "API key for this service is missing. Please configure it in the settings."
        case .invalidAPIKey:
            return "The provided API key is invalid."
        case .audioFileNotFound:
            return "The audio file to transcribe could not be found."
        case .apiRequestFailed(let statusCode, let message):
            return "The API request failed with status code \(statusCode): \(message)"
        case .networkError(let error):
            return "A network error occurred: \(error.localizedDescription)"
        case .noTranscriptionReturned:
            return "The API returned an empty or invalid response."
        case .dataEncodingError:
            return "Failed to encode the request body."
        }
    }
}

class CloudTranscriptionService: TranscriptionService {
    
    private struct APIConfig {
        let url: URL
        let apiKey: String
        let modelName: String
    }
    
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let config = try getAPIConfig(for: model)
        
        var request: URLRequest
        var body: Data
        
        switch model.provider {
        case .elevenLabs:
            let boundary = "Boundary-\(UUID().uuidString)"
            var elevenLabsRequest = URLRequest(url: config.url)
            elevenLabsRequest.httpMethod = "POST"
            elevenLabsRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            elevenLabsRequest.setValue(config.apiKey, forHTTPHeaderField: "xi-api-key")
            body = try createElevenLabsRequestBody(audioURL: audioURL, modelName: config.modelName, boundary: boundary)
            request = elevenLabsRequest
            
        case .groq:
            let boundary = "Boundary-\(UUID().uuidString)"
            var openAICompatibleRequest = URLRequest(url: config.url)
            openAICompatibleRequest.httpMethod = "POST"
            openAICompatibleRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            openAICompatibleRequest.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
            body = try createOpenAICompatibleRequestBody(audioURL: audioURL, modelName: config.modelName, boundary: boundary)
            request = openAICompatibleRequest
            

            
        default:
            throw CloudTranscriptionError.unsupportedProvider
        }
        
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudTranscriptionError.networkError(URLError(.badServerResponse))
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorMessage = String(data: data, encoding: .utf8) ?? "No error message"
            throw CloudTranscriptionError.apiRequestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        do {
            let transcriptionResponse = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
            return transcriptionResponse.text
        } catch {
            throw CloudTranscriptionError.noTranscriptionReturned
        }
    }
    
    private func getAPIConfig(for model: any TranscriptionModel) throws -> APIConfig {
        let providerKey: String
        let apiURL: URL
        
        switch model.provider {
        case .groq:
            providerKey = "GROQ"
            apiURL = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
        case .elevenLabs:
            providerKey = "ElevenLabs"
            apiURL = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!
        default:
            throw CloudTranscriptionError.unsupportedProvider
        }
        
        guard let apiKey = UserDefaults.standard.string(forKey: "\(providerKey)APIKey"), !apiKey.isEmpty else {
            throw CloudTranscriptionError.missingAPIKey
        }
        
        return APIConfig(url: apiURL, apiKey: apiKey, modelName: model.name)
    }
    
    private func createElevenLabsRequestBody(audioURL: URL, modelName: String, boundary: String) throws -> Data {
        var body = Data()
        let crlf = "\r\n"
        
        guard let audioData = try? Data(contentsOf: audioURL) else {
            throw CloudTranscriptionError.audioFileNotFound
        }
        
        // File
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioURL.lastPathComponent)\"\(crlf)".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(audioData)
        body.append(crlf.data(using: .utf8)!)
        
        // Model ID
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model_id\"\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(modelName.data(using: .utf8)!)
        body.append(crlf.data(using: .utf8)!)
        
        let selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
        if selectedLanguage != "auto", !selectedLanguage.isEmpty {
            body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language_code\"\(crlf)\(crlf)".data(using: .utf8)!)
            body.append(selectedLanguage.data(using: .utf8)!)
            body.append(crlf.data(using: .utf8)!)
        }
        
        body.append("--\(boundary)--\(crlf)".data(using: .utf8)!)
        
        return body
    }
    
    private func createOpenAICompatibleRequestBody(audioURL: URL, modelName: String, boundary: String) throws -> Data {
        var body = Data()
        let crlf = "\r\n"
        
        guard let audioData = try? Data(contentsOf: audioURL) else {
            throw CloudTranscriptionError.audioFileNotFound
        }
        
        let selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
        let prompt = UserDefaults.standard.string(forKey: "TranscriptionPrompt") ?? ""
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioURL.lastPathComponent)\"\(crlf)".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(audioData)
        body.append(crlf.data(using: .utf8)!)
        
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(modelName.data(using: .utf8)!)
        body.append(crlf.data(using: .utf8)!)
        
        if selectedLanguage != "auto", !selectedLanguage.isEmpty {
            body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\(crlf)\(crlf)".data(using: .utf8)!)
            body.append(selectedLanguage.data(using: .utf8)!)
            body.append(crlf.data(using: .utf8)!)
        }
        
        // Include prompt for OpenAI-compatible APIs
        if !prompt.isEmpty {
            body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"prompt\"\(crlf)\(crlf)".data(using: .utf8)!)
            body.append(prompt.data(using: .utf8)!)
            body.append(crlf.data(using: .utf8)!)
        }
        
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\(crlf)\(crlf)".data(using: .utf8)!)
        body.append("json".data(using: .utf8)!)
        body.append(crlf.data(using: .utf8)!)
        
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"temperature\"\(crlf)\(crlf)".data(using: .utf8)!)
        body.append("0".data(using: .utf8)!)
        body.append(crlf.data(using: .utf8)!)
        body.append("--\(boundary)--\(crlf)".data(using: .utf8)!)
        
        return body
    }
    
    private struct TranscriptionResponse: Decodable {
        let text: String
        let language: String?
        let duration: Double?
        let x_groq: GroqMetadata?
        
        struct GroqMetadata: Decodable {
            let id: String?
        }
    }
    

} 