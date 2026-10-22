import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var monitor: SpeedMonitor
    @Environment(\.dismiss) private var dismiss

    private let intervals = [0, 1, 2, 5, 10, 15]

    var body: some View {
        NavigationStack {
            Form {
                Section("Annoncering") {
                    Toggle("Annoncér når grænsen ændres", isOn: $settings.announceOnChange)
                    Picker("Gentag grænsen", selection: $settings.periodicIntervalMinutes) {
                        ForEach(intervals, id: \.self) { minutes in
                            Text(minutes == 0 ? "Aldrig" : "Hvert \(minutes). min").tag(minutes)
                        }
                    }
                    VStack(alignment: .leading) {
                        Text("Taletempo")
                        Slider(value: $settings.speechRate, in: 0.35...0.6)
                    }
                    Button("Afprøv annoncering") { monitor.testAnnouncement() }
                }

                Section {
                    Toggle("Advar ved for høj fart", isOn: $settings.warnWhenSpeeding)
                    Stepper("Tolerance: \(settings.speedingToleranceKmh) km/t",
                            value: $settings.speedingToleranceKmh, in: 0...15)
                    Stepper("Gentag advarsel: \(settings.warningRepeatSeconds) sek",
                            value: $settings.warningRepeatSeconds, in: 5...120, step: 5)
                    Toggle("Advarselstone", isOn: $settings.playWarningTone)
                    Button("Afprøv advarsel") { monitor.testWarning() }
                } header: {
                    Text("Advarsel")
                } footer: {
                    Text("Advarslen gives når farten er over grænsen plus tolerancen i mindst 2 sekunder.")
                }

                Section {
                    Picker("Kilde", selection: $settings.source) {
                        ForEach(SpeedLimitSourceKind.allCases) { Text($0.title).tag($0) }
                    }
                    if settings.source == .saphe {
                        TextField("Endpoint (https://…)", text: $settings.sapheEndpoint)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                        SecureField("API-nøgle", text: $settings.sapheAPIKey)
                    }
                } header: {
                    Text("Datakilde")
                } footer: {
                    Text("Saphe har ingen offentlig API. Saphe-kilden virker først, når Saphe giver adgang. OpenStreetMap er gratis og dækker det meste af Danmark, men kan have huller eller forældede skilte.")
                }

                Section {
                    Text("Appen er et hjælpemiddel. Følg altid den skiltede fartgrænse.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Indstillinger")
            .toolbar {
                Button("Færdig") { dismiss() }
            }
        }
    }
}
