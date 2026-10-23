import SwiftUI

@main
struct SpeedAnnounceApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var monitor: SpeedMonitor
    @StateObject private var tripLog: TripLog

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        let tripLog = TripLog()
        _tripLog = StateObject(wrappedValue: tripLog)
        let monitor = SpeedMonitor(settings: settings, tripLog: tripLog)
        // `-demo normal|speeding` shows sample values for screenshots.
        switch UserDefaults.standard.string(forKey: "demo") {
        case "normal": monitor.showDemo(limit: 80, speed: 76, road: "Køgevej")
        case "speeding": monitor.showDemo(limit: 50, speed: 63, road: "Vesterbrogade")
        default: break
        }
        _monitor = StateObject(wrappedValue: monitor)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(monitor)
                .environmentObject(tripLog)
        }
    }
}
