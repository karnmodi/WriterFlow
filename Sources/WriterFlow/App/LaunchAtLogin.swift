import Foundation
import ServiceManagement

@MainActor
enum LaunchAtLogin {
    static func apply(enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status == .enabled { return }
                try service.register()
                Log.app.info("Launch-at-login registered")
            } else {
                if service.status == .notRegistered { return }
                try service.unregister()
                Log.app.info("Launch-at-login unregistered")
            }
        } catch {
            Log.app.error("Launch-at-login toggle failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
