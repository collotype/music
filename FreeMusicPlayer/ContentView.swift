//
//  ContentView.swift
//  FreeMusicPlayer
//
//  Root screen with a single navigation container.
//

import SwiftUI

enum AppTheme {
    static let paper = Color(red: 0.04, green: 0.04, blue: 0.04)
    static let paperDeep = Color(red: 0.01, green: 0.01, blue: 0.01)
    static let ink = Color.white
    static let mutedInk = Color(red: 0.62, green: 0.62, blue: 0.62)
    static let panel = Color(red: 0.10, green: 0.10, blue: 0.10)
    static let elevatedPanel = Color(red: 0.15, green: 0.15, blue: 0.15)
    static let line = Color.white.opacity(0.07)
    static let accent = Color(red: 0.26, green: 0.84, blue: 0.38)
}

struct ContentView: View {
    @EnvironmentObject var audioPlayer: AudioPlayer
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var router: AppRouter
    @State private var showPlayer: Bool = false
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.paper, AppTheme.paperDeep],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                NavigationStack(path: $router.path) {
                    currentTabView
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .navigationDestination(for: AppRoute.self) { route in
                            switch route {
                            case .playlist(let playlistId):
                                PlaylistView(playlistId: playlistId)
                            case .onlineArtist(let artist):
                                OnlineArtistDetailView(route: artist)
                            case .onlineRelease(let release):
                                OnlineReleaseDetailView(route: release)
                            }
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                if audioPlayer.currentTrack != nil {
                    MiniPlayer(showPlayer: $showPlayer)
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom))
                }

                CustomTabBar()
            }

            if showPlayer {
                PlayerView(isPresented: $showPlayer)
                    .transition(.move(edge: .bottom))
                    .zIndex(1)
            }
        }
        .accentColor(AppTheme.accent)
        .preferredColorScheme(.dark)
        .task {
            // Start heavy data loading AFTER the first render — runs off main thread.
            dataManager.loadData()
            audioPlayer.applySavedPlaybackPreferences(dataManager.settings)
        }
    }
    
    @ViewBuilder
    private var currentTabView: some View {
        switch router.selectedTab {
        case .home:
            HomeView()
        case .library:
            LibraryView()
        case .search:
            SearchView()
        }
    }
}

struct CustomTabBar: View {
    @EnvironmentObject var router: AppRouter
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    debugLog("Tab button pressed: \(tab.rawValue)")
                    withAnimation(.spring(response: 0.3)) {
                        router.navigate(to: tab)
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(router.selectedTab == tab ? AppTheme.ink : AppTheme.mutedInk.opacity(0.58))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .overlay(alignment: .top) {
                        if router.selectedTab == tab {
                            Circle()
                                .fill(AppTheme.accent)
                                .frame(width: 5, height: 5)
                                .offset(y: -2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            Rectangle()
                .fill(AppTheme.panel.opacity(0.96))
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.line)
                .frame(height: 0.5)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AudioPlayer.shared)
        .environmentObject(DataManager.shared)
        .environmentObject(AppRouter())
}
