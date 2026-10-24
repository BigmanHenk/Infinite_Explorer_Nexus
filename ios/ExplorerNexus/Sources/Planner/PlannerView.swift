import SwiftUI
import UIKit

/// My week: seven day cards with the forecast, tides and sunset, your plan for each part
/// of the day, weather-led suggestions, and sharing to other phones or the PC planner.
struct PlannerView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var store: Store
    @EnvironmentObject var planner: PlannerStore
    @EnvironmentObject var weather: WeatherStore
    @EnvironmentObject var base: BaseStore
    @EnvironmentObject var location: LocationModel
    @State private var editing: PlanItem?
    @State private var confirmClear = false
    @State private var showQR = false
    @State private var showSuggest = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                weekHeader
                HStack { BaseChip(); Spacer() }
                if let e = weather.error { Text(e).font(.caption).foregroundStyle(.orange) }
                ForEach(planner.weekDays, id: \.self) { day in dayCard(day) }
                Text("Suggest fills only empty days. Forecast: Met Office UK models via Open-Meteo, refreshed when you have signal.")
                    .font(.caption2).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.6)).multilineTextAlignment(.center)
            }
            .padding(16)
        }
        .background(theme.t.background)
        .navigationTitle("My week")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showSuggest = true } label: { Label("Suggest", systemImage: "wand.and.stars") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Screen.tour) { Image(systemName: "map") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    let week = planner.weekDays.flatMap { planner.items(on: $0) }
                    ShareLink(item: planner.weekText(store: store, weather: weather)) { Label("Share as text", systemImage: "text.alignleft") }
                    if let link = PlanShare.link(week) {
                        ShareLink(item: link, message: Text("My week plan - tap to open in Explorer")) { Label("Share as link", systemImage: "link") }
                    }
                    if let file = PlanShare.file(week, name: "Week " + Day.format(planner.weekStart, "d MMM")) {
                        ShareLink(item: file) { Label("Share as file (AirDrop, iCloud Drive)", systemImage: "doc") }
                    }
                    Button { showQR = true } label: { Label("Show QR code", systemImage: "qrcode") }
                    Divider()
                    Button(role: .destructive) { confirmClear = true } label: { Label("Clear this week", systemImage: "trash") }
                } label: { Image(systemName: "square.and.arrow.up") }
            }
        }
        .confirmationDialog("Clear everything planned this week?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear week", role: .destructive) { planner.clearWeek() }
        }
        .sheet(item: $editing) { PlanItemEditor(item: $0) }
        .sheet(isPresented: $showSuggest) { SuggestSheet() }
        .sheet(isPresented: $showQR) { PlanQRView(items: planner.weekDays.flatMap { planner.items(on: $0) }) }
        .explorerDestinations()
        .task { await weather.refresh() }
        .refreshable { await weather.refresh(force: true) }
    }

    private var weekHeader: some View {
        HStack {
            Button { planner.moveWeek(-1) } label: { Image(systemName: "chevron.left").font(.headline) }
            Spacer()
            VStack(spacing: 2) {
                Text("\(Day.format(planner.weekStart, "d MMM")) – \(Day.format(Day.add(6, to: planner.weekStart), "d MMM yyyy"))")
                    .font(.headline).foregroundStyle(theme.t.onBackground)
                if let a = weather.ageText { Text("Forecast \(a)").font(.caption2).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.7)) }
            }
            Spacer()
            Button { planner.moveWeek(1) } label: { Image(systemName: "chevron.right").font(.headline) }
        }
        .padding(.horizontal, 4)
    }

    private func dayCard(_ day: Date) -> some View {
        let list = planner.items(on: day)
        let isToday = Day.key(day) == Day.key(Date())
        let w = weather.forecast(for: day)
        let sun = Sun.times(day)
        return Card {
            HStack(alignment: .firstTextBaseline) {
                Text(Day.format(day, "EEEE d MMM")).font(.headline)
                    .foregroundStyle(isToday ? theme.t.primary : theme.t.onBackground)
                if isToday { Text("TODAY").font(.caption2.weight(.bold)).foregroundStyle(theme.t.primary) }
                Spacer()
                if let w {
                    HStack(spacing: 4) {
                        Image(systemName: w.symbol).symbolRenderingMode(.multicolor)
                        Text("\(Int(w.tMax.rounded()))°").font(.subheadline.weight(.semibold))
                    }
                }
            }
            if let w {
                let rain: String = w.rainMM >= 0.5 ? String(format: " · %.0f mm", w.rainMM) : ""
                let line: String = w.advice + rain + " · wind \(Int(w.windMph.rounded())) mph"
                Text(line)
                    .font(.caption).foregroundStyle(w.isWet || w.isWindy ? .orange : theme.t.onSurfaceVariant.opacity(0.8))
            }
            HStack(spacing: 10) {
                if let s = sun.sunset { Label(Day.time(s), systemImage: "sunset").labelStyle(.titleAndIcon) }
                if let t = store.tides?.extremes(on: day) {
                    ForEach(t) { e in Text("\(e.high ? "HW" : "LW") \(Day.time(e.time))") }
                }
            }
            .font(.caption2).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.7))
            if list.isEmpty {
                Text("Free").font(.subheadline).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.5))
            }
            ForEach(list) { item in
                PlanRow(item: item)
                    .contextMenu {
                        Button { editing = item } label: { Label("Edit", systemImage: "pencil") }
                        Menu("Move to") {
                            ForEach(planner.weekDays, id: \.self) { d in
                                Button(Day.format(d, "EEEE")) { var v = item; v.day = Day.key(d); planner.update(v) }
                            }
                        }
                        Button(role: .destructive) { planner.remove(item) } label: { Label("Remove", systemImage: "trash") }
                    }
            }
            HStack {
                Button { editing = PlanItem(day: Day.key(day), kind: .note, refID: nil, title: "", slot: .morning, time: nil) } label: {
                    Label("Add a note", systemImage: "plus.circle").font(.caption.weight(.semibold))
                }
                Spacer()
                if !list.isEmpty {
                    Text("Long-press an item to edit, move or remove").font(.caption2).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.5))
                }
            }
        }
    }
}

/// Edit (or create) one plan item: title for notes, part of day, time, note.
struct PlanItemEditor: View {
    @EnvironmentObject var planner: PlannerStore
    @Environment(\.dismiss) private var dismiss
    @State var item: PlanItem
    @State private var useTime = false
    @State private var time = Date()

    private var isNew: Bool { !planner.items.contains { $0.id == item.id } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if item.kind == .note {
                        TextField("What (e.g. lunch at the Minnis, train to Canterbury)", text: $item.title)
                    } else {
                        Text(item.title).font(.headline)
                    }
                    Text(Day.date(item.day).map { Day.format($0, "EEEE d MMMM") } ?? item.day).foregroundStyle(.secondary)
                }
                Section("When") {
                    Picker("Part of the day", selection: $item.slot) {
                        ForEach(PlanItem.Slot.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Set a time", isOn: $useTime)
                    if useTime { DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute) }
                }
                Section("Note") { TextField("Note", text: $item.note, axis: .vertical) }
                if !isNew {
                    Section {
                        Button("Remove from plan", role: .destructive) { planner.remove(item); dismiss() }
                    }
                }
            }
            .themedList()
            .navigationTitle(isNew ? "Add a note" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save") {
                        item.time = useTime ? Day.time(time) : nil
                        if isNew { planner.add(item) } else { planner.update(item) }
                        dismiss()
                    }
                    .disabled(item.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let t = item.time, let h = Int(t.prefix(2)), let m = Int(t.suffix(2)) {
                    useTime = true
                    time = Day.cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// The week's plan as a QR code: another iPhone's camera opens it straight in Explorer.
struct PlanQRView: View {
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss
    let items: [PlanItem]
    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if let link = PlanShare.link(items), let img = QR.image(link.absoluteString) {
                    Image(uiImage: img).interpolation(.none).resizable().scaledToFit()
                        .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 16))
                        .frame(maxWidth: 320)
                    Text("Scan with another iPhone's camera to copy this week's plan (\(items.count) items).")
                        .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(theme.t.onSurfaceVariant)
                } else {
                    Text("The plan is too long for one QR code - share it as a file instead.")
                }
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(theme.t.background)
            .navigationTitle("Plan QR code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
        }
    }
}

/// Tick what you would like to do; Suggest spreads it fairly over the empty days of the week,
/// led by the forecast, opening hours and your base & radius.
struct SuggestSheet: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var store: Store
    @EnvironmentObject var planner: PlannerStore
    @EnvironmentObject var weather: WeatherStore
    @EnvironmentObject var base: BaseStore
    @EnvironmentObject var location: LocationModel
    @EnvironmentObject var interests: InterestStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Interest.allCases) { i in
                        Toggle(isOn: Binding(get: { interests.chosen.contains(i) },
                                             set: { on in if on { interests.chosen.insert(i) } else { interests.chosen.remove(i) } })) {
                            Label(i.label, systemImage: i.symbol)
                        }
                    }
                } header: {
                    HStack {
                        SectionHead("What would you like to do?")
                        Spacer()
                        Button(interests.chosen.count == Interest.allCases.count ? "None" : "All") {
                            interests.chosen = interests.chosen.count == Interest.allCases.count ? [] : Set(Interest.allCases)
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
                .listRowBackground(theme.t.surface)
                Section {
                    Stepper("Up to \(interests.perDay) things a day", value: $interests.perDay, in: 1...4)
                    HStack { BaseChip(); Spacer() }
                    Text(weather.days.isEmpty ? "No forecast saved yet - outdoor plans are not weather-checked."
                         : "Wet days get indoor choices; very windy days skip beaches and exposed walks; sunset spots only on clear evenings.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { SectionHead("How") }
                .listRowBackground(theme.t.surface)
                Section {
                    Button {
                        planner.suggestFair(store: store, weather: weather, interests: interests.chosen, perDay: interests.perDay,
                                            origin: base.origin(location)) { base.within($0, location) }
                        dismiss()
                    } label: {
                        Label("Suggest my week", systemImage: "wand.and.stars").font(.headline).frame(maxWidth: .infinity)
                    }
                    .disabled(interests.chosen.isEmpty)
                    Text("Only empty days are filled - clear a day first to re-plan it.").font(.caption2).foregroundStyle(.secondary)
                }
                .listRowBackground(theme.t.surface)
            }
            .themedList()
            .navigationTitle("Suggest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
