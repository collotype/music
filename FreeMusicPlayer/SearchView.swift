//
//  SearchView.swift
//  FreeMusicPlayer
//
//  Поиск треков
//

import SwiftUI

struct SearchView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var audioPlayer: AudioPlayer
    @State private var searchText: String = ""
    @State private var searchResults: [Track] = []
    @State private var isSearching: Bool = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Поисковая строка
                    searchHeader
                    
                    // Результаты или пустое состояние
                    if searchText.isEmpty {
                        emptyState
                    } else if searchResults.isEmpty {
                        noResultsState
                    } else {
                        searchResultsList
                    }
                }
            }
            .navigationBarHidden(true)
        }
    }
    
    var searchHeader: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 16)
            
            // Поисковая строка
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white.opacity(0.5))
                
                TextField("Поиск треков и исполнителей", text: $searchText)
                    .font(.system(size: 17))
                    .foregroundColor(.white)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onChange(of: searchText) { newValue in
                        performSearch(newValue)
                    }
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        searchResults = []
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }
    
    var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "magnifyingglass")
                .font(.system(size: 80))
                .foregroundColor(.white.opacity(0.1))
            
            Text("Поиск")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white.opacity(0.3))
            
            Text("Найдите свои любимые треки")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.2))
            
            // Популярные запросы
            VStack(alignment: .leading, spacing: 12) {
                Text("Популярное")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
                
                FlowLayout {
                    ForEach(["Рок", "Поп", "Хип-хоп", "Электроника", "Джаз"], id: \.self) { query in
                        Button(action: {
                            searchText = query
                            performSearch(query)
                        }) {
                            Text(query)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.1))
                                )
                        }
                    }
                }
            }
            .padding(.top, 20)
            
            Spacer()
        }
        .padding(.horizontal, 20)
    }
    
    var noResultsState: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "note.slash")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.2))
            
            Text("Ничего не найдено")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
            
            Text("Попробуйте другой запрос")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.3))
            
            Spacer()
        }
    }
    
    var searchResultsList: some View {
        List(searchResults) { track in
            SearchTrackRow(track: track)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
        }
        .listStyle(.plain)
        .background(Color.black)
    }
    
    func performSearch(_ query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        
        // Поиск по локальной библиотеке
        searchResults = dataManager.tracks.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(query) ||
            $0.displayArtist.localizedCaseInsensitiveContains(query) ||
            ($0.album?.localizedCaseInsensitiveContains(query) ?? false)
        }
        
        isSearching = false
    }
}

// Строка результата поиска
struct SearchTrackRow: View {
    let track: Track
    @EnvironmentObject var audioPlayer: AudioPlayer
    @EnvironmentObject var dataManager: DataManager
    
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
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(track.displayArtist)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Длительность
            Text(track.formattedDuration)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
            
            // Кнопка воспроизведения
            Button(action: {
                audioPlayer.load(track: track)
                audioPlayer.play()
            }) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// Flow layout для тегов
struct FlowLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews)
        
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + 8
                    rowHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + 8
            }
            
            self.size = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}

#Preview {
    SearchView()
        .environmentObject(AudioPlayer.shared)
        .environmentObject(DataManager.shared)
}
