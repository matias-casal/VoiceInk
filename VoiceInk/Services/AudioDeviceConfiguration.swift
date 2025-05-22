import Foundation
import AVFoundation
import CoreAudio
import os

class AudioDeviceConfiguration {
    private static let logger = Logger(subsystem: "com.bootweb.VoiceInk", category: "AudioDeviceConfiguration")
    

    static func configureAudioSession(with deviceID: AudioDeviceID) throws -> AudioStreamBasicDescription {
        var propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var streamFormat = AudioStreamBasicDescription()
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // First, ensure the device is ready
        var isAlive: UInt32 = 0
        var aliveSize = UInt32(MemoryLayout<UInt32>.size)
        var aliveAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let aliveStatus = AudioObjectGetPropertyData(
            deviceID,
            &aliveAddress,
            0,
            nil,
            &aliveSize,
            &isAlive
        )
        
        if aliveStatus != noErr || isAlive == 0 {
            logger.error("Device \(deviceID) is not alive or ready")
            throw AudioConfigurationError.failedToGetDeviceFormat(status: aliveStatus)
        }
        
        // Get the device format
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &streamFormat
        )
        
        if status != noErr {
            logger.error("Failed to get device format: \(status)")
            throw AudioConfigurationError.failedToGetDeviceFormat(status: status)
        }
        
        return streamFormat
    }
    

    static func setDefaultInputDevice(_ deviceID: AudioDeviceID) throws {
        var deviceIDCopy = deviceID
        let propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let setDeviceResult = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            propertySize,
            &deviceIDCopy
        )
        
        if setDeviceResult != noErr {
            logger.error("Failed to set input device: \(setDeviceResult)")
            throw AudioConfigurationError.failedToSetInputDevice(status: setDeviceResult)
        }
    }
    
    /// Creates a device change observer
    /// - Parameters:
    ///   - handler: The closure to execute when device changes
    ///   - queue: The queue to execute the handler on (defaults to main queue)
    /// - Returns: The observer token
    static func createDeviceChangeObserver(
        handler: @escaping () -> Void,
        queue: OperationQueue = .main
    ) -> NSObjectProtocol {
        return NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AudioDeviceChanged"),
            object: nil,
            queue: queue,
            using: { _ in handler() }
        )
    }
}

enum AudioConfigurationError: LocalizedError {
    case failedToGetDeviceFormat(status: OSStatus)
    case failedToSetInputDevice(status: OSStatus)
    case failedToGetAudioUnit
    
    var errorDescription: String? {
        switch self {
        case .failedToGetDeviceFormat(let status):
            return "Failed to get device format: \(status)"
        case .failedToSetInputDevice(let status):
            return "Failed to set input device: \(status)"
        case .failedToGetAudioUnit:
            return "Failed to get audio unit from input node"
        }
    }
} 