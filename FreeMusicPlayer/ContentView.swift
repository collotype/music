//
//  ContentView.swift
//  FreeMusicPlayer
//
//  Root screen with a single navigation container.
//

import SwiftUI

enum AppTheme {
    static let paper = Color(red: 0.94, green: 0.94, blue: 0.92)
    static let paperDeep = Color(red: 0.86, green: 0.86, blue: 0.84)
    static let ink = Color(red: 0.09, green: 0.09, blue: 0.09)
    static let mutedInk = Color(red: 0.36, green: 0.36, blue: 0.34)
    static let panel = Color.white.opacity(0.58)
    static let line = Color.black.opacity(0.08)
    static let accent = Color(red: 0.86, green: 0.20, blue: 0.16)
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
        .preferredColorScheme(.light)
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
                .fill(.ultraThinMaterial)
                .overlay(AppTheme.paper.opacity(0.72))
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
