import SwiftUI

struct MiniRecorderView: View {
    @ObservedObject var whisperState: WhisperState
    @ObservedObject var recorder: Recorder
    @EnvironmentObject var windowManager: MiniWindowManager
    @State private var showPowerModePopover = false
    @ObservedObject private var powerModeManager = PowerModeManager.shared
    
    var body: some View {
        Group {
            if windowManager.isVisible {
                Capsule()
                    .fill(.clear)
                    .background(
                        ZStack {
                            // Base dark background
                            Color.black.opacity(0.9)
                            
                            // Subtle gradient overlay
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.95),
                                    Color(red: 0.15, green: 0.15, blue: 0.15).opacity(0.9)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            
                            // Very subtle visual effect for depth
                            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                                .opacity(0.05)
                        }
                        .clipShape(Capsule())
                    )
                    .overlay {
                        // Subtle inner border
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                    }
                    .overlay {
                        HStack(spacing: 0) {
                            // Record Button - on the left
                            NotchRecordButton(
                                isRecording: whisperState.isRecording,
                                isProcessing: whisperState.isProcessing
                            ) {
                                Task { await whisperState.toggleRecord() }
                            }
                            .frame(width: 24)
                            .padding(.leading, 8)
                            
                            // Visualizer - centered and expanded
                            Group {
                                if whisperState.isProcessing {
                                    StaticVisualizer(color: .white)
                                } else {
                                    AudioVisualizer(
                                        audioMeter: recorder.audioMeter,
                                        color: .white,
                                        isActive: whisperState.isRecording
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 8)
                            
                            // Power Mode Button - on the right
                            NotchToggleButton(
                                isEnabled: powerModeManager.isPowerModeEnabled,
                                icon: powerModeManager.currentActiveConfiguration.emoji,
                                color: .orange,
                                disabled: !powerModeManager.isPowerModeEnabled
                            ) {
                                if powerModeManager.isPowerModeEnabled {
                                    showPowerModePopover.toggle()
                                }
                            }
                            .frame(width: 24)
                            .padding(.trailing, 8)
                            .popover(isPresented: $showPowerModePopover, arrowEdge: .bottom) {
                                PowerModePopover()
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .opacity(windowManager.isVisible ? 1 : 0)
            }
        }
    }
}


