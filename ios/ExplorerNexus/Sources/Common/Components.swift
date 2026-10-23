import Charts
import SwiftUI

/// A rounded theme-surface card.
struct Card<Content: View>: View {
    @EnvironmentObject var theme: ThemeStore
    var padding: CGFloat = 14
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.t.outline.opacity(0.6), lineWidth: 0.5))
    }
}

/// Round category icon (colour + SF Symbol).
struct CatIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 34
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: Circle())
    }
}

/// Filter chip.
struct Chip: View {
    let text: String
    var symbol: String? = nil
    let on: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) { ChipLabel(text: text, symbol: symbol, on: on) }
            .buttonStyle(.plain)
    }
}

/// The look of a chip without the button (for Menu labels).
struct ChipLabel: View {
    @EnvironmentObject var theme: ThemeStore
    let text: String
    var symbol: String? = nil
    let on: Bool
    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.caption) }
            Text(text).font(.subheadline.weight(on ? .semibold : .regular))
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .foregroundStyle(on ? theme.t.onPrimary : theme.t.onSurfaceVariant)
        .background(on ? theme.t.primary : theme.t.surfaceVariant, in: Capsule())
    }
}

/// Label + value row in a detail page (hidden when the value is missing).
struct InfoRow: View {
    @EnvironmentObject var theme: ThemeStore
    let symbol: String
    let title: String
    let value: String?
    var body: some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol).foregroundStyle(theme.t.primary).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.caption).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.7))
                    Text(value).font(.subheadline).foregroundStyle(theme.t.onBackground)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// "Needs signal" links (website, phone, directions), with the sources list.
struct LinksBlock: View {
    @EnvironmentObject var theme: ThemeStore
    var website: String?
    var phone: String?
    var directions: (lat: Double, lon: Double, name: String)?
    var sources: [String] = []
    var verified: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let w = website, let u = URL(string: w) {
                Link(destination: u) { Label("Website", systemImage: "safari") }
            }
            if let p = phone, let u = URL(string: "tel:" + p.filter { $0.isNumber || $0 == "+" }) {
                Link(destination: u) { Label(p, systemImage: "phone") }
            }
            if let d = directions,
               let u = URL(string: "http://maps.apple.com/?daddr=\(d.lat),\(d.lon)&dirflg=w&q=\(d.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                Link(destination: u) { Label("Directions in Apple Maps", systemImage: "arrow.triangle.turn.up.right.diamond") }
            }
            if !sources.isEmpty {
                DisclosureGroup("Sources") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(sources, id: \.self) { s in
                            if let u = URL(string: s) {
                                Link(s, destination: u).font(.caption).lineLimit(1).truncationMode(.middle)
                            }
                        }
                        if let verified { Text("Checked \(verified). Details change - check before you travel.").font(.caption2).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.6)) }
                    }
                }
                .font(.subheadline)
            }
        }
        .tint(theme.t.primary)
    }
}

/// Today's tide curve with high/low marks and a "now" line.
struct TideChart: View {
    @EnvironmentObject var theme: ThemeStore
    let day: Date
    let tides: TideTable
    var height: CGFloat = 150
    var body: some View {
        let curve = tides.curve(on: day)
        let ex = tides.extremes(on: day)
        let now = Date()
        let sun = Sun.times(day)
        Chart {
            if let r = sun.sunrise, let s = sun.sunset {
                RectangleMark(xStart: .value("rise", r), xEnd: .value("set", s))
                    .foregroundStyle(theme.t.primary.opacity(0.07))
            }
            ForEach(Array(curve.enumerated()), id: \.offset) { _, p in
                AreaMark(x: .value("Time", p.0), y: .value("Height", p.1))
                    .foregroundStyle(LinearGradient(colors: [Color(hex: 0x2E9BD6).opacity(0.55), Color(hex: 0x2E9BD6).opacity(0.05)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", p.0), y: .value("Height", p.1))
                    .foregroundStyle(Color(hex: 0x5BB8EA))
            }
            ForEach(ex) { e in
                PointMark(x: .value("Time", e.time), y: .value("Height", e.height))
                    .foregroundStyle(e.high ? Color(hex: 0x5BB8EA) : Color(hex: 0xC9A66B))
                    .annotation(position: e.high ? .top : .bottom, spacing: 2) {
                        Text(Day.time(e.time)).font(.caption2.weight(.semibold)).foregroundStyle(theme.t.onSurfaceVariant)
                    }
            }
            if Day.key(now) == Day.key(day) {
                RuleMark(x: .value("Now", now)).foregroundStyle(theme.t.primary)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
        .chartYScale(domain: -0.5...6.0)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisGridLine().foregroundStyle(theme.t.outline.opacity(0.4))
                AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .omitted)), centered: false)
                    .foregroundStyle(theme.t.onSurfaceVariant.opacity(0.7))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 2, 4, 6]) { v in
                AxisGridLine().foregroundStyle(theme.t.outline.opacity(0.3))
                AxisValueLabel { Text("\(v.as(Int.self) ?? 0) m").font(.caption2) }
                    .foregroundStyle(theme.t.onSurfaceVariant.opacity(0.7))
            }
        }
        .frame(height: height)
    }
}

/// High/low water chips in a row.
struct TideRow: View {
    @EnvironmentObject var theme: ThemeStore
    let extremes: [TideExtreme]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(extremes) { e in
                VStack(spacing: 1) {
                    Text(e.high ? "HIGH" : "LOW").font(.caption2.weight(.bold)).tracking(1)
                        .foregroundStyle(e.high ? Color(hex: 0x5BB8EA) : Color(hex: 0xC9A66B))
                    Text(Day.time(e.time)).font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(theme.t.onBackground)
                    Text(String(format: "%.1f m", e.height)).font(.caption2).foregroundStyle(theme.t.onSurfaceVariant.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(theme.t.surfaceVariant.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

/// Small "Add to planner" button used on detail pages.
struct PlanButton: View {
    @EnvironmentObject var theme: ThemeStore
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label("Add to my week", systemImage: "calendar.badge.plus")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(theme.t.onPrimary)
                .background(theme.t.primary, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

extension View {
    func cardTitle(_ theme: ThemeStore) -> some View {
        self.font(.headline).foregroundStyle(theme.t.onBackground)
    }
}
