//
//  PlayerView.swift
//  FreeMusicPlayer
//
//  Полноэкранный плеер
//

import SwiftUI

struct PlayerView: View {
    @EnvironmentObject var audioPlayer: AudioPlayer
    @EnvironmentObject var dataManager: DataManager
    @Binding var isPresented: Bool
    @State private var showLyrics: Bool = false
    @State private var showEQ: Bool = false
    
    var body: some View {
        ZStack {
            // Градиентный фон
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.7, green: 0.15, blue: 0.15),
                    Color(red: 0.2, green: 0.05, blue: 0.05),
                    Color.black
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Верхняя панель
                playerHeader
                
                Spacer()
                
                // Обложка
                albumArt
                
                Spacer()
                
                // Информация и контролы
                playerControls
            }
        }
    }
    
    // Верхняя панель
    var playerHeader: some View {
        HStack {
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    isPresented = false
                }
            }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            Text("СЕЙЧАС ИГРАЕТ")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
            
            Spacer()
            
            Button(action: { showEQ = true }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
    
    // Обложка альбома
    var albumArt: some View {
        VStack(spacing: 20) {
            // Большая обложка
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.8, green: 0.2, blue: 0.2),
                                Color(red: 0.3, green: 0.1, blue: 0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .aspectRatio(1, contentMode: .fit)
                    .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
                
                Image(systemName: "music.note")
                    .font(.system(size: 80))
                    .foregroundColor(.white.opacity(0.3))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40)
            
            // Информация о треке
            VStack(spacing: 8) {
                Text(audioPlayer.currentTrack?.displayTitle ?? "Неизвестно")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text(audioPlayer.currentTrack?.displayArtist ?? "")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            // Кнопка избранного
            HStack(spacing: 24) {
                Button(action: {
                    audioPlayer.playPrevious()
                }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }
                
                Button(action: {
                    audioPlayer.togglePlayPause()
                }) {
                    Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.white)
                }
                
                Button(action: {
                    audioPlayer.playNext()
                }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }
            }
            .padding(.top, 8)
        }
    }
    
    // Контролы плеера
    var playerControls: some View {
        VStack(spacing: 20) {
            // Прогресс бар
            progressSection
            
            // Дополнительные контролы
            extraControls
            
            Spacer(minLength: 20)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
    }
    
    // Прогресс
    var progressSection: some View {
        VStack(spacing: 8) {
            // Слайдер
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Фон
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 4)
                    
                    // Заполнение
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white)
                        .frame(width: progressWidth(geometry.size.width), height: 4)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let percent = max(0, min(1, value.location.x / geometry.size.width))
                            audioPlayer.seek(to: percent * audioPlayer.duration)
                        }
                )
            }
            .frame(height: 20)
            
            // Время
            HStack {
                Text(formatTime(audioPlayer.currentTime))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                
                Spacer()
                
                Text(formatTime(audioPlayer.duration))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
    
    func progressWidth(_ totalWidth: CGFloat) -> CGFloat {
        guard audioPlayer.duration > 0 else { return 0 }
        let percent = audioPlayer.currentTime / audioPlayer.duration
        return CGFloat(percent) * totalWidth
    }
    
    // Дополнительные контролы
    var extraControls: some View {
        HStack(spacing: 0) {
            // Shuffle
            Button(action: {
                audioPlayer.toggleShuffle()
            }) {
                Image(systemName: "shuffle")
                    .font(.system(size: 22))
                    .foregroundColor(audioPlayer.isShuffle ? .red : .white.opacity(0.5))
            }
            .frame(width: 60)
            
            // Speed
            Button(action: {}) {
                Text(String(format: "%.1fx", audioPlayer.playbackSpeed))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(width: 50)
            
            Spacer()
            
            // Lyrics
            Button(action: { showLyrics.toggle() }) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 20))
                    .foregroundColor(showLyrics ? .red : .white.opacity(0.5))
            }
            .frame(width: 50)
            
            Spacer()
            
            // Repeat
            Button(action: {
                audioPlayer.toggleRepeat()
            }) {
                Image(systemName: repeatIcon)
                    .font(.system(size: 22))
                    .foregroundColor(audioPlayer.repeatMode != .off ? .red : .white.opacity(0.5))
            }
            .frame(width: 60)
        }
    }
    
    var repeatIcon: String {
        switch audioPlayer.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
    
    func formatTime(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", mins, secs)
    }
}

#Preview {
    PlayerView(isPresented: .constant(true))
        .environmentObject(AudioPlayer.shared)
        .environmentObject(DataManager.shared)
}
