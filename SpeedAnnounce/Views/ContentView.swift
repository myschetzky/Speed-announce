import CoreLocation
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var monitor: SpeedMonitor
    @EnvironmentObject private var settings: AppSettings
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()
                SpeedSignView(limit: monitor.currentLimit, isSpeeding: monitor.isSpeeding)
                    .frame(width: 220, height: 220)

                VStack(spacing: 6) {
                    Text(speedText)
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(monitor.isSpeeding ? Color.red : Color.primary)
                    Text("km/t")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    if let road = monitor.roadName {
                        Text(road).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let status = monitor.statusMessage {
                        Text(status).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
                    }
                    if monitor.authorizationStatus == .denied || monitor.authorizationStatus == .restricted {
                        Text("Giv adgang til lokalitet i Indstillinger for at bruge appen.")
                            .font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                    }
                }
                Spacer()

                Button {
                    monitor.isRunning ? monitor.stop() : monitor.start()
                } label: {
                    Text(monitor.isRunning ? "Stop" : "Start kørsel")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(monitor.isRunning ? Color.red : Color.accentColor)

                Text("Data: \(attribution)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Fartgrænse")
            .toolbar {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Indstillinger")
            }
            .sheet(isPresented: $showSettings) {
                SettingsView().environmentObject(settings).environmentObject(monitor)
            }
        }
    }

    private var attribution: String {
        if let source = monitor.limitSource {
            switch source {
            case "HERE": return "© HERE"
            case "Saphe": return "Saphe"
            default: return "© OpenStreetMap-bidragydere"
            }
        }
        switch settings.source {
        case .here, .hereOnly: return "© HERE"
        case .saphe: return "Saphe"
        case .openStreetMap: return "© OpenStreetMap-bidragydere"
        }
    }

    private var speedText: String {
        guard let speed = monitor.speedKmh else { return "–" }
        return String(Int(speed.rounded()))
    }
}

struct SpeedSignView: View {
    let limit: AnnouncementPolicy.Limit?
    let isSpeeding: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle().fill(.white)
                Circle().strokeBorder(.red, lineWidth: size * 0.12)
                label(size: size)
            }
            .scaleEffect(isSpeeding ? 1.05 : 1)
            .shadow(color: isSpeeding ? .red.opacity(0.7) : .black.opacity(0.15), radius: isSpeeding ? 24 : 8)
            .animation(isSpeeding ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true) : .default, value: isSpeeding)
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private func label(size: CGFloat) -> some View {
        switch limit {
        case .kmh(let value):
            Text("\(value)")
                .font(.system(size: size * (value >= 100 ? 0.34 : 0.42), weight: .heavy, design: .rounded))
                .foregroundStyle(.black)
        case .unlimited:
            Image(systemName: "line.diagonal")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(.gray)
        case nil:
            Text("?")
                .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
                .foregroundStyle(.gray)
        }
    }

    private var accessibilityText: String {
        switch limit {
        case .kmh(let value): return "Fartgrænse \(value)"
        case .unlimited: return "Ingen fartgrænse"
        case nil: return "Ukendt fartgrænse"
        }
    }
}
