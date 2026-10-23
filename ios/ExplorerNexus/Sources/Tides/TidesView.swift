import SwiftUI

/// Tide tables: a day's curve, then a month of high and low waters.
struct TidesView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var store: Store
    @State private var day = Day.start(Date())
    @State private var month = Day.start(Date())

    var body: some View {
        ScrollView {
            if let tides = store.tides {
                VStack(alignment: .leading, spacing: 14) {
                    Card {
                        HStack {
                            Button { day = Day.add(-1, to: day) } label: { Image(systemName: "chevron.left") }
                            Spacer()
                            VStack(spacing: 2) {
                                Text(Day.format(day, "EEEE d MMMM yyyy")).font(.headline).foregroundStyle(theme.t.onBackground)
                                if let r = tides.rangeText(on: day) { Text(r).font(.caption).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.7)) }
                            }
                            Spacer()
                            Button { day = Day.add(1, to: day) } label: { Image(systemName: "chevron.right") }
                        }
                        TideChart(day: day, tides: tides, height: 190)
                        TideRow(extremes: tides.extremes(on: day))
                        let sun = Sun.times(day)
                        HStack {
                            if let r = sun.sunrise { Label(Day.time(r), systemImage: "sunrise") }
                            Spacer()
                            if let s = sun.sunset { Label(Day.time(s), systemImage: "sunset") }
                        }
                        .font(.caption).foregroundStyle(theme.t.onSurfaceVariant)
                    }
                    Card {
                        Label("Safety", systemImage: "exclamationmark.triangle.fill").font(.subheadline.weight(.bold)).foregroundStyle(.orange)
                        Text("The tide comes in fast over the flat chalk and mud at Minnis Bay, Reculver, Pegwell Bay and below the cliffs from Margate to Botany Bay, and can cut you off. Start back well before high water. In an emergency call 999 and ask for the Coastguard.")
                            .font(.footnote).foregroundStyle(theme.t.onBackground).fixedSize(horizontal: false, vertical: true)
                        Text(tides.accuracyNote).font(.caption2).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(tides.datumNote).font(.caption2).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.7))
                    }
                    monthTable(tides)
                }
                .padding(16)
            } else {
                Text("Tide tables are missing from this build.").padding()
            }
        }
        .background(theme.t.background)
        .navigationTitle("Tides · Margate")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func monthTable(_ tides: TideTable) -> some View {
        let first = Day.cal.date(from: Day.cal.dateComponents([.year, .month], from: month)) ?? month
        let n = Day.cal.range(of: .day, in: .month, for: first)?.count ?? 30
        return Card {
            HStack {
                Button { month = Day.cal.date(byAdding: .month, value: -1, to: first) ?? first } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(Day.format(first, "MMMM yyyy")).font(.headline).foregroundStyle(theme.t.onBackground)
                Spacer()
                Button { month = Day.cal.date(byAdding: .month, value: 1, to: first) ?? first } label: { Image(systemName: "chevron.right") }
            }
            HStack {
                Text("Day").frame(width: 58, alignment: .leading)
                Text("High water").frame(maxWidth: .infinity, alignment: .leading)
                Text("Low water").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption2.weight(.bold)).foregroundStyle(theme.t.primary)
            ForEach(0..<n, id: \.self) { i in
                let d = Day.add(i, to: first)
                let ex = tides.extremes(on: d)
                let today = Day.key(d) == Day.key(Date())
                Button { day = d } label: {
                    HStack(alignment: .top) {
                        Text(Day.format(d, "EEE d")).frame(width: 58, alignment: .leading)
                            .fontWeight(today ? .bold : .regular)
                        Text(ex.filter(\.high).map { "\(Day.time($0.time)) \(String(format: "%.1f", $0.height))" }.joined(separator: "\n"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(ex.filter { !$0.high }.map { "\(Day.time($0.time)) \(String(format: "%.1f", $0.height))" }.joined(separator: "\n"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(today ? theme.t.primary : theme.t.onBackground)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
                if i < n - 1 { Divider().overlay(theme.t.outline.opacity(0.4)) }
            }
            Text("Times are UK local time (GMT/BST); heights in metres. Tap a day to see its curve above.")
                .font(.caption2).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.6))
        }
    }
}
