//
//  SettingsView.swift
//  FreeMusicPlayer
//
//  Настройки (как на референсе)
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var audioPlayer: AudioPlayer
    @State private var showClearConfirm: Bool = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                List {
                    // Основные
                    settingsSection(title: "Основные", icon: "gear") {
                        settingRow(title: "Основные", icon: "gearshape")
                        settingRow(title: "Хранилище", icon: "externaldrive")
                        settingRow(title: "Свайпы", icon: "hand.tap")
                    }
                    
                    // Внешний вид
                    settingsSection(title: "Внешний вид", icon: "paintbrush") {
                        settingRow(title: "Интерфейс", icon: "display")
                        settingRow(title: "Кастомизация", icon: "slider.horizontal.3")
                        settingRow(title: "Плеер", icon: "play.circle")
                        settingRow(title: "Обложка", icon: "photo")
                    }
                    
                    // Интеграции
                    settingsSection(title: "Интеграции", icon: "link") {
                        settingRow(title: "Прокси", icon: "shield")
                        settingRow(title: "Last.fm", icon: "waveform")
                    }
                    
                    // Сервисы
                    settingsSection(title: "Сервисы", icon: "cloud") {
                        settingRow(title: "YouTube Music", icon: "play.circle", configured: true)
                        settingRow(title: "SoundCloud", icon: "cloud")
                        settingRow(title: "Spotify", icon: "sparkles")
                    }
                    
                    // Хранилище
                    settingsSection(title: "Хранилище", icon: "externaldrive") {
                        storageInfoRow
                        
                        Button(action: { showClearConfirm = true }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Очистить кеш")
                                        .foregroundColor(.white)
                                    Text("Удалить все кэшированные файлы")
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    
                    // О приложении
                    settingsSection(title: "О приложении", icon: "info.circle") {
                        HStack {
                            Text("Версия")
                                .foregroundColor(.white)
                            Spacer()
                            Text("1.0.0")
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 12)
                        
                        Button(action: {}) {
                            HStack {
                                Text("Открыть исходный код")
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .background(Color.black)
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.large)
        }
        .accentColor(.white)
        .alert("Очистка данных", isPresented: $showClearConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Очистить", role: .destructive) {
                dataManager.clearAllData()
                audioPlayer.stop()
            }
        } message: {
            Text("Это действие удалит все треки, плейлисты и настройки. Продолжить?")
        }
    }
    
    func settingsSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Section {
            content()
        } header: {
            Label(title, systemImage: icon)
                .foregroundColor(.gray)
                .font(.system(size: 13, weight: .semibold))
        }
    }
    
    func settingRow(title: String, icon: String, configured: Bool = false) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.white)
                .frame(width: 30)
            
            Text(title)
                .foregroundColor(.white)
            
            Spacer()
            
            if configured {
                Text("Подключено")
                    .font(.system(size: 12))
                    .foregroundColor(.green)
            }
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding(.vertical, 12)
    }
    
    var storageInfoRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Занято")
                        .foregroundColor(.white)
                    Text("0 MB")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Всего")
                        .foregroundColor(.gray)
                    Text("∞")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.gray)
                }
            }
            
            // Прогресс бар
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.red, Color.orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 0, height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding(.vertical, 12)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AudioPlayer.shared)
        .environmentObject(DataManager.shared)
}
