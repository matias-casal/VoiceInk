import SwiftUI

struct AppNotificationView: View {
    let title: String
    let message: String
    let type: NotificationType
    let duration: TimeInterval
    let onClose: () -> Void
    let onTap: (() -> Void)?
    
    @State private var progress: Double = 1.0
    @State private var timer: Timer?

    enum NotificationType {
        case error
        case warning
        case info
        case success

        var iconName: String {
            switch self {
            case .error: return "xmark.octagon.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            }
        }

        var iconColor: Color {
            switch self {
            case .error: return .red
            case .warning: return .yellow
            case .info: return .blue
            case .success: return .green
            }
        }
    }

    var body: some View {
        ZStack {
            HStack(alignment: .center, spacing: 12) {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 50, height: 50)
                        .cornerRadius(10)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .fontWeight(.bold)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Text(message)
                        .font(.system(size: 11))
                        .fontWeight(.semibold)
                        .opacity(0.9)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
            }
            .padding(12)
            .frame(height: 60)
            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .frame(width: 16, height: 16)
                }
                Spacer()
            }
            .padding(8)
        }
        .frame(minWidth: 320, maxWidth: 420)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.95))
        )
        .overlay(
            VStack {
                Spacer()
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.6))
                        .frame(width: geometry.size.width * max(0, progress), height: 2)
                        .animation(.linear(duration: 0.1), value: progress)
                }
                .frame(height: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        )
        .onAppear {
            startProgressTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
        .onTapGesture {
            if let onTap = onTap {
                onTap()
                onClose()
            }
        }
    }
    
    private func startProgressTimer() {
        let updateInterval: TimeInterval = 0.1
        let totalSteps = duration / updateInterval
        let stepDecrement = 1.0 / totalSteps
        
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { _ in
            if progress > 0 {
                progress = max(0, progress - stepDecrement)
            } else {
                timer?.invalidate()
                timer = nil
            }
        }
    }
}
