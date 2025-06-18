import SwiftUI

struct LicenseManagementView: View {
    @StateObject private var licenseViewModel = LicenseViewModel()
    
    var body: some View {
        VStack(spacing: 24) {
            // Pro Status Header
            VStack(spacing: 16) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.green)
                
                VStack(spacing: 8) {
                    Text("VoiceInk Pro")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Full version activated")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 32)
            
            // Pro Features List
            VStack(alignment: .leading, spacing: 16) {
                Text("Pro Features Included:")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 12) {
                    FeatureRow(icon: "mic.fill", title: "Unlimited Transcription", description: "No limits on recording length or frequency")
                    FeatureRow(icon: "wand.and.stars", title: "AI Enhancement", description: "Advanced text processing and improvement")
                    FeatureRow(icon: "square.and.arrow.up", title: "Export & Import", description: "Save and share your transcriptions")
                    FeatureRow(icon: "gear", title: "Advanced Settings", description: "Full customization and configuration options")
                    FeatureRow(icon: "keyboard", title: "Custom Shortcuts", description: "Personalized hotkeys and automation")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: 600)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.green)
        }
    }
}

#Preview {
    LicenseManagementView()
}


