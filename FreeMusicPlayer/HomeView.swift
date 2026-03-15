//
//  HomeView.swift
//  FreeMusicPlayer
//
//  Главная страница (как на референсе)
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var audioPlayer: AudioPlayer
    @State private var searchText: String = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                // Градиентный фон как на референсе
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.6, green: 0.1, blue: 0.1),
                        Color(red: 0.3, green: 0.05, blue: 0.05),
                        Color.black
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Моя волна
                        WaveCard()
                        
                        // Слушай вместе
                        ListenTogetherCard()
                        
                        // Плейлисты
                        PlaylistsSection()
                        
                        // Популярное
                        PopularSection()
                        
                        // Недавние
                        RecentSection()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 100)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                        Text("FreeMusic")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button(action: {}) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.white)
                        }
                        
                        Button(action: {}) {
                            AsyncImage(url: URL(string: "https://via.placeholder.com/40"))?
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                        }
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }
}

// Карточка "Моя волна"
struct WaveCard: View {
    @EnvironmentObject var audioPlayer: AudioPlayer
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Моя волна")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Зажмите для настройки и нажмите для погружения")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                Button(action: {
                    // Запуск волны
                    if let firstTrack = DataManager.shared.tracks.randomElement() {
                        audioPlayer.load(track: firstTrack)
                        audioPlayer.play()
                    }
                }) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: "play.fill")
                                .foregroundColor(.black)
                                .font(.system(size: 20))
                        )
                }
            }
            
            // Волнистая линия
            WaveformView()
                .frame(height: 40)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.05))
                .blur(radius: 20)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// Волнообразная визуализация
struct WaveformView: View {
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<40, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 3, height: CGFloat.random(in: 8...25))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// Карточка "Слушай вместе"
struct ListenTogetherCard: View {
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 32))
                .foregroundColor(.white)
                .frame(width: 60, height: 60)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.1))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Слушай вместе")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Публичные комнаты")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
    }
}

// Секция плейлистов
struct PlaylistsSection: View {
    @EnvironmentObject var dataManager: DataManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Плейлисты")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(dataManager.playlists.prefix(5)) { playlist in
                        PlaylistCard(playlist: playlist)
                    }
                    
                    // Добавить плейлист
                    Button(action: {
                        let name = "Новый плейлист \(dataManager.playlists.count + 1)"
                        _ = dataManager.createPlaylist(name: name)
                    }) {
                        VStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.05))
                                .frame(width: 140, height: 140)
                                .overlay(
                                    Image(systemName: "plus")
                                        .font(.system(size: 32))
                                        .foregroundColor(.white.opacity(0.5))
                                )
                            
                            Text("Создать")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.top, 8)
                        }
                    }
                }
            }
        }
    }
}

// Карточка плейлиста
struct PlaylistCard: View {
    let playlist: Playlist
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Обложка
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.7, green: 0.2, blue: 0.2),
                            Color(red: 0.3, green: 0.1, blue: 0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 140, height: 140)
                .overlay(
                    Image(systemName: "music.note.list")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.3))
                )
            
            Text(playlist.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
            
            Text("\(playlist.trackCount) треков")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
        }
    }
}

// Секция популярного
struct PopularSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Популярное")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<5, id: \.self) { i in
                        PopularCard(index: i)
                    }
                }
            }
        }
    }
}

struct PopularCard: View {
    let index: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.1))
                .frame(width: 140, height: 140)
            
            Text("Треки #\(index + 1)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
    }
}

// Секция недавних
struct RecentSection: View {
    @EnvironmentObject var dataManager: DataManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Недавние")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
            
            VStack(spacing: 0) {
                ForEach(dataManager.tracks.prefix(10)) { track in
                    TrackRow(track: track)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.03))
            )
        }
    }
}

// Строка трека
struct TrackRow: View {
    let track: Track
    @EnvironmentObject var audioPlayer: AudioPlayer
    @EnvironmentObject var dataManager: DataManager
    
    var isPlaying: Bool {
        audioPlayer.currentTrack?.id == track.id && audioPlayer.isPlaying
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Обложка
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.1))
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: "music.note")
                        .foregroundColor(.white.opacity(0.3))
                )
            
            // Информация
            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isPlaying ? .red : .white)
                
                Text(track.displayArtist)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            // Длительность
            Text(track.formattedDuration)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.05))
                )
            
            // Кнопка избранного
            Button(action: {
                dataManager.toggleFavorite(track)
            }) {
                Image(systemName: dataManager.favorites.contains(track.id) ? "heart.fill" : "heart")
                    .foregroundColor(dataManager.favorites.contains(track.id) ? .red : .white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            audioPlayer.load(track: track)
            audioPlayer.play()
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AudioPlayer.shared)
        .environmentObject(DataManager.shared)
}
