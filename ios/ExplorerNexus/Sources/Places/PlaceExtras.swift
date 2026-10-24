import Combine
import SwiftUI

/// The opening-times filter: a day and a time range; "whole range" or "at some point".
@MainActor
final class OpenFilter: ObservableObject {
    @Published var on = false
    @Published var day = Day.start(Date())
    @Published var from = 10 * 60      // minutes
    @Published var to = 14 * 60
    @Published var whole = false
    @Published var includeUnknown = false

    func matches(_ p: Place) -> Bool {
        p.hours.isOpen(on: day, from: from, to: to, whole: whole) ?? includeUnknown
    }

    var label: String {
        guard on else { return "Opening times" }
        let d = Day.key(day) == Day.key(Date()) ? "Today" : Day.format(day, "EEE d")
        return "\(d) \(OpenFilter.hm(from))–\(OpenFilter.hm(to))"
    }

    static func hm(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }
}

struct OpenFilterSheet: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var filter: OpenFilter

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Only show places open then", isOn: $filter.on)
                }
                .listRowBackground(theme.t.surface)
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(0..<14, id: \.self) { i in
                                let d = Day.add(i, to: Day.start(Date()))
                                let sel = Day.key(d) == Day.key(filter.day)
                                Button { filter.day = d; filter.on = true } label: {
                                    VStack(spacing: 2) {
                                        Text(i == 0 ? "Today" : Day.weekdayShort(d)).font(.caption2.weight(.semibold))
                                        Text(Day.format(d, "d")).font(.headline)
                                    }
                                    .frame(width: 50, height: 52)
                                    .foregroundStyle(sel ? theme.t.onPrimary : theme.t.onSurfaceVariant)
                                    .background(sel ? theme.t.primary : theme.t.surfaceVariant, in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } header: { SectionHead("Day") }
                .listRowBackground(theme.t.surface)
                Section {
                    HStack {
                        Text("From \(OpenFilter.hm(filter.from))").font(.headline.monospacedDigit())
                        Spacer()
                        Text("to \(OpenFilter.hm(filter.to))").font(.headline.monospacedDigit())
                    }
                    .foregroundStyle(theme.t.primary)
                    Slider(value: Binding(get: { Double(filter.from) }, set: { filter.from = min(Int($0), filter.to - 30); filter.on = true }),
                           in: 0...1410, step: 30) { Text("From") }
                    Slider(value: Binding(get: { Double(filter.to) }, set: { filter.to = max(Int($0), filter.from + 30); filter.on = true }),
                           in: 30...1440, step: 30) { Text("To") }
                    HStack(spacing: 8) {
                        quick("Morning", 9 * 60, 12 * 60)
                        quick("Lunch", 12 * 60, 14 * 60)
                        quick("Afternoon", 14 * 60, 17 * 60)
                        quick("Evening", 18 * 60, 22 * 60)
                    }
                    Picker("Open", selection: $filter.whole) {
                        Text("At some point").tag(false)
                        Text("The whole time").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Include places with unknown hours", isOn: $filter.includeUnknown)
                } header: { SectionHead("Time range") }
                .listRowBackground(theme.t.surface)
                Section {
                    let n = store.places.filter { filter.matches($0) }.count
                    Text("\(n) places match (before the other filters).").font(.caption).foregroundStyle(.secondary)
                    Text("Beaches, viewpoints and walks count as always open. Hours come from the venues' published times - bank holidays and events can change them.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .listRowBackground(theme.t.surface)
            }
            .themedList()
            .navigationTitle("Opening times")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func quick(_ title: String, _ a: Int, _ b: Int) -> some View {
        Button(title) { filter.from = a; filter.to = b; filter.on = true }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
    }
}

/// On a place page: hours today and this week, food hygiene, menu, reviews.
struct PlaceExtras: View {
    @EnvironmentObject var theme: ThemeStore
    let place: Place

    var body: some View {
        let h = place.hours
        if h.known || place.hygiene != nil || place.menuURL != nil || place.isEatDrink || place.drink != nil {
            Card {
                if h.known {
                    HStack {
                        Label("Opening times", systemImage: "clock").cardTitle(theme)
                        Spacer()
                        if let o = h.openNow() {
                            Text(o ? "OPEN NOW" : "CLOSED NOW").font(.caption.weight(.bold))
                                .foregroundStyle(o ? Color(hex: 0x3E9B4F) : .orange)
                        }
                    }
                    ForEach(0..<7, id: \.self) { i in
                        let d = Day.add(i, to: Day.start(Date()))
                        HStack {
                            Text(i == 0 ? "Today" : Day.format(d, "EEEE")).frame(width: 96, alignment: .leading)
                            Text(h.text(on: d) ?? "–")
                            Spacer()
                        }
                        .font(.caption.weight(i == 0 ? .semibold : .regular))
                        .foregroundStyle(theme.t.onBackground)
                    }
                }
                if let r = place.hygiene {
                    Divider().overlay(theme.t.outline)
                    HStack(spacing: 10) {
                        Text(r).font(.title2.weight(.heavy)).foregroundStyle(.white)
                            .frame(width: 40, height: 40).background(hygieneColour(r), in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Food hygiene rating \(r) of 5").font(.subheadline.weight(.semibold)).foregroundStyle(theme.t.onBackground)
                            Text("Food Standards Agency\(place.hygieneDate.map { " · inspected \($0)" } ?? "")")
                                .font(.caption).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.75))
                        }
                        Spacer()
                        if let u = place.hygieneURL.flatMap(URL.init(string:)) { Link(destination: u) { Image(systemName: "info.circle") } }
                    }
                }
                if let d = place.drink, !d.badges.isEmpty || d.notes != nil {
                    Divider().overlay(theme.t.outline)
                    if !d.badges.isEmpty {
                        Text(d.badges.joined(separator: " · ")).font(.caption.weight(.semibold)).foregroundStyle(theme.t.primary)
                    }
                    if let n = d.notes { Text(n).font(.caption).foregroundStyle(theme.t.onBackground) }
                    if let a = d.awards, !a.isEmpty {
                        Label(a.joined(separator: "; "), systemImage: "rosette").font(.caption).foregroundStyle(theme.t.onSurfaceVariant)
                    }
                }
                if let m = place.menuURL, let u = URL(string: m) {
                    Link(destination: u) {
                        Label("Menu", systemImage: "menucard").font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .foregroundStyle(theme.t.onPrimary).background(theme.t.primary, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                HStack(spacing: 10) {
                    reviewLink("TripAdvisor reviews", "https://www.tripadvisor.co.uk/Search?q=")
                    reviewLink("Google reviews", "https://www.google.com/maps/search/")
                }
            }
        }
    }

    private func reviewLink(_ title: String, _ base: String) -> some View {
        let q = "\(place.name) \(place.town)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return Link(destination: URL(string: base + q)!) {
            Label(title, systemImage: "star.bubble").font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(theme.t.surfaceVariant, in: RoundedRectangle(cornerRadius: 10))
        }
        .tint(theme.t.primary)
    }

    private func hygieneColour(_ r: String) -> Color {
        switch Int(r) ?? -1 {
        case 5, 4: return Color(hex: 0x3E9B4F)
        case 3: return Color(hex: 0xC9A12E)
        case 0...2: return Color(hex: 0xD9483B)
        default: return Color(hex: 0x6E7781)
        }
    }
}
