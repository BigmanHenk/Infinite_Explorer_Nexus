import SwiftUI
import UIKit

/// What's on: day by day for the next weeks, plus everything coming up later in the year.
struct EventsView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var store: Store
    @EnvironmentObject var base: BaseStore
    @EnvironmentObject var location: LocationModel
    @State private var mode = 0           // 0 = by day, 1 = coming up
    @State private var day = Day.start(Date())
    @State private var category: String? = nil
    @State private var town: String? = nil
    @State private var search = ""

    private var categories: [String] { Array(Set(store.events.map(\.category))).sorted() }
    private var towns: [String] { Array(Set(store.events.map(\.town))).sorted() }

    private func keep(_ e: EventItem) -> Bool {
        if let category, e.category != category { return false }
        if let town, e.town != town { return false }
        if !base.within(e.coordinate, location) { return false }
        let q = search.lowercased()
        if !q.isEmpty, !(e.title.lowercased().contains(q) || e.venue.lowercased().contains(q) || e.description.lowercased().contains(q)) {
            return false
        }
        return true
    }

    var body: some View {
        List {
            Section {
                Picker("", selection: $mode) {
                    Text("Day by day").tag(0)
                    Text("Coming up").tag(1)
                }
                .pickerStyle(.segmented)
                BaseChip()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Menu {
                            Button("All types") { category = nil }
                            ForEach(categories, id: \.self) { c in Button(c.capitalized) { category = c } }
                        } label: { ChipLabel(text: category?.capitalized ?? "All types", symbol: "line.3.horizontal.decrease", on: category != nil) }
                        Menu {
                            Button("All towns") { town = nil }
                            ForEach(towns, id: \.self) { t in Button(t) { town = t } }
                        } label: { ChipLabel(text: town ?? "All towns", symbol: "mappin", on: town != nil) }
                    }
                }
                if mode == 0 { dayStrip }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

            if mode == 0 { dayList } else { upcomingList }
        }
        .themedList()
        .searchable(text: $search, prompt: "Search events")
        .navigationTitle("What's on")
    }

    private var dayStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(0..<60, id: \.self) { i in
                        let d = Day.add(i, to: Day.start(Date()))
                        let on = Day.key(d) == Day.key(day)
                        let n = EventCalendar.on(d, events: store.events).filter { !$0.ongoing && keep($0.event) }.count
                        Button { day = d } label: {
                            VStack(spacing: 2) {
                                Text(i == 0 ? "Today" : Day.weekdayShort(d)).font(.caption2.weight(.semibold))
                                Text(Day.format(d, "d")).font(.headline)
                                Circle().fill(n > 0 ? (on ? theme.t.onPrimary : theme.t.primary) : .clear).frame(width: 5, height: 5)
                            }
                            .frame(width: 48, height: 58)
                            .foregroundStyle(on ? theme.t.onPrimary : theme.t.onSurfaceVariant)
                            .background(on ? theme.t.primary : theme.t.surface, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .id(i)
                    }
                }
            }
        }
    }

    @ViewBuilder private var dayList: some View {
        let occ = EventCalendar.on(day, events: store.events).filter { keep($0.event) }
        let oneOff = occ.filter { !$0.ongoing }
        let ongoing = occ.filter { $0.ongoing }
        Section {
            if oneOff.isEmpty {
                Text("Nothing dated on this day - see the exhibitions and regulars below.")
                    .font(.subheadline).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.7))
                    .listRowBackground(theme.t.surface)
            }
            ForEach(oneOff) { o in
                NavigationLink(value: o.event) { EventRow(event: o.event, showDate: false) }
                    .listRowBackground(theme.t.surface)
            }
        } header: { SectionHead(Day.format(day, "EEEE d MMMM")) }
        if !ongoing.isEmpty {
            Section {
                ForEach(ongoing) { o in
                    NavigationLink(value: o.event) { EventRow(event: o.event, showDate: true) }
                        .listRowBackground(theme.t.surface)
                }
            } header: { SectionHead("Also on - exhibitions, cinemas, long runs") }
        }
    }

    @ViewBuilder private var upcomingList: some View {
        let today = Day.start(Date())
        let dated = store.events.filter { $0.recurrence == nil && keep($0) && ($0.endDate ?? $0.startDate ?? "") >= Day.key(today) }
            .sorted { ($0.startDate ?? "") < ($1.startDate ?? "") }
        let byMonth = Dictionary(grouping: dated) { e -> String in
            let s = max(e.startDate ?? "", Day.key(today))
            return String(s.prefix(7))
        }
        ForEach(byMonth.keys.sorted(), id: \.self) { m in
            Section {
                ForEach(byMonth[m] ?? []) { e in
                    NavigationLink(value: e) { EventRow(event: e, showDate: true) }
                        .listRowBackground(theme.t.surface)
                }
            } header: { SectionHead(Day.date(m + "-01").map { Day.format($0, "MMMM yyyy") } ?? m) }
        }
        let regular = store.events.filter { $0.recurrence != nil && keep($0) }
        if !regular.isEmpty {
            Section {
                ForEach(regular) { e in
                    NavigationLink(value: e) { EventRow(event: e, showDate: true) }
                        .listRowBackground(theme.t.surface)
                }
            } header: { SectionHead("Regulars - markets, parkrun, cinemas") }
        }
    }
}

struct EventDetailView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var router: Router
    let event: EventItem
    @State private var planning: PlanTarget?
    @State private var fullMap = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    CatIcon(symbol: Cat.eventSymbol(event.category), color: theme.t.primary, size: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.title).font(.title2.weight(.bold)).foregroundStyle(theme.t.onBackground)
                        Text("\(event.venue) · \(event.town)").font(.subheadline).foregroundStyle(theme.t.primary)
                    }
                }
                if event.isExpected {
                    Label("Date expected from previous years - the organiser has not confirmed it yet.", systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.orange)
                }
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        InfoRow(symbol: "calendar", title: "When", value: EventCalendar.dateText(event))
                        if let next = EventCalendar.next(event) {
                            InfoRow(symbol: "arrow.forward.circle", title: "Next", value: Day.format(next, "EEEE d MMMM"))
                        }
                        InfoRow(symbol: "clock", title: "Time", value: event.timeText)
                        InfoRow(symbol: "sterlingsign.circle", title: "Price", value: event.price)
                        InfoRow(symbol: "ticket", title: "Booking", value: event.booking)
                    }
                }
                PlanButton {
                    var days: Set<String> = []
                    var d = Day.start(Date())
                    for _ in 0..<21 {
                        if EventCalendar.occurs(event, on: d) != nil { days.insert(Day.key(d)) }
                        d = Day.add(1, to: d)
                    }
                    planning = PlanTarget(kind: .event, refID: event.id, title: event.title, time: event.startTime, days: days)
                }
                if let c = event.coordinate { TravelCard(to: c, name: event.venue) }
                Card {
                    Text(event.description).foregroundStyle(theme.t.onBackground)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                if let c = event.coordinate {
                    OfflineMapView(events: [event], accent: UIColor(theme.t.primary), focus: MapFocus(center: c, meters: 900))
                        .frame(height: 170)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .allowsHitTesting(false)
                        .overlay(alignment: .topTrailing) { ExpandMapButton { fullMap = true } }
                        .overlay(alignment: .bottomTrailing) {
                            Button { router.showOnMap([CLLocationCoordinate2DBox(c)]) } label: {
                                Label("Open map", systemImage: "map").font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                            .padding(8)
                        }
                }
                Card {
                    MoreInfoLinks(name: event.title, town: event.town, website: event.website, sources: event.sources)
                }
                Card {
                    LinksBlock(website: nil, phone: nil, directions: nil, sources: event.sources, verified: event.verified)
                }
            }
            .padding(16)
        }
        .background(theme.t.background)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $planning) { AddToPlanSheet(target: $0) }
        .fullScreenCover(isPresented: $fullMap) {
            FullScreenMap(title: event.venue, events: [event],
                          focus: MapFocus(center: event.coordinate ?? Sun.birchington, meters: 900))
        }
    }
}
