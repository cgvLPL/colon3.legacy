import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var soulseek: SoulseekModel
    @EnvironmentObject private var player: Player
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var updates: UpdateChecker
    @AppStorage(AccentPalette.storageKey) private var accentHex = AccentPalette.defaultHex

    var body: some View {
        tabs
        .modifier(RouterPresenters(active: !router.showPlayer))
        .sheet(isPresented: $router.showPlayer) {
            NowPlayingView()
                .modifier(RouterPresenters(active: true))
                .tint(Color(hex: accentHex))
        }
        .compatOnChange(of: library.artworkRevision) { _ in player.reloadArtwork() }
        .tint(Color(hex: accentHex))
    }

    /// The Tab API (iOS 18) where it exists, so iOS 26's tab bar accessory keeps working;
    /// `.tabItem` on older systems.
    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 18, *) {
            TabView(selection: $router.tab) {
                Tab("Home", systemImage: "square.grid.2x2", value: AppTab.trending) {
                    HomeView().modifier(FallbackMiniPlayer(open: openPlayer))
                }
                Tab("Library", systemImage: "music.note.house", value: AppTab.library) {
                    LibraryView().modifier(FallbackMiniPlayer(open: openPlayer))
                }
                Tab("Search", systemImage: "magnifyingglass", value: AppTab.search) {
                    SearchView().modifier(FallbackMiniPlayer(open: openPlayer))
                }
                Tab("Downloads", systemImage: "arrow.down.circle", value: AppTab.downloads) {
                    DownloadsView().modifier(FallbackMiniPlayer(open: openPlayer))
                }
                .badge(soulseek.activeDownloadCount)
                Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                    SettingsView()
                }
                .badge(updates.isUpdateAvailable ? 1 : 0)
            }
            .modifier(TabAccessoryMiniPlayer(isVisible: player.current != nil, open: openPlayer))
        } else {
            TabView(selection: $router.tab) {
                HomeView().modifier(FallbackMiniPlayer(open: openPlayer))
                    .tabItem { Label("Home", systemImage: "square.grid.2x2") }
                    .tag(AppTab.trending)
                LibraryView().modifier(FallbackMiniPlayer(open: openPlayer))
                    .tabItem { Label("Library", systemImage: "music.note.house") }
                    .tag(AppTab.library)
                SearchView().modifier(FallbackMiniPlayer(open: openPlayer))
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
                    .tag(AppTab.search)
                DownloadsView().modifier(FallbackMiniPlayer(open: openPlayer))
                    .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
                    .badge(soulseek.activeDownloadCount)
                    .tag(AppTab.downloads)
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .badge(updates.isUpdateAvailable ? 1 : 0)
                    .tag(AppTab.settings)
            }
        }
    }

    private func openPlayer() {
        router.showPlayer = true
    }
}

/// Banner shown on screens that need the Soulseek connection.
struct ConnectionBanner: View {
    @EnvironmentObject private var soulseek: SoulseekModel

    var body: some View {
        switch soulseek.connection {
        case .loggedIn:
            EmptyView()
        case .connecting:
            Label("Connecting…", systemImage: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .disconnected:
            Label(soulseek.hasCredentials ? "Disconnected" : "Log in under Settings to search Soulseek",
                  systemImage: "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(.secondary)
        }
    }
}
