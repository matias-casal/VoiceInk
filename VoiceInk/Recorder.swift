import Foundation
import AVFoundation
import CoreAudio
import os

@MainActor
class Recorder: ObservableObject {
    private var recorder: AVAudioRecorder?
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "Recorder")
    private let deviceManager = AudioDeviceManager.shared
    private var deviceObserver: NSObjectProtocol?
    private var isReconfiguring = false
    private let mediaController = MediaController.shared
    @Published var audioMeter = AudioMeter(averagePower: 0, peakPower: 0)
    
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
        
        if recorder != nil {
            let currentURL = recorder?.url
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
        
        let recordSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        do {
            recorder = try AVAudioRecorder(url: url, settings: recordSettings)
            recorder?.isMeteringEnabled = true
            
            if recorder?.record() == false {
                logger.error("❌ Could not start recording")
                throw RecorderError.couldNotStartRecording
            }
            
            Task {
                while recorder != nil {
                    updateAudioMeter()
                    try? await Task.sleep(nanoseconds: 33_000_000)
                }
            }
            
        } catch {
            logger.error("Failed to create audio recorder: \(error.localizedDescription)")
            stopRecording()
            throw RecorderError.couldNotStartRecording
        }
    }
    
    func stopRecording() {
        recorder?.stop()
        recorder = nil
        audioMeter = AudioMeter(averagePower: 0, peakPower: 0)
        Task {
            await mediaController.unmuteSystemAudio()
        }
        deviceManager.isRecordingActive = false
    }
    
    private func updateAudioMeter() {
        guard let recorder = recorder else { return }
        recorder.updateMeters()
        
        let averagePower = recorder.averagePower(forChannel: 0)
        let peakPower = recorder.peakPower(forChannel: 0)
        
        let minVisibleDb: Float = -60.0 
        let maxVisibleDb: Float = 0.0

        let normalizedAverage: Float
        if averagePower < minVisibleDb {
            normalizedAverage = 0.0
        } else if averagePower >= maxVisibleDb {
            normalizedAverage = 1.0
        } else {
            normalizedAverage = (averagePower - minVisibleDb) / (maxVisibleDb - minVisibleDb)
        }
        
        let normalizedPeak: Float
        if peakPower < minVisibleDb {
            normalizedPeak = 0.0
        } else if peakPower >= maxVisibleDb {
            normalizedPeak = 1.0
        } else {
            normalizedPeak = (peakPower - minVisibleDb) / (maxVisibleDb - minVisibleDb)
        }
        
        audioMeter = AudioMeter(averagePower: Double(normalizedAverage), peakPower: Double(normalizedPeak))
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