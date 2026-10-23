import MapKit
import SwiftUI
import UIKit

/// A detail page's map opened full screen: pinch, pan, rotate, your position.
struct FullScreenMap: View {
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss
    var title: String
    var places: [Place] = []
    var events: [EventItem] = []
    var walk: Walk? = nil
    var focus: MapFocus
    @State private var follow = false

    var body: some View {
        ZStack(alignment: .top) {
            OfflineMapView(places: places, events: events, walk: walk,
                           routeColor: UIColor(theme.t.primary), accent: UIColor(theme.t.primary),
                           focus: focus, followUser: follow)
                .ignoresSafeArea()
            HStack {
                Button { dismiss() } label: {
                    Label("Close", systemImage: "xmark").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 9).background(.ultraThinMaterial, in: Capsule())
                }
                Spacer()
                Text(title).font(.caption.weight(.semibold)).lineLimit(1)
                    .padding(.horizontal, 10).padding(.vertical, 6).background(.ultraThinMaterial, in: Capsule())
                Spacer()
                Button { follow.toggle() } label: {
                    Image(systemName: follow ? "location.north.line.fill" : "location")
                        .font(.headline).frame(width: 42, height: 42).background(.ultraThinMaterial, in: Circle())
                }
            }
            .padding(.horizontal, 14)
        }
        .overlay(alignment: .bottomLeading) {
            Text("© OpenStreetMap contributors").font(.system(size: 9)).padding(4)
                .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 4)).foregroundStyle(.black)
                .padding(8)
        }
    }
}

/// The round "expand" button laid over a small map.
struct ExpandMapButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.subheadline.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
        }
        .padding(8)
    }
}
