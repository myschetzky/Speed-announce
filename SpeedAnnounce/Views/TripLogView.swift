import SwiftUI

struct TripLogView: View {
    @EnvironmentObject private var log: TripLog
    @State private var confirmClear = false

    var body: some View {
        List {
            if log.entries.isEmpty {
                Text("Ingen ture endnu. Loggen fyldes, når du trykker Start kørsel.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(log.trips.enumerated()), id: \.offset) { _, trip in
                Section(header: Text(trip.first.map { Self.dayFormatter.string(from: $0.date) } ?? "")) {
                    ForEach(trip.reversed()) { entry in
                        row(entry)
                    }
                }
            }
        }
        .navigationTitle("Turlog")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: log.exportText) { Image(systemName: "square.and.arrow.up") }
                    .disabled(log.entries.isEmpty)
                Button(role: .destructive) { confirmClear = true } label: { Image(systemName: "trash") }
                    .disabled(log.entries.isEmpty)
            }
        }
        .confirmationDialog("Slet hele turloggen?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Slet", role: .destructive) { log.clear() }
        }
    }

    @ViewBuilder
    private func row(_ entry: TripLogEntry) -> some View {
        let content = HStack(alignment: .top) {
            Text(Self.timeFormatter.string(from: entry.date))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .foregroundStyle(entry.kind == .speeding ? Color.red : Color.primary)
                let details = [entry.road, entry.speedKmh.map { "\($0) km/t" }, entry.source].compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        if let url = entry.mapURL {
            Link(destination: url) { content }.tint(.primary)
        } else {
            content
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "da_DK")
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
