import Foundation
import AppKit
import Vision
import os

class ScreenCaptureService: ObservableObject {
    @Published var isCapturing = false
    @Published var lastCapturedText: String?
    
    private let logger = Logger(
        subsystem: "com.bootweb.VoiceInk",
        category: "aienhancement"
    )
    
    // Maximum number of retries for capture attempts
    private let maxCaptureRetries = 3
    // Delay between capture retries in seconds
    private let captureRetryDelay: TimeInterval = 0.5
    
    private func getActiveWindowInfo() -> (title: String, ownerName: String, windowID: CGWindowID)? {
        // Try multiple window list options to improve reliability
        let options: [CGWindowListOption] = [
            [.optionOnScreenOnly, .excludeDesktopElements],
            [.optionOnScreenOnly],
            []
        ]
        
        for option in options {
            let windowListInfo = CGWindowListCopyWindowInfo(option, kCGNullWindowID) as? [[String: Any]] ?? []
            
            // Find the frontmost window that isn't our own app
            if let frontWindow = windowListInfo.first(where: { info in
                let layer = info[kCGWindowLayer as String] as? Int32 ?? 0
                let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
                // Exclude our own app and system UI elements
                return layer == 0 && ownerName != "VoiceInk" && !ownerName.contains("Dock") && !ownerName.contains("Menu Bar")
            }) {
                guard let windowID = frontWindow[kCGWindowNumber as String] as? CGWindowID,
                      let ownerName = frontWindow[kCGWindowOwnerName as String] as? String,
                      let title = frontWindow[kCGWindowName as String] as? String else {
                    continue
                }
                
                return (title: title, ownerName: ownerName, windowID: windowID)
            }
        }
        
        // If we couldn't find a window with the normal approach, try a more aggressive approach
        logger.notice("Trying fallback window detection approach")
        let allWindows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        
        // Find any visible window that isn't our own
        if let visibleWindow = allWindows.first(where: { info in
            let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 0
            return ownerName != "VoiceInk" && !ownerName.contains("Dock") && alpha > 0
        }) {
            let windowID = visibleWindow[kCGWindowNumber as String] as? CGWindowID ?? 0
            let ownerName = visibleWindow[kCGWindowOwnerName as String] as? String ?? "Unknown App"
            let title = visibleWindow[kCGWindowName as String] as? String ?? "Unknown Window"
            
            logger.notice("Found fallback window: \(title, privacy: .public) (\(ownerName, privacy: .public))")
            return (title: title, ownerName: ownerName, windowID: windowID)
        }
        
        logger.notice("❌ No suitable window found for capture")
        return nil
    }
    
    func captureActiveWindow() -> NSImage? {
        guard let windowInfo = getActiveWindowInfo() else {
            logger.notice("❌ Failed to get window info for capture")
            return captureFullScreen() // Fallback to full screen capture
        }
        
        // Try to capture the specific window
        let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowInfo.windowID,
            [.boundsIgnoreFraming, .bestResolution]
        )
        
        if let cgImage = cgImage {
            logger.notice("✅ Successfully captured window")
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } else {
            logger.notice("⚠️ Window-specific capture failed, trying fallback methods")
            return captureFullScreen() // Fallback to full screen
        }
    }
    
    private func captureFullScreen() -> NSImage? {
        logger.notice("📺 Attempting full screen capture as fallback")
        
        // Capture the entire screen
        if let screen = NSScreen.main {
            let rect = screen.frame
            let cgImage = CGWindowListCreateImage(
                rect,
                .optionOnScreenOnly,
                kCGNullWindowID,
                [.bestResolution]
            )
            
            if let cgImage = cgImage {
                logger.notice("✅ Full screen capture successful")
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
        }
        
        logger.notice("❌ All capture methods failed")
        return nil
    }
    
    func extractText(from image: NSImage, completion: @escaping (String?) -> Void) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            logger.notice("❌ Failed to convert NSImage to CGImage for text extraction")
            completion(nil)
            return
        }
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                self.logger.notice("❌ Text recognition error: \(error.localizedDescription, privacy: .public)")
                completion(nil)
                return
            }
            
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                self.logger.notice("❌ No text observations found")
                completion(nil)
                return
            }
            
            let text = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }.joined(separator: "\n")
            
            if text.isEmpty {
                self.logger.notice("⚠️ Text extraction returned empty result")
                completion(nil)
            } else {
                self.logger.notice("✅ Text extraction successful, found \(text.count, privacy: .public) characters")
                completion(text)
            }
        }
        
        // Configure the recognition level
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        do {
            try requestHandler.perform([request])
        } catch {
            logger.notice("❌ Failed to perform text recognition: \(error.localizedDescription, privacy: .public)")
            completion(nil)
        }
    }
    
    func captureAndExtractText() async -> String? {
        guard !isCapturing else { 
            logger.notice("⚠️ Screen capture already in progress, skipping")
            return nil 
        }
        
        isCapturing = true
        defer { 
            DispatchQueue.main.async {
                self.isCapturing = false
            }
        }
        
        logger.notice("🎬 Starting screen capture")
        
        // Try multiple times to get a successful capture
        for attempt in 1...maxCaptureRetries {
            logger.notice("🔄 Capture attempt \(attempt, privacy: .public) of \(self.maxCaptureRetries, privacy: .public)")
            
            // First get window info
            guard let windowInfo = getActiveWindowInfo() else {
                logger.notice("❌ Failed to get window info on attempt \(attempt, privacy: .public)")
                if attempt < maxCaptureRetries {
                    try? await Task.sleep(nanoseconds: UInt64(captureRetryDelay * 1_000_000_000))
                    continue
                }
                return nil
            }
            
            logger.notice("🎯 Found window: \(windowInfo.title, privacy: .public) (\(windowInfo.ownerName, privacy: .public))")
            
            // Start with window metadata
            var contextText = """
            Active Window: \(windowInfo.title)
            Application: \(windowInfo.ownerName)
            
            """
            
            // Then capture and process window content
            if let capturedImage = captureActiveWindow() {
                if let extractedText = await withCheckedContinuation({ continuation in
                    extractText(from: capturedImage) { text in
                        continuation.resume(returning: text)
                    }
                }) {
                    contextText += "Window Content:\n\(extractedText)"
                    // Log immediately after text extraction
                    logger.notice("✅ Captured: \(contextText, privacy: .public)")
                    
                    // Ensure lastCapturedText is set on the main thread
                    await MainActor.run {
                        self.lastCapturedText = contextText
                    }
                    
                    return contextText
                } else {
                    logger.notice("⚠️ Failed to extract text from image on attempt \(attempt, privacy: .public)")
                }
            } else {
                logger.notice("⚠️ Failed to capture window image on attempt \(attempt, privacy: .public)")
            }
            
            if attempt < maxCaptureRetries {
                try? await Task.sleep(nanoseconds: UInt64(captureRetryDelay * 1_000_000_000))
            }
        }
        
        logger.notice("❌ All capture attempts failed")
        return nil
    }
} 
