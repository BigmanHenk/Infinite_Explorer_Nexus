import SwiftUI

/// The Nexus colour themes — the same set and values as the Windows, Android and Nexus iOS
/// apps. Twilight is the default.
struct NexusTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let primaryHex: UInt32
    let onPrimaryHex: UInt32
    let secondaryHex: UInt32
    let tertiaryHex: UInt32
    let backgroundHex: UInt32
    let surfaceHex: UInt32
    let surfaceVariantHex: UInt32
    let onBackgroundHex: UInt32
    let onSurfaceVariantHex: UInt32
    var outlineHex: UInt32? = nil

    var primary: Color { Color(hex: primaryHex) }
    var onPrimary: Color { Color(hex: onPrimaryHex) }
    var secondary: Color { Color(hex: secondaryHex) }
    var tertiary: Color { Color(hex: tertiaryHex) }
    var background: Color { Color(hex: backgroundHex) }
    var surface: Color { Color(hex: surfaceHex) }
    var surfaceVariant: Color { Color(hex: surfaceVariantHex) }
    var onBackground: Color { Color(hex: onBackgroundHex) }
    var onSurfaceVariant: Color { Color(hex: onSurfaceVariantHex) }
    var outline: Color { Color(hex: outlineHex ?? surfaceVariantHex) }

    static let all: [NexusTheme] = [
        NexusTheme(id: "ATELIER", name: "Atelier", primaryHex: 0x3179A6, onPrimaryHex: 0x000D1A, secondaryHex: 0x5F6469,
                   tertiaryHex: 0x3179A6, backgroundHex: 0x0E1216, surfaceHex: 0x202429, surfaceVariantHex: 0x2F3338,
                   onBackgroundHex: 0xFAF8F5, onSurfaceVariantHex: 0xEDEBE7),
        NexusTheme(id: "TWILIGHT", name: "Twilight", primaryHex: 0xDA9E3F, onPrimaryHex: 0x100300, secondaryHex: 0x6D717E,
                   tertiaryHex: 0xDA9E3F, backgroundHex: 0x040819, surfaceHex: 0x13192D, surfaceVariantHex: 0x21283D,
                   onBackgroundHex: 0xF4EDE6, onSurfaceVariantHex: 0xE9DFD5),
        NexusTheme(id: "BOTANICAL", name: "Botanical", primaryHex: 0xBA6826, onPrimaryHex: 0x100200, secondaryHex: 0x556159,
                   tertiaryHex: 0xBA6826, backgroundHex: 0x092012, surfaceHex: 0x1D3425, surfaceVariantHex: 0x2C4334,
                   onBackgroundHex: 0xF7F1E5, onSurfaceVariantHex: 0xEBE4D6),
        NexusTheme(id: "CYANOTYPE", name: "Cyanotype", primaryHex: 0x00B1DA, onPrimaryHex: 0x000815, secondaryHex: 0x546673,
                   tertiaryHex: 0x00B1DA, backgroundHex: 0x001C3C, surfaceHex: 0x003053, surfaceVariantHex: 0x0F4064,
                   onBackgroundHex: 0xF0F6F9, onSurfaceVariantHex: 0xE0EAED),
        NexusTheme(id: "JADE", name: "Jade", primaryHex: 0x1F9B82, onPrimaryHex: 0x000A05, secondaryHex: 0x576767,
                   tertiaryHex: 0x1F9B82, backgroundHex: 0x031A1A, surfaceHex: 0x162E2D, surfaceVariantHex: 0x253D3D,
                   onBackgroundHex: 0xEAF5F0, onSurfaceVariantHex: 0xDAE9E3),
        NexusTheme(id: "DUSK_INDIGO", name: "Dusk Indigo", primaryHex: 0x8FDF5A, onPrimaryHex: 0x0D2000, secondaryHex: 0x8FDF5A,
                   tertiaryHex: 0xA07EFF, backgroundHex: 0x05030F, surfaceHex: 0x0E0B22, surfaceVariantHex: 0x1C1840,
                   onBackgroundHex: 0x8FDF5A, onSurfaceVariantHex: 0x9B7FE0, outlineHex: 0x524A80),
        NexusTheme(id: "AMETHYST", name: "Amethyst", primaryHex: 0xE4B24A, onPrimaryHex: 0x1A0F00, secondaryHex: 0x6E6580,
                   tertiaryHex: 0xE4B24A, backgroundHex: 0x140826, surfaceHex: 0x251643, surfaceVariantHex: 0x342056,
                   onBackgroundHex: 0xF1EAF7, onSurfaceVariantHex: 0xDED3EC),
        NexusTheme(id: "HARBOR", name: "Harbor", primaryHex: 0xE9A94D, onPrimaryHex: 0x160A00, secondaryHex: 0x5A6E73,
                   tertiaryHex: 0xE9A94D, backgroundHex: 0x04202A, surfaceHex: 0x0F3540, surfaceVariantHex: 0x184451,
                   onBackgroundHex: 0xEAF3F5, onSurfaceVariantHex: 0xD6E5E8),
        NexusTheme(id: "MARINE", name: "Marine", primaryHex: 0xE08A4A, onPrimaryHex: 0x170800, secondaryHex: 0x5B6675,
                   tertiaryHex: 0xE08A4A, backgroundHex: 0x041530, surfaceHex: 0x0E2748, surfaceVariantHex: 0x163A5E,
                   onBackgroundHex: 0xEAF1F9, onSurfaceVariantHex: 0xD8E2ED),
        NexusTheme(id: "SLATE", name: "Slate", primaryHex: 0x37C6B0, onPrimaryHex: 0x00110D, secondaryHex: 0x5D686E,
                   tertiaryHex: 0x37C6B0, backgroundHex: 0x0F1417, surfaceHex: 0x1E262B, surfaceVariantHex: 0x2C363C,
                   onBackgroundHex: 0xEEF3F5, onSurfaceVariantHex: 0xDCE4E7),
    ]

    /// All-red, dark-adapted; overrides the chosen theme when switched on.
    static let nightRed = NexusTheme(id: "NIGHT_RED", name: "Night Red", primaryHex: 0xDD1800, onPrimaryHex: 0x0D0000,
                                     secondaryHex: 0x881100, tertiaryHex: 0x661000, backgroundHex: 0x040000,
                                     surfaceHex: 0x0A0000, surfaceVariantHex: 0x120000, onBackgroundHex: 0xBF1100,
                                     onSurfaceVariantHex: 0x991000, outlineHex: 0x661000)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// The chosen theme, kept in UserDefaults, shared through the environment.
@MainActor
final class ThemeStore: ObservableObject {
    @Published var themeID: String { didSet { UserDefaults.standard.set(themeID, forKey: "theme_name"); apply(); updateAppIcon() } }
    @Published var nightRed: Bool { didSet { UserDefaults.standard.set(nightRed, forKey: "theme_night_red"); apply(); updateAppIcon() } }

    /// The home-screen icon follows the theme (one theme-coloured icon per theme in the
    /// asset catalog, as the Myco app does). Only on a theme change: iOS shows a short
    /// notice every time an app changes its icon.
    private func updateAppIcon() {
        let want = nightRed ? "AppIcon-NIGHT_RED" : "AppIcon-\(themeID)"
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, app.alternateIconName != want else { return }
        app.setAlternateIconName(want) { err in if let err { print("app icon \(want): \(err.localizedDescription)") } }
    }

    init() {
        themeID = UserDefaults.standard.string(forKey: "theme_name") ?? "TWILIGHT"
        nightRed = UserDefaults.standard.bool(forKey: "theme_night_red")
        apply()
    }

    var t: NexusTheme {
        if nightRed { return .nightRed }
        return NexusTheme.all.first { $0.id == themeID } ?? NexusTheme.all[1]
    }

    /// UIKit bars that SwiftUI does not style itself.
    private func apply() {
        let t = self.t
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(t.surface)
        let item = UITabBarItemAppearance()
        item.normal.iconColor = UIColor(t.onSurfaceVariant.opacity(0.6))
        item.normal.titleTextAttributes = [.foregroundColor: UIColor(t.onSurfaceVariant.opacity(0.6))]
        item.selected.iconColor = UIColor(t.primary)
        item.selected.titleTextAttributes = [.foregroundColor: UIColor(t.primary)]
        tab.stackedLayoutAppearance = item
        tab.inlineLayoutAppearance = item
        tab.compactInlineLayoutAppearance = item
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(t.background)
        nav.titleTextAttributes = [.foregroundColor: UIColor(t.onBackground)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(t.onBackground)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
    }
}

/// Theme background + surface rows for a Form or List, as the Windows app's panels.
struct ThemedList: ViewModifier {
    @EnvironmentObject var theme: ThemeStore
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(theme.t.background)
            .toolbarBackground(theme.t.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(theme.t.surface, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
    }
}

extension View {
    func themedList() -> some View { modifier(ThemedList()) }
}

/// Section titles in the Nexus style: small capitals in the theme accent.
struct SectionHead: View {
    @EnvironmentObject var theme: ThemeStore
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.bold)).tracking(1.5)
            .foregroundStyle(theme.t.primary)
    }
}
