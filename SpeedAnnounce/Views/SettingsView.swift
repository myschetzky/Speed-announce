import SwiftUI

struct SettingsView: View {
    private var authorizationText: String {
        switch monitor.authorizationStatus {
        case .authorizedAlways: return "altid"
        case .authorizedWhenInUse: return "når appen bruges"
        case .denied: return "afvist"
        case .restricted: return "begrænset"
        case .notDetermined: return "ikke spurgt"
        @unknown default: return "ukendt"
        }
    }

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
                    if settings.source == .here {
                        SecureField("HERE API-nøgle", text: $settings.hereAPIKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Stepper("Maks. \(settings.hereMonthlyLimit) kald/md",
                                value: $settings.hereMonthlyLimit, in: 500...100_000, step: 500)
                        LabeledContent("Brugt denne måned", value: "\(monitor.hereRequestsThisMonth)")
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
                    Text("HERE er samme kortdata som Saphe bruger og dækker alle danske veje. Appen henter kun en ny rute ved sving eller efter 1–2 km, og bruger OpenStreetMap hvis HERE fejler eller kvoten er brugt. Saphe har ingen offentlig API.")
                }

                Section {
                    let d = monitor.diagnostics
                    LabeledContent("Kører", value: monitor.isRunning ? "ja" : "nej")
                    LabeledContent("Lokalitet", value: authorizationText)
                    LabeledContent("GPS-positioner", value: "\(d.locationsReceived)")
                    LabeledContent("Seneste position", value: d.lastFix.map { "\(Int(Date().timeIntervalSince($0))) sek siden" } ?? "–")
                    LabeledContent("Nøjagtighed", value: d.lastAccuracy.map { "±\(Int($0)) m" } ?? "–")
                    LabeledContent("Opslag", value: "\(d.lookupsFinished) af \(d.lookupsStarted)")
                    LabeledContent("Seneste opslag", value: d.lastLookupDuration.map { String(format: "%.1f sek", $0) } ?? "–")
                    LabeledContent("Resultat", value: d.lastLookupResult ?? "–")
                    if settings.source == .here {
                        LabeledContent("HERE", value: d.hereStatus ?? "–")
                        LabeledContent("HERE-nøgle", value: settings.hereAPIKey.isEmpty ? "mangler" : "indtastet")
                    }
                    if let error = d.lastError {
                        Text("Fejl: \(error)").font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("Diagnose")
                } footer: {
                    Text("Tag et skærmbillede af denne sektion, hvis appen ikke finder fartgrænsen.")
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
