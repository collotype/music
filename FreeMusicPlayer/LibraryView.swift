//
//  LibraryView.swift
//  FreeMusicPlayer
//
//  Библиотека (как на референсе "Любимые")
//

import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var audioPlayer: AudioPlayer
    @State private var showingImporter = false
    @State private var selectedFilter: LibraryFilter = .all
    @State private var searchText: String = ""
    
    var filteredTracks: [Track] {
        var tracks = dataManager.tracks
        
        // Фильтр по категории
        switch selectedFilter {
        case .all:
            break
        case .favorites:
            tracks = dataManager.favoriteTracks
        case .offline:
            tracks = tracks.filter { $0.fileURL != nil }
        case .playlists:
            return [] // Отдельная секция
        }
        
        // Поиск
        if !searchText.isEmpty {
            tracks = tracks.filter {
                $0.displayTitle.localizedCaseInsensitiveContains(searchText) ||
                $0.displayArtist.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return tracks
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Заголовок с градиентом как на референсе
                headerSection
                
                // Фильтры
                filterSection
                
                // Список треков
                trackListSection
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
    }
    
    // Заголовок
    var headerSection: some View {
        ZStack {
            // Градиентный фон как на референсе
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.8, green: 0.15, blue: 0.15),
                    Color(red: 0.4, green: 0.1, blue: 0.1),
                    Color.black
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 16) {
                // Верхняя панель
                HStack {
                    Button(action: {}) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    Button(action: {}) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.trailing, 16)
                    
                    Button(action: {}) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.trailing, 16)
                    
                    Button(action: {}) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                Spacer()
                
                // Заголовок
                VStack(alignment: .leading, spacing: 4) {
                    switch selectedFilter {
                    case .all:
                        Text("Медиатека")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.white)
                        Text("\(filteredTracks.count) треков")
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.7))
                    case .favorites:
                        Text("Любимые")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.white)
                        Text("\(filteredTracks.count) треков")
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.7))
                    case .offline:
                        Text("Офлайн")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.white)
                        Text("\(filteredTracks.count) треков")
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.7))
                    case .playlists:
                        Text("Плейлисты")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                
                // Кнопки действий
                HStack(spacing: 12) {
                    Button(action: {
                        if let first = filteredTracks.first {
                            audioPlayer.load(track: first)
                            audioPlayer.play()
                        }
                    }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Воспроизвести")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(Color.white)
                        )
                    }
                    
                    Button(action: {
                        dataManager.tracks.shuffle()
                    }) {
                        HStack {
                            Image(systemName: "shuffle")
                            Text("Перемешать")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.15))
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .frame(height: 280)
    }
    
    // Фильтры
    var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryFilter.allCases, id: \.self) { filter in
                    FilterChip(
                        title: filter.title,
                        isSelected: selectedFilter == filter,
                        count: filterCount(for: filter)
                    ) {
                        selectedFilter = filter
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
    
    // Список треков
    var trackListSection: some View {
        Group {
            if filteredTracks.isEmpty {
                emptyStateView
            } else {
                List {
                    ForEach(filteredTracks) { track in
                        LibraryTrackRow(track: track)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                .listStyle(.plain)
                .background(Color.black)
            }
        }
    }
    
    var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.2))
            
            Text("Медиатека пуста")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
            
            Text("Загрузите треки чтобы начать")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.3))
            
            Button(action: { showingImporter = true }) {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                    Text("Загрузить треки")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.15))
                )
            }
        }
        .padding(.top, 100)
    }
    
    func filterCount(for filter: LibraryFilter) -> Int {
        switch filter {
        case .all:
            return dataManager.tracks.count
        case .favorites:
            return dataManager.favoriteTracks.count
        case .offline:
            return dataManager.tracks.filter { $0.fileURL != nil }.count
        case .playlists:
            return dataManager.playlists.count
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let importedTracks = urls.compactMap(importTrack)
            guard !importedTracks.isEmpty else { return }
            dataManager.addTracks(importedTracks)
        case .failure:
            break
        }
    }

    private func importTrack(from url: URL) -> Track? {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }

        let destinationURL = uniqueDestinationURL(
            in: documentsDirectory,
            originalFilename: url.lastPathComponent
        )

        do {
            try FileManager.default.copyItem(at: url, to: destinationURL)
        } catch {
            return nil
        }

        let asset = AVURLAsset(url: destinationURL)
        let title = metadataValue(for: asset, identifier: .commonIdentifierTitle)
            ?? destinationURL.deletingPathExtension().lastPathComponent
        let artist = metadataValue(for: asset, identifier: .commonIdentifierArtist)
            ?? "Unknown Artist"
        let album = metadataValue(for: asset, identifier: .commonIdentifierAlbumName)
        let duration = max(CMTimeGetSeconds(asset.duration), 0)

        return Track(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            fileURL: destinationURL.lastPathComponent,
            coverArtURL: nil,
            source: .local
        )
    }

    private func metadataValue(for asset: AVURLAsset, identifier: AVMetadataIdentifier) -> String? {
        asset.commonMetadata
            .first(where: { $0.identifier == identifier })?
            .stringValue
    }

    private func uniqueDestinationURL(in directory: URL, originalFilename: String) -> URL {
        let sanitizedName = originalFilename.isEmpty ? UUID().uuidString + ".mp3" : originalFilename
        let baseURL = directory.appendingPathComponent(sanitizedName)

        guard FileManager.default.fileExists(atPath: baseURL.path) else {
            return baseURL
        }

        let baseName = baseURL.deletingPathExtension().lastPathComponent
        let fileExtension = baseURL.pathExtension

        for index in 1...999 {
            let candidateName = fileExtension.isEmpty
                ? "\(baseName)-\(index)"
                : "\(baseName)-\(index).\(fileExtension)"
            let candidateURL = directory.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return directory.appendingPathComponent(UUID().uuidString + "-" + sanitizedName)
    }
}

enum LibraryFilter: CaseIterable {
    case all
    case favorites
    case offline
    case playlists
    
    var title: String {
        switch self {
        case .all: return "Все"
        case .favorites: return "Любимые"
        case .offline: return "Офлайн"
        case .playlists: return "Плейлисты"
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let count: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                if count > 0 {
                    Text("(\(count))")
                        .font(.system(size: 13))
                }
            }
            .foregroundColor(isSelected ? .black : .white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.white : Color.white.opacity(0.1))
            )
        }
    }
}

struct LibraryTrackRow: View {
    let track: Track
    @EnvironmentObject var audioPlayer: AudioPlayer
    @EnvironmentObject var dataManager: DataManager
    
    var isPlaying: Bool {
        audioPlayer.currentTrack?.id == track.id && audioPlayer.isPlaying
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Обложка с иконкой платформы
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 56, height: 56)
                
                Image(systemName: "music.note")
                    .foregroundColor(.white.opacity(0.3))
                
                // Иконка источника
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: track.source == .youtube ? "play.circle.fill" : "cloud.fill")
                            .font(.system(size: 14))
                            .foregroundColor(track.source == .youtube ? .red : .orange)
                            .background(Circle().fill(Color.black))
                    }
                    .padding(4)
                }
            }
            
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
            
            // Избранное
            Button(action: {
                dataManager.toggleFavorite(track)
            }) {
                Image(systemName: dataManager.favorites.contains(track.id) ? "heart.fill" : "heart")
                    .foregroundColor(dataManager.favorites.contains(track.id) ? .red : .white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            audioPlayer.load(track: track)
            audioPlayer.play()
        }
    }
}

#Preview {
    LibraryView()
        .environmentObject(AudioPlayer.shared)
        .environmentObject(DataManager.shared)
}
