import SwiftUI

/// Home: today's sun, tides, what's on, your plan, and the ways into everything else.
struct TodayView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var store: Store
    @EnvironmentObject var planner: PlannerStore
    @EnvironmentObject var router: Router
    @EnvironmentObject var weather: WeatherStore
    @State private var now = Date()
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        let today = Day.start(now)
        let sun = Sun.times(today)
        let occ = EventCalendar.on(today, events: store.events)
        let plan = planner.items(on: today)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(sun)
                weatherCard
                if let tides = store.tides, tides.covers(now) { tideCard(tides, today) }
                planCard(plan)
                eventsCard(occ.filter { !$0.ongoing }, ongoing: occ.filter { $0.ongoing }.count)
                weekendCard()
                shortcuts
                Text("All of this is stored on your phone and works without signal.")
                    .font(.caption).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.6))
                    .frame(maxWidth: .infinity).padding(.top, 4)
            }
            .padding(16)
        }
        .background(theme.t.background)
        .navigationTitle(Day.format(now, "EEEE d MMMM"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Screen.settings) { Image(systemName: "gearshape") }
            }
        }
        .explorerDestinations()
        .onReceive(timer) { now = $0 }
        .refreshable { await weather.refresh(force: true) }
    }

    @ViewBuilder private var weatherCard: some View {
        if weather.days.isEmpty {
            Card {
                Label("Weather", systemImage: "cloud.sun").cardTitle(theme)
                Text(weather.loading ? "Getting the Met Office forecast…" : "No forecast yet - it downloads automatically when you have signal (pull down to retry).")
                    .font(.subheadline).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.8))
            }
        } else {
            Card {
                HStack {
                    Label("Met Office forecast", systemImage: "cloud.sun").cardTitle(theme)
                    Spacer()
                    if let a = weather.ageText { Text(a).font(.caption2).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.6)) }
                }
                if let w = weather.forecast(for: now) {
                    HStack(spacing: 12) {
                        Image(systemName: w.symbol).symbolRenderingMode(.multicolor).font(.system(size: 36))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(w.text) · \(Int(w.tMax.rounded()))° / \(Int(w.tMin.rounded()))°").font(.headline).foregroundStyle(theme.t.onBackground)
                            Text(String(format: "Rain %.1f mm · wind %d mph, gusts %d · sun %.0f h", w.rainMM, Int(w.windMph.rounded()), Int(w.gustMph.rounded()), w.sunHours))
                                .font(.caption).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.8))
                            Text(w.advice).font(.caption.weight(.semibold)).foregroundStyle(w.isWet || w.isWindy ? .orange : theme.t.primary)
                        }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(weather.days.filter { $0.day > Day.key(now) }, id: \.day) { w in
                            VStack(spacing: 3) {
                                Text(Day.date(w.day).map(Day.weekdayShort) ?? "").font(.caption2.weight(.semibold))
                                Image(systemName: w.symbol).symbolRenderingMode(.multicolor)
                                Text("\(Int(w.tMax.rounded()))°").font(.caption.weight(.semibold))
                                if w.rainMM >= 0.5 { Text(String(format: "%.0f mm", w.rainMM)).font(.system(size: 9)).foregroundStyle(Color(hex: 0x5BB8EA)) }
                            }
                            .frame(width: 46).padding(.vertical, 6)
                            .background(theme.t.surfaceVariant.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(theme.t.onBackground)
                        }
                    }
                }
            }
        }
    }

    private func header(_ sun: Sun.DayTimes) -> some View {
        Card {
            HStack(spacing: 0) {
                sunCell("sunrise.fill", "Sunrise", sun.sunrise)
                sunCell("sun.max.fill", "Noon", sun.solarNoon)
                sunCell("sunset.fill", "Sunset", sun.sunset)
                let moon = Sun.moonText(now)
                VStack(spacing: 4) {
                    Image(systemName: moon.symbol).font(.title3).foregroundStyle(theme.t.primary)
                    Text(moon.name).font(.caption2).multilineTextAlignment(.center)
                        .foregroundStyle(theme.t.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity)
            }
            if let g = sun.eveningGolden {
                Divider().overlay(theme.t.outline)
                HStack {
                    Image(systemName: "camera.aperture").foregroundStyle(theme.t.primary)
                    Text("Golden hour \(Day.time(g.0))–\(Day.time(g.1))")
                    if let az = sun.sunsetAzimuth {
                        Text("· sun sets \(Sun.compass(az))").foregroundStyle(theme.t.onSurfaceVariant.opacity(0.7))
                    }
                }
                .font(.footnote)
                .foregroundStyle(theme.t.onBackground)
            }
        }
    }

    private func sunCell(_ symbol: String, _ title: String, _ t: Date?) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).symbolRenderingMode(.multicolor).font(.title3)
            Text(t.map(Day.time) ?? "–").font(.headline.monospacedDigit()).foregroundStyle(theme.t.onBackground)
            Text(title).font(.caption2).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }

    private func tideCard(_ tides: TideTable, _ today: Date) -> some View {
        NavigationLink(value: Screen.tides) {
            Card {
                HStack {
                    Label("Tides · \(tides.station)", systemImage: "water.waves").cardTitle(theme)
                    Spacer()
                    if let h = tides.height(at: now), let rising = tides.rising(at: now) {
                        Text(String(format: "%.1f m %@", h, rising ? "↑ rising" : "↓ falling"))
                            .font(.caption.weight(.semibold)).foregroundStyle(theme.t.primary)
                    }
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.5))
                }
                TideChart(day: today, tides: tides, height: 120)
                TideRow(extremes: tides.extremes(on: today))
            }
        }
        .buttonStyle(.plain)
    }

    private func planCard(_ plan: [PlanItem]) -> some View {
        Card {
            HStack {
                Label("My plan today", systemImage: "calendar").cardTitle(theme)
                Spacer()
                Button("Week") { router.tab = .planner }.font(.subheadline)
            }
            if plan.isEmpty {
                Text("Nothing planned yet. Open My week and tap Suggest, or add things from Explore, Walks and What's on.")
                    .font(.subheadline).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.8))
            }
            ForEach(plan) { item in
                PlanRow(item: item)
            }
        }
    }

    private func eventsCard(_ list: [Occurrence], ongoing: Int) -> some View {
        Card {
            NavigationLink(value: Screen.whatsOn) {
                HStack {
                    Label("What's on today", systemImage: "party.popper").cardTitle(theme)
                    Spacer()
                    Text("All").font(.subheadline).foregroundStyle(theme.t.primary)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.5))
                }
            }
            .buttonStyle(.plain)
            if list.isEmpty {
                Text("No one-off events today.").font(.subheadline).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.8))
            }
            ForEach(list.prefix(5)) { o in
                NavigationLink(value: o.event) { EventRow(event: o.event, showDate: false) }.buttonStyle(.plain)
            }
            if ongoing > 0 {
                NavigationLink(value: Screen.whatsOn) {
                    Text("+ \(ongoing) exhibitions, cinemas and longer runs").font(.caption).foregroundStyle(theme.t.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func weekendCard() -> some View {
        let today = Day.start(now)
        let wd = Day.cal.component(.weekday, from: today)   // 1 Sun ... 7 Sat
        let toSat = (7 - wd + 7) % 7
        let sat = Day.add(toSat == 0 && wd != 7 ? 7 : toSat, to: today)
        let days = wd == 1 ? [today] : [sat, Day.add(1, to: sat)]
        let items = days.flatMap { d in EventCalendar.on(d, events: store.events).filter { !$0.ongoing } }
        if !items.isEmpty && wd != 7 && wd != 1 {
            Card {
                Label("This weekend", systemImage: "sparkles").cardTitle(theme)
                ForEach(items.prefix(5)) { o in
                    NavigationLink(value: o.event) { EventRow(event: o.event, showDate: true, onDay: Day.date(o.day)) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private var shortcuts: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            shortcut("What's on", "party.popper.fill", Color(hex: 0xE5598F), .whatsOn)
            shortcut("Tide tables", "water.waves", Color(hex: 0x2E9BD6), .tides)
            shortcut("Wildlife, photo spots & views", "binoculars.fill", Color(hex: 0xD9483B), .photo)
            shortcut("Practical info", "info.circle.fill", Color(hex: 0x6E7781), .info)
            shortcut("Tour builder (pub crawl…)", "map.fill", Color(hex: 0xB8862E), .tour)
        }
    }

    private func shortcut(_ title: String, _ symbol: String, _ color: Color, _ s: Screen) -> some View {
        NavigationLink(value: s) {
            HStack(spacing: 10) {
                CatIcon(symbol: symbol, color: color, size: 34)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(theme.t.onBackground)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(theme.t.surface, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

/// One event in a list.
struct EventRow: View {
    @EnvironmentObject var theme: ThemeStore
    let event: EventItem
    var showDate = true
    var onDay: Date? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CatIcon(symbol: Cat.eventSymbol(event.category), color: theme.t.primary.opacity(0.85), size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).font(.subheadline.weight(.semibold)).foregroundStyle(theme.t.onBackground)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    if showDate {
                        if let onDay { Text(Day.format(onDay, "EEE d MMM")) } else { Text(EventCalendar.dateText(event)) }
                    }
                    if let t = event.timeText { Text(showDate ? "· \(t)" : t) }
                }
                .font(.caption).foregroundStyle(theme.t.primary)
                Text("\(event.venue) · \(event.town)").font(.caption).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.75))
                if event.isExpected {
                    Text("Date expected - not yet confirmed").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// One planner item (used on Today and in My week).
struct PlanRow: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var planner: PlannerStore
    @EnvironmentObject var store: Store
    let item: PlanItem
    var body: some View {
        HStack(spacing: 10) {
            Button { planner.toggleDone(item) } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(item.done ? theme.t.primary : theme.t.onSurfaceVariant.opacity(0.5))
            }
            .buttonStyle(.plain)
            link
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var link: some View {
        switch item.kind {
        case .place:
            if let p = item.refID.flatMap(store.place) { NavigationLink(value: p) { label(Cat.symbol(p.category)) }.buttonStyle(.plain) } else { label("mappin") }
        case .event:
            if let e = item.refID.flatMap(store.event) { NavigationLink(value: e) { label(Cat.eventSymbol(e.category)) }.buttonStyle(.plain) } else { label("calendar") }
        case .walk:
            if let w = item.refID.flatMap(store.walk) { NavigationLink(value: w) { label("figure.walk") }.buttonStyle(.plain) } else { label("figure.walk") }
        case .note:
            label("note.text")
        }
    }

    private func label(_ symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(theme.t.primary).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline.weight(.medium))
                    .strikethrough(item.done)
                    .foregroundStyle(theme.t.onBackground.opacity(item.done ? 0.5 : 1))
                    .multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    Text(item.time ?? item.slot.label)
                    if !item.note.isEmpty { Text("· \(item.note)").lineLimit(2) }
                }
                .font(.caption).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.75))
            }
        }
        .contentShape(Rectangle())
    }
}
