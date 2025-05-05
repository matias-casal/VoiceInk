import Foundation
import AVFoundation
import CoreAudio
import os

@MainActor
class Recorder: ObservableObject {
    private var engine: AVAudioEngine?
    private var file: AVAudioFile?
    private let logger = Logger(subsystem: "com.bootweb.VoiceInk", category: "Recorder")
    private let deviceManager = AudioDeviceManager.shared
    private var deviceObserver: NSObjectProtocol?
    private var isReconfiguring = false
    private let mediaController = MediaController.shared
    @Published var audioMeter = AudioMeter(averagePower: 0, peakPower: 0)
    private var latestBuffer: AVAudioPCMBuffer?
    
    enum RecorderError: Error {
        case couldNotStartRecording
    }
    
    init() {
        setupDeviceChangeObserver()
    }
    
    private func setupDeviceChangeObserver() {
        deviceObserver = AudioDeviceConfiguration.createDeviceChangeObserver { [weak self] in
            Task {
                await self?.handleDeviceChange()
            }
        }
    }
    
    private func handleDeviceChange() async {
        guard !isReconfiguring else { return }
        isReconfiguring = true

        if engine != nil {
            let currentURL = file?.url
            stopRecording()
            try? await Task.sleep(nanoseconds: 100_000_000)
            
            if let url = currentURL {
                do {
                    try await startRecording(toOutputFile: url)
                } catch {
                    logger.error("❌ Failed to restart recording after device change: \(error.localizedDescription)")
                }
            }
        }
        isReconfiguring = false
    }
    
    private func configureAudioSession(with deviceID: AudioDeviceID) async throws {
        do {
            _ = try AudioDeviceConfiguration.configureAudioSession(with: deviceID)
            try AudioDeviceConfiguration.setDefaultInputDevice(deviceID)
        } catch {
            logger.error("❌ Failed to configure audio session: \(error.localizedDescription)")
            throw error
        }
    }
    
    func startRecording(toOutputFile url: URL) async throws {
        deviceManager.isRecordingActive = true

        Task { 
            await mediaController.muteSystemAudio()
        }
        let deviceID = deviceManager.getCurrentDevice()
        if deviceID != 0 {
            do {
                try await configureAudioSession(with: deviceID)
            } catch {
                logger.warning("⚠️ Failed to configure audio session for device \(deviceID), attempting to continue: \(error.localizedDescription)")
            }
        }
        
        engine = AVAudioEngine()
        let inputNode = engine!.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        let whisperSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        let processingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000.0,
            channels: 1,
            interleaved: false
        )!
        
        do {
            file = try AVAudioFile(forWriting: url, settings: whisperSettings)
        } catch {
            logger.error("Failed to create audio file: \(error.localizedDescription)")
            stopRecording()
            throw RecorderError.couldNotStartRecording
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            let processedBuffer: AVAudioPCMBuffer
            if buffer.format != processingFormat {
                guard let converter = AVAudioConverter(from: buffer.format, to: processingFormat),
                      let newBuffer = AVAudioPCMBuffer(pcmFormat: processingFormat, 
                                                      frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * 
                                                                                    (16000.0 / buffer.format.sampleRate))) else {
                    self.logger.error("Failed to create converter or buffer")
                    return
                }
                
                var error: NSError?
                let status = converter.convert(to: newBuffer, error: &error) { _, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }
                
                if status == .error || error != nil {
                    self.logger.error("Format conversion failed: \(error?.localizedDescription ?? "unknown error")")
                    return
                }
                
                processedBuffer = newBuffer
            } else {
                processedBuffer = buffer
            }
            
            Task { @MainActor in
                self.latestBuffer = processedBuffer
                self.calculateAndUpdateAudioLevel(buffer: processedBuffer)
            }
            
            do {
                guard let int16Converter = AVAudioConverter(from: processedBuffer.format, to: self.file!.processingFormat),
                      let int16Buffer = AVAudioPCMBuffer(pcmFormat: self.file!.processingFormat, 
                                                        frameCapacity: processedBuffer.frameLength) else {
                    self.logger.error("Failed to create int16 converter")
                    return
                }
                
                var conversionError: NSError?
                let conversionStatus = int16Converter.convert(to: int16Buffer, error: &conversionError) { _, outStatus in
                    outStatus.pointee = .haveData
                    return processedBuffer
                }
                
                if conversionStatus == .error || conversionError != nil {
                    self.logger.error("Int16 conversion failed")
                    return
                }
                
                try self.file?.write(from: int16Buffer)
            } catch {
                self.logger.error("Failed to write audio buffer: \(error.localizedDescription)")
            }
        }
        
        do {
            try engine!.start()
        } catch {
            logger.error("❌ Failed to start audio engine: \(error.localizedDescription)")
            stopRecording()
            throw RecorderError.couldNotStartRecording
        }
    }
    
    func stopRecording() {
        let wasRunning = engine != nil
        defer {
            deviceManager.isRecordingActive = false
            engine?.stop()
            engine = nil
        }

        audioMeter = AudioMeter(averagePower: 0, peakPower: 0)
        engine?.inputNode.removeTap(onBus: 0)
        file = nil
        NotificationCenter.default.post(name: NSNotification.Name("AudioDeviceChanged"), object: nil)
        Task {
            await mediaController.unmuteSystemAudio()
        }
    }
    
    private func calculateAndUpdateAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let floatData = buffer.floatChannelData else { return }
        let channelData = floatData[0]
        let frameLength = Int(buffer.frameLength)
        
        var sum: Float = 0
        var peak: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
            peak = max(peak, abs(sample))
        }
        
        let rms = sqrt(sum / Float(frameLength))
        let peakValue = peak
        
        let multiplier: Double = 20.0
        let scaledRMS = min(Double(rms) * multiplier, 1.0)
        let scaledPeak = min(Double(peakValue) * multiplier, 1.0)
        
        audioMeter = AudioMeter(averagePower: scaledRMS, peakPower: scaledPeak)
    }
    
    deinit {
        if let observer = deviceObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

struct AudioMeter: Equatable {
    let averagePower: Double
    let peakPower: Double
}