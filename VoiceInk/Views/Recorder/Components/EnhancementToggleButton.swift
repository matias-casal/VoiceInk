import SwiftUI

// Enhancement Toggle Button Component
struct EnhancementToggleButton: View {
    let isEnabled: Bool
    let isConfigured: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: isEnabled ? "brain.head.profile.fill" : "brain.head.profile")
                .font(.system(size: 12, weight: isEnabled ? .medium : .regular))
                .foregroundColor(buttonColor)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isConfigured)
    }
    
    private var buttonColor: Color {
        if !isConfigured {
            return .white.opacity(0.3)
        } else if isEnabled {
            return .blue
        } else {
            return .white.opacity(0.6)
        }
    }
} 