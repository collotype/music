//
//  ContentView.swift
//  FreeMusicPlayer
//
//  Главный экран с навигацией
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var audioPlayer: AudioPlayer
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedTab: Tab = .home
    @State private var showPlayer: Bool = false
    
    var body: some View {
        ZStack {
            // Основной фон
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Контент
                TabView(selection: $selectedTab) {
                    HomeView()
                        .tabItem {
                            Label(Tab.home.title, systemImage: Tab.home.icon)
                        }
                        .tag(Tab.home)
                    
                    LibraryView()
                        .tabItem {
                            Label(Tab.library.title, systemImage: Tab.library.icon)
                        }
                        .tag(Tab.library)
                    
                    SearchView()
                        .tabItem {
                            Label(Tab.search.title, systemImage: Tab.search.icon)
                        }
                        .tag(Tab.search)
                    
                    SettingsView()
                        .tabItem {
                            Label(Tab.profile.title, systemImage: Tab.profile.icon)
                        }
                        .tag(Tab.profile)
                }
                
                // Мини-плеер
                if audioPlayer.currentTrack != nil {
                    MiniPlayer(showPlayer: $showPlayer)
                        .transition(.move(edge: .bottom))
                }
                
                // Нижняя навигация
                CustomTabBar(selectedTab: $selectedTab)
            }
            
            // Полноэкранный плеер
            if showPlayer {
                PlayerView(isPresented: $showPlayer)
                    .transition(.move(edge: .bottom))
            }
        }
        .accentColor(Color.red)
    }
}

// Кастомная нижняя панель навигации
struct CustomTabBar: View {
    @Binding var selectedTab: Tab
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = tab
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 22))
                        Text(tab.title)
                            .font(.system(size: 10))
                    }
                    .foregroundColor(selectedTab == tab ? .white : .gray)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 8)
        .background(
            Color(red: 0.1, green: 0.1, blue: 0.1)
                .opacity(0.95)
                .blur(radius: 20)
        )
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .colorMultiply(Color.white.opacity(0.1)),
            alignment: .top
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(AudioPlayer.shared)
        .environmentObject(DataManager.shared)
}
