import Foundation
import AppKit

@MainActor
class LicenseViewModel: ObservableObject {
    enum LicenseState: Equatable {
        case licensed
    }
    
    @Published private(set) var licenseState: LicenseState = .licensed
    @Published var licenseKey: String = ""
    @Published var isValidating = false
    @Published var validationMessage: String?
    @Published private(set) var activationsLimit: Int = 0
    
    init() {
        // App is always Pro - no license validation needed
        self.licenseState = .licensed
    }
    
    var canUseApp: Bool {
        return true // Always allow app usage
    }
    
    func openPurchaseLink() {
        // No-op - purchase not needed
    }
    
    func validateLicense() async {
        // No-op - no validation needed
        licenseState = .licensed
        validationMessage = "VoiceInk Pro - Full Version"
    }
    
    func removeLicense() {
        // No-op - license can't be removed as app is always Pro
        licenseState = .licensed
    }
}

// Keep extension for compatibility but notification is not needed
extension Notification.Name {
    static let licenseStatusChanged = Notification.Name("licenseStatusChanged")
}
