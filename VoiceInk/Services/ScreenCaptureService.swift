import Foundation
import SwiftUI
import AppKit
import Vision
import os

class ScreenCaptureService: ObservableObject {
    @Published var isCapturing = false
    @Published var lastCapturedText: String?
    
    private let logger = Logger(subsystem: "com.bootweb.VoiceInk", category: "aienhancement")
    
    init() {
        logger.notice("ScreenCaptureService initialized")
    }
    
    private func getActiveWindowInfo() -> (title: String, ownerName: String, windowID: CGWindowID)? {
        let windowListInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        
        if let frontWindow = windowListInfo.first(where: { info in
            let layer = info[kCGWindowLayer as String] as? Int32 ?? 0
            let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
            return layer == 0 && ownerName != "VoiceInk" && !ownerName.contains("Dock") && !ownerName.contains("Menu Bar")
        }) {
            let title = frontWindow[kCGWindowName as String] as? String ?? ""
            let ownerName = frontWindow[kCGWindowOwnerName as String] as? String ?? ""
            let windowID = frontWindow[kCGWindowNumber as String] as? CGWindowID ?? 0
            
            return (title: title, ownerName: ownerName, windowID: windowID)
        }
        
        return nil
    }
    
    func extractText(from image: NSImage, completion: @escaping (String?) -> Void) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion(nil)
            return
        }
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                self.logger.notice("Text recognition error: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            let recognizedStrings = observations.compactMap { observation in
                return observation.topCandidates(3).first?.string
            }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            
            let extractedText = recognizedStrings.joined(separator: "\n")
            completion(extractedText.isEmpty ? nil : extractedText)
        }
        
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US", "es-ES"]
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.01
        
        do {
            try requestHandler.perform([request])
        } catch {
            logger.notice("Failed to perform text recognition: \(error.localizedDescription)")
            completion(nil)
        }
    }
    
    func detectActiveScreen() -> NSScreen? {
        if let windowInfo = getActiveWindowInfo() {
            let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
            
            if let windowDict = windowList.first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == windowInfo.windowID }),
               let boundsDict = windowDict[kCGWindowBounds as String] as? [String: Any],
               let x = boundsDict["X"] as? CGFloat,
               let y = boundsDict["Y"] as? CGFloat,
               let width = boundsDict["Width"] as? CGFloat,
               let height = boundsDict["Height"] as? CGFloat {
                
                let windowCenter = CGPoint(x: x + width/2, y: y + height/2)
                
                for screen in NSScreen.screens {
                    let screenFrame = screen.frame
                    if screenFrame.contains(windowCenter) {
                        return screen
                    }
                }
            }
        }
        
        let mouseLocation = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            let screenFrame = screen.frame
            if screenFrame.contains(mouseLocation) {
                return screen
            }
        }
        
        return NSScreen.main
    }
    
    func captureSpecificScreen(_ screen: NSScreen) -> NSImage? {
        let screenFrame = screen.frame
        let primaryScreen = NSScreen.screens.first!
        let primaryHeight = primaryScreen.frame.height
        
        let cgRect = CGRect(
            x: screenFrame.origin.x,
            y: primaryHeight - screenFrame.origin.y - screenFrame.height,
            width: screenFrame.width,
            height: screenFrame.height
        )
        
        let cgImage = CGWindowListCreateImage(
            cgRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        )
        
        if let cgImage = cgImage, cgImage.width > 0 && cgImage.height > 0 {
            return NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
        }
        
        return nil
    }
    
    func captureFullScreen() -> NSImage? {
        guard let activeScreen = detectActiveScreen() else {
            return captureAllScreens()
        }
        
        if let screenImage = captureSpecificScreen(activeScreen) {
            return screenImage
        }
        
        return captureAllScreens()
    }
    
    func captureAllScreens() -> NSImage? {
        let cgImage = CGWindowListCreateImage(
            .null,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        )
        
        if let cgImage = cgImage, cgImage.width > 0 && cgImage.height > 0 {
            return NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
        }
        
        return nil
    }
    
    func captureActiveWindow() -> NSImage? {
        guard let windowInfo = getActiveWindowInfo() else {
            return captureFullScreen()
        }
        
        let cgImage1 = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowInfo.windowID,
            [.boundsIgnoreFraming, .bestResolution]
        )
        
        if let cgImage1 = cgImage1, cgImage1.width > 0 && cgImage1.height > 0 {
            if cgImage1.height < 100 {
                let cgImage2 = CGWindowListCreateImage(
                    .null,
                    .optionIncludingWindow,
                    windowInfo.windowID,
                    [.bestResolution]
                )
                
                if let cgImage2 = cgImage2, cgImage2.height > cgImage1.height {
                    return NSImage(cgImage: cgImage2, size: CGSize(width: cgImage2.width, height: cgImage2.height))
                }
                
                if let smartScreenImage = captureFullScreen() {
                    return smartScreenImage
                }
            }
            
            return NSImage(cgImage: cgImage1, size: CGSize(width: cgImage1.width, height: cgImage1.height))
        }
        
        return captureFullScreen()
    }
    
    func captureAndExtractText() async -> String? {
        guard !isCapturing else { 
            return nil 
        }
        
        isCapturing = true
        defer { 
            DispatchQueue.main.async {
                self.isCapturing = false
            }
        }
        
        guard let windowInfo = getActiveWindowInfo() else {
            return nil
        }
        
        var contextText = "Active Window:\nApplication: \(windowInfo.ownerName)\n"
        
        if !windowInfo.title.isEmpty {
            contextText += "Window Title: \(windowInfo.title)\n"
        }
        
        if let capturedImage = captureActiveWindow() {
            let extractedText = await withCheckedContinuation({ continuation in
                extractText(from: capturedImage) { text in
                    continuation.resume(returning: text)
                }
            })
            
            if let extractedText = extractedText {
                contextText += "Window Content:\n\(extractedText)"
            } else {
                contextText += "Window Content: [No text could be extracted from the window]"
            }
        } else {
            contextText += "Window Content: [Could not capture window]"
        }
        
        DispatchQueue.main.async {
            self.lastCapturedText = contextText
        }
        
        return contextText
    }
} 
