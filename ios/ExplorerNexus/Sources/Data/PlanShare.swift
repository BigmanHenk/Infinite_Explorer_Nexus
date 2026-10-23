import Foundation

/// Moving a plan between phones and the PC planner without any server:
///  - link  explorernexus://plan?z=<base64url of raw-deflate JSON>  (QR code on the PC page,
///    or sent in a message); ?j=<base64url JSON> is accepted too;
///  - file  *.explorerplan (the same JSON) via AirDrop, Mail, Messages, Files/iCloud Drive.
/// JSON: {"v":1,"from":"Explorer","items":[{"d":"2026-10-24","k":"walk","r":"id","t":"Title",
///        "s":"morning","tm":"10:00","n":"note"}]}
enum PlanShare {
    struct Wire: Codable {
        var v = 1
        var from: String?
        var items: [Item]
        struct Item: Codable {
            var d: String
            var k: String
            var r: String?
            var t: String
            var s: String
            var tm: String?
            var n: String?
        }
    }

    static func wire(_ items: [PlanItem]) -> Wire {
        Wire(from: "Explorer iPhone", items: items.map {
            .init(d: $0.day, k: $0.kind.rawValue, r: $0.refID, t: $0.title, s: $0.slot.rawValue, tm: $0.time,
                  n: $0.note.isEmpty ? nil : $0.note)
        })
    }

    static func items(_ w: Wire) -> [PlanItem] {
        w.items.compactMap { i in
            guard Day.date(i.d) != nil else { return nil }
            return PlanItem(day: i.d, kind: PlanItem.Kind(rawValue: i.k) ?? .note, refID: i.r, title: i.t,
                            slot: PlanItem.Slot(rawValue: i.s) ?? .morning, time: i.tm, note: i.n ?? "")
        }
    }

    static func json(_ items: [PlanItem]) -> Data {
        (try? JSONEncoder().encode(wire(items))) ?? Data()
    }

    /// A link that opens the app with this plan.
    static func link(_ items: [PlanItem]) -> URL? {
        let raw = json(items)
        if let z = try? (raw as NSData).compressed(using: .zlib) as Data {   // .zlib = raw deflate
            return URL(string: "explorernexus://plan?z=" + base64url(z))
        }
        return URL(string: "explorernexus://plan?j=" + base64url(raw))
    }

    /// Writes a .explorerplan file for sharing.
    static func file(_ items: [PlanItem], name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".explorerplan")
        do { try json(items).write(to: url, options: .atomic) } catch { return nil }
        return url
    }

    /// Reads a plan from a link or a file the app was opened with.
    static func read(_ url: URL) -> [PlanItem]? {
        if url.isFileURL {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let d = try? Data(contentsOf: url) else { return nil }
            return decode(d)
        }
        guard url.scheme == "explorernexus",
              let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        if let z = q.first(where: { $0.name == "z" })?.value, let d = unbase64url(z),
           let raw = try? (d as NSData).decompressed(using: .zlib) as Data {
            return decode(raw)
        }
        if let j = q.first(where: { $0.name == "j" })?.value, let d = unbase64url(j) {
            return decode(d)
        }
        return nil
    }

    private static func decode(_ d: Data) -> [PlanItem]? {
        guard let w = try? JSONDecoder().decode(Wire.self, from: d) else { return nil }
        let v = items(w)
        return v.isEmpty ? nil : v
    }

    static func base64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func unbase64url(_ s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        return Data(base64Encoded: b)
    }
}

extension PlannerStore {
    /// Adds imported items; `replaceDays` first clears the days the import covers.
    func importItems(_ new: [PlanItem], replaceDays: Bool) {
        if replaceDays {
            for key in Set(new.map(\.day)) { if let d = Day.date(key) { clear(day: d) } }
        }
        for it in new {
            let dup = items.contains { $0.day == it.day && $0.title == it.title && $0.kind == it.kind }
            if !dup { add(it) }
        }
        if let first = new.map(\.day).min(), let d = Day.date(first) { weekStart = Day.weekStart(d) }
    }
}
