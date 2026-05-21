import SwiftUI

@main
struct ExambroApp: App {
    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    var body: some Scene {
        WindowGroup {
            LoginView()
                .preferredColorScheme(.dark)
        }
    }
}
