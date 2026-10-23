import SwiftUI

/// Practical information: toilets, parking, stations, health, plus the general facts.
struct InfoView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var store: Store
    var body: some View {
        List {
            Section {
                Link(destination: URL(string: "tel:999")!) { Label("Emergency: 999 (police, ambulance, fire, Coastguard)", systemImage: "phone.fill") }
                Link(destination: URL(string: "tel:111")!) { Label("NHS 111 (urgent, not an emergency)", systemImage: "cross.case.fill") }
            }
            .listRowBackground(theme.t.surface)
            Section {
                ForEach(store.facts) { f in
                    DisclosureGroup(f.topic) {
                        Text(f.text).font(.subheadline).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                }
            } header: { SectionHead("Good to know") }
            .listRowBackground(theme.t.surface)
            Section {
                ForEach(store.places.filter { $0.category == "practical" }) { p in
                    NavigationLink(value: p) { PlaceRow(place: p) }
                }
            } header: { SectionHead("Toilets, parking, stations, health") }
            .listRowBackground(theme.t.surface)
        }
        .themedList()
        .tint(theme.t.primary)
        .navigationTitle("Practical info")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SettingsView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var store: Store
    @EnvironmentObject var weather: WeatherStore
    var body: some View {
        List {
            Section {
                Picker("Theme", selection: $theme.themeID) {
                    ForEach(NexusTheme.all) { t in
                        HStack {
                            Circle().fill(t.primary).frame(width: 14, height: 14)
                            Text(t.name)
                        }
                        .tag(t.id)
                    }
                }
                Toggle("Night red (keeps your eyes dark-adapted)", isOn: $theme.nightRed)
            } header: { SectionHead("Look") }
            .listRowBackground(theme.t.surface)

            Section {
                LabeledContent("Places", value: "\(store.places.count)")
                LabeledContent("Events", value: "\(store.events.count)")
                LabeledContent("Walks", value: "\(store.walks.count)")
                LabeledContent("Photo spots & hides", value: "\(store.photoSpots.count)")
                if let t = store.tides { LabeledContent("Tide tables", value: "to \(t.lastDay)") }
                LabeledContent("Content checked", value: store.meta["built"] ?? "–")
                LabeledContent("Forecast", value: weather.ageText ?? "not yet downloaded")
                Button("Refresh forecast now") { Task { await weather.refresh(force: true) } }
            } header: { SectionHead("On this phone") }
            .listRowBackground(theme.t.surface)

            Section {
                Text("Places, events, walks and photo spots were researched from the organisers', venues' and councils' own pages (each entry lists its sources). Opening times, prices and event dates change - check before you travel, especially dates marked \"expected\".")
                Text("Map data © OpenStreetMap contributors, available under the Open Database Licence (openstreetmap.org/copyright).")
                Text("Tide predictions: computed from Environment Agency tide gauge data (Open Government Licence). Not for navigation.")
                Text("Weather: Met Office UK models via Open-Meteo.com (CC BY 4.0).")
                Text("Plan on the PC: open the Explorer Planner page in a browser, then scan its QR code with the iPhone camera.")
            } header: { SectionHead("Sources & credits") }
            .font(.footnote)
            .listRowBackground(theme.t.surface)
        }
        .themedList()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
