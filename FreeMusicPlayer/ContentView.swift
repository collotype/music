//
//  ContentView.swift
//  FreeMusicPlayer
//
//  Root screen with a single navigation container.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var audioPlayer: AudioPlayer
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var router: AppRouter
    @State private var showPlayer: Bool = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

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
        }
        .accentColor(.red)
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
        case .settings:
            SettingsView()
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
                            .font(.system(size: 22))
                        Text(tab.title)
                            .font(.system(size: 10))
                    }
                    .foregroundColor(router.selectedTab == tab ? .white : .gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .background(
            Color(red: 0.1, green: 0.1, blue: 0.1)
                .opacity(0.95)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.1))
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
