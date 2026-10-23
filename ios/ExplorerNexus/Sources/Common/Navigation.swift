import SwiftUI

/// Destinations every tab's NavigationStack understands.
struct ExplorerDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: Place.self) { PlaceDetailView(place: $0) }
            .navigationDestination(for: EventItem.self) { EventDetailView(event: $0) }
            .navigationDestination(for: Walk.self) { WalkDetailView(walk: $0) }
            .navigationDestination(for: Screen.self) { s in
                switch s {
                case .whatsOn: EventsView()
                case .tides: TidesView()
                case .photo: PhotoView()
                case .info: InfoView()
                case .settings: SettingsView()
                }
            }
    }
}

enum Screen: Hashable { case whatsOn, tides, photo, info, settings }

extension View {
    func explorerDestinations() -> some View { modifier(ExplorerDestinations()) }
}

/// What the "Add to my week" sheet is adding.
struct PlanTarget: Identifiable {
    let kind: PlanItem.Kind
    let refID: String?
    let title: String
    var time: String? = nil
    /// Days it is possible on (events); nil = any day.
    var days: Set<String>? = nil
    var id: String { "\(kind)-\(refID ?? title)" }
}

struct AddToPlanSheet: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var planner: PlannerStore
    @Environment(\.dismiss) private var dismiss
    let target: PlanTarget
    @State private var day: Date = Day.start(Date())
    @State private var slot: PlanItem.Slot = .morning
    @State private var useTime = false
    @State private var time = Date()
    @State private var note = ""

    private var choices: [Date] {
        let today = Day.start(Date())
        let all = (0..<21).map { Day.add($0, to: today) }
        guard let d = target.days else { return all }
        return all.filter { d.contains(Day.key($0)) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(target.title).font(.headline)
                }
                Section("Day") {
                    if choices.isEmpty {
                        Text("Not on in the next three weeks.").foregroundStyle(.secondary)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(choices, id: \.self) { d in
                                let on = Day.key(d) == Day.key(day)
                                Button { day = d } label: {
                                    VStack(spacing: 2) {
                                        Text(Day.weekdayShort(d)).font(.caption.weight(.semibold))
                                        Text(Day.format(d, "d")).font(.title3.weight(.bold))
                                        Text(Day.format(d, "MMM")).font(.caption2)
                                    }
                                    .frame(width: 52, height: 66)
                                    .foregroundStyle(on ? theme.t.onPrimary : theme.t.onSurfaceVariant)
                                    .background(on ? theme.t.primary : theme.t.surfaceVariant, in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    let n = planner.items(on: day).count
                    if n > 0 { Text("\(n) thing\(n == 1 ? "" : "s") planned that day already").font(.caption).foregroundStyle(.secondary) }
                }
                Section("When") {
                    Picker("Part of the day", selection: $slot) {
                        ForEach(PlanItem.Slot.allCases, id: \.self) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Set a time", isOn: $useTime)
                    if useTime {
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    }
                }
                Section("Note") {
                    TextField("e.g. book tickets, meet at the station", text: $note, axis: .vertical)
                }
                if let tides = Store.shared.tides {
                    let ex = tides.extremes(on: day)
                    if !ex.isEmpty {
                        Section("Tides that day") { TideRow(extremes: ex).listRowBackground(Color.clear) }
                    }
                }
            }
            .themedList()
            .navigationTitle("Add to my week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let t = useTime ? Day.time(time) : nil
                        planner.add(PlanItem(day: Day.key(day), kind: target.kind, refID: target.refID, title: target.title,
                                             slot: slotFor(t) ?? slot, time: t, note: note))
                        planner.weekStart = Day.weekStart(day)
                        dismiss()
                    }
                    .disabled(choices.isEmpty)
                }
            }
            .onAppear {
                if let first = choices.first { day = first }
                if let t = target.time, let h = Int(t.prefix(2)), let m = Int(t.suffix(2)) {
                    useTime = true
                    time = Day.cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
                    slot = slotFor(t) ?? .morning
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func slotFor(_ t: String?) -> PlanItem.Slot? {
        guard let t, let h = Int(t.prefix(2)) else { return nil }
        return h < 12 ? .morning : (h < 17 ? .afternoon : .evening)
    }
}
