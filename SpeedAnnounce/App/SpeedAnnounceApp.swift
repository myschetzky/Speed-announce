import SwiftUI

@main
struct SpeedAnnounceApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var monitor: SpeedMonitor

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _monitor = StateObject(wrappedValue: SpeedMonitor(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(monitor)
        }
    }
}
