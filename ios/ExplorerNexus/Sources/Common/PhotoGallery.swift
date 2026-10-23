import SwiftUI
import UIKit

/// One bundled photo (Wikimedia Commons, openly licensed) with its credit.
struct PhotoItem: Identifiable, Hashable {
    let id: String
    let image: UIImage
    let title: String
    let author: String
    let licence: String
    let page: String?
    /// Walk photos: which waypoint (0-based) it shows.
    let point: Int?

    var credit: String { "\(author) · \(licence) · Wikimedia Commons" }

    static func == (a: PhotoItem, b: PhotoItem) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

extension Store {
    /// Photos for a place id or "walk:<id>", read on demand (kept small in memory).
    func photos(for owner: String) -> [PhotoItem] {
        guard let path = Bundle.main.path(forResource: "explorer", ofType: "sqlite", inDirectory: "Content"),
              let db = SQLiteDB(path: path) else { return [] }
        var out: [PhotoItem] = []
        db.query("SELECT seq, point, data, title, author, licence, page FROM photos WHERE owner = ? ORDER BY seq", [owner]) { r in
            guard let d = r.data(2), let img = UIImage(data: d) else { return }
            out.append(PhotoItem(id: "\(owner)#\(r.int(0) ?? 0)", image: img, title: r.text(3), author: r.text(4),
                                 licence: r.text(5), page: r.string(6), point: r.int(1)))
        }
        return out
    }
}

/// Swipeable photos with the credit under each; tap for full screen.
struct PhotoGallery: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var store: Store
    let owner: String
    var height: CGFloat = 230
    @State private var photos: [PhotoItem] = []
    @State private var index = 0
    @State private var full: PhotoItem?

    var body: some View {
        Group {
            if !photos.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    TabView(selection: $index) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { i, p in
                            Image(uiImage: p.image)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: height)
                                .clipped()
                                .contentShape(Rectangle())
                                .onTapGesture { full = p }
                                .tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
                    .frame(height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    if index < photos.count {
                        creditLine(photos[index])
                    }
                }
            }
        }
        .task(id: owner) { photos = store.photos(for: owner) }
        .fullScreenCover(item: $full) { p in FullPhoto(photo: p) }
    }

    private func creditLine(_ p: PhotoItem) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "camera").font(.system(size: 9))
            if let page = p.page, let u = URL(string: page) {
                Link(p.credit, destination: u)
            } else {
                Text(p.credit)
            }
        }
        .font(.caption2)
        .lineLimit(1)
        .foregroundStyle(theme.t.onSurfaceVariant.opacity(0.6))
        .tint(theme.t.onSurfaceVariant.opacity(0.6))
    }
}

/// Full-screen photo with pinch-zoom.
struct FullPhoto: View {
    @Environment(\.dismiss) private var dismiss
    let photo: PhotoItem
    @State private var scale: CGFloat = 1
    @State private var base: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: photo.image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .gesture(MagnificationGesture()
                    .onChanged { scale = max(1, min(5, base * $0)) }
                    .onEnded { _ in base = scale })
                .onTapGesture(count: 2) { scale = 1; base = 1 }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(.white.opacity(0.85))
            }
            .padding()
            VStack {
                Spacer()
                Text("\(photo.title.replacingOccurrences(of: "File:", with: ""))\n\(photo.credit)")
                    .font(.caption2).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
                    .padding(.bottom, 20).padding(.horizontal)
            }
        }
    }
}
