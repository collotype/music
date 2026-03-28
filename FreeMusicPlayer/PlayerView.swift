//
//  PlayerView.swift
//  FreeMusicPlayer
//
//  Full screen player.
//

import AVFoundation
import SwiftUI

struct PlayerView: View {
    @EnvironmentObject var audioPlayer: AudioPlayer
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var router: AppRouter
    @Binding var isPresented: Bool
    @State private var showLyrics: Bool = false
    @State private var showEQ: Bool = false
    @State private var isTogglingFavorite = false
    @State private var favoriteActionErrorMessage: String?
    
    var body: some View {
        ZStack {
            playerBackground
            
            VStack(spacing: 0) {
                playerHeader
                Spacer()
                albumArt
                Spacer()
                playerControls
            }
        }
        .onAppear {
            debugLog("Player background stack composed: artwork backdrop -> blur -> dark tint -> foreground UI")
        }
        .onChange(of: audioPlayer.currentTrack?.id) { _ in
            debugLog("Player background updated for track: \(audioPlayer.currentTrack?.displayTitle ?? "none")")
        }
        .sheet(isPresented: $showEQ) {
            PlayerPlaceholderSheet(
                title: "Equalizer",
                description: "The button is wired up and ready for a real EQ screen."
            )
        }
        .sheet(isPresented: $showLyrics) {
            PlayerLyricsSheet(track: audioPlayer.currentTrack)
        }
        .alert("Favorites Unavailable", isPresented: favoriteActionErrorIsPresented) {
            Button("OK", role: .cancel) {
                favoriteActionErrorMessage = nil
            }
        } message: {
            Text(favoriteActionErrorMessage ?? "This track could not be updated in your library.")
        }
    }

    private var playerBackground: some View {
        ZStack {
            TrackArtworkBackdrop(
                track: audioPlayer.currentTrack,
                fallbackPalette: .playerFallback
            )
            .scaleEffect(1.08)
            .blur(radius: 34)
            .opacity(0.96)

            TrackArtworkBackdrop(
                track: audioPlayer.currentTrack,
                fallbackPalette: .playerFallback
            )
            .opacity(0.34)

            Rectangle()
                .fill(Color.black.opacity(0.18))

            LinearGradient(
                colors: [
                    Color.black.opacity(0.22),
                    Color.black.opacity(0.34),
                    Color.black.opacity(0.58),
                    Color.black.opacity(0.74)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
    
    var playerHeader: some View {
        HStack {
            Button {
                debugLog("Player dismiss button pressed")
                withAnimation(.spring(response: 0.3)) {
                    isPresented = false
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Text("NOW PLAYING")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
            
            Spacer()
            
            Button {
                debugLog("Player EQ button pressed")
                showEQ = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
    
    var albumArt: some View {
        VStack(spacing: 20) {
            ZStack {
                if let currentTrack = audioPlayer.currentTrack {
                    TrackArtworkBackdrop(
                        track: currentTrack,
                        fallbackPalette: .playerFallback,
                        cornerRadius: 34
                    )
                    .frame(width: 340, height: 340)
                    .blur(radius: 42)
                    .opacity(0.68)

                    TrackArtworkView(track: currentTrack, size: 320, cornerRadius: 24, showsSourceBadge: false)
                        .aspectRatio(1, contentMode: .fit)
                        .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
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
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40)
            
            VStack(spacing: 8) {
                Text(audioPlayer.currentTrack?.displayTitle ?? "Unknown Track")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                if let currentArtistRoute {
                    Button {
                        openArtistPage(currentArtistRoute)
                    } label: {
                        HStack(spacing: 6) {
                            Text(currentArtistRoute.artistName)
                                .lineLimit(1)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.72))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(audioPlayer.currentTrack?.displayArtist ?? "Unknown Artist")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            HStack(spacing: 24) {
                Button {
                    debugLog("Player previous button pressed")
                    audioPlayer.playPrevious()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                
                Button {
                    debugLog("Player play/pause button pressed")
                    audioPlayer.togglePlayPause()
                } label: {
                    Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                
                Button {
                    debugLog("Player next button pressed")
                    audioPlayer.playNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        }
    }
    
    var playerControls: some View {
        VStack(spacing: 20) {
            progressSection
            extraControls
            Spacer(minLength: 20)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
    }
    
    var progressSection: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 4)
                    
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
    
    var extraControls: some View {
        HStack(spacing: 0) {
            Button {
                debugLog("Player shuffle button pressed")
                audioPlayer.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 22))
                    .foregroundColor(audioPlayer.isShuffle ? .red : .white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .frame(width: 60)
            
            Button {
                debugLog("Player speed button pressed")
                audioPlayer.cyclePlaybackSpeed()
            } label: {
                Text(String(format: "%.2gx", audioPlayer.playbackSpeed))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .frame(width: 50)
            
            Spacer()

            Button {
                toggleFavoriteForCurrentTrack()
            } label: {
                if isTogglingFavorite {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: favoriteButtonSystemImage)
                        .font(.system(size: 20))
                        .foregroundColor(favoriteButtonTintColor)
                }
            }
            .buttonStyle(.plain)
            .frame(width: 50)
            .disabled(!canToggleFavoriteForCurrentTrack || isTogglingFavorite)

            Spacer()

            Button {
                debugLog("Player lyrics button pressed")
                showLyrics = true
            } label: {
                Image(systemName: "text.bubble")
                    .font(.system(size: 20))
                    .foregroundColor(showLyrics ? .red : .white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .frame(width: 50)
            
            Spacer()
            
            Button {
                debugLog("Player repeat button pressed")
                audioPlayer.toggleRepeat()
            } label: {
                Image(systemName: repeatIcon)
                    .font(.system(size: 22))
                    .foregroundColor(audioPlayer.repeatMode != .off ? .red : .white.opacity(0.5))
            }
            .buttonStyle(.plain)
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
        guard time.isFinite else { return "0:00" }
        let mins = Int(time) / 60
        let secs = Int(time.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", mins, secs)
    }

    private var currentArtistRoute: OnlineArtistRoute? {
        audioPlayer.currentTrack?.onlineArtistRoute
    }

    private var currentTrackIsSaved: Bool {
        guard let currentTrack = audioPlayer.currentTrack else { return false }
        return dataManager.isTrackSaved(currentTrack)
    }

    private var canToggleFavoriteForCurrentTrack: Bool {
        guard let currentTrack = audioPlayer.currentTrack else { return false }

        if dataManager.isTrackSaved(currentTrack) {
            return true
        }

        return currentTrack.source == .soundcloud && currentTrack.sourceID != nil
    }

    private var favoriteButtonSystemImage: String {
        guard canToggleFavoriteForCurrentTrack else { return "heart.slash" }
        return currentTrackIsSaved ? "heart.fill" : "heart"
    }

    private var favoriteButtonTintColor: Color {
        guard canToggleFavoriteForCurrentTrack else { return .white.opacity(0.24) }
        return currentTrackIsSaved ? .red : .white.opacity(0.7)
    }

    private var favoriteActionErrorIsPresented: Binding<Bool> {
        Binding(
            get: { favoriteActionErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    favoriteActionErrorMessage = nil
                }
            }
        )
    }

    private func openArtistPage(_ route: OnlineArtistRoute) {
        debugLog("Player artist pressed: \(route.artistName) [\(route.providerArtistID)]")

        withAnimation(.spring(response: 0.3)) {
            isPresented = false
        }

        Task { @MainActor in
            await Task.yield()
            router.openOnlineArtist(route)
        }
    }

    private func toggleFavoriteForCurrentTrack() {
        guard let currentTrack = audioPlayer.currentTrack,
              canToggleFavoriteForCurrentTrack,
              !isTogglingFavorite else {
            return
        }

        isTogglingFavorite = true
        favoriteActionErrorMessage = nil

        Task {
            defer {
                Task { @MainActor in
                    isTogglingFavorite = false
                }
            }

            do {
                let savedTrack = try await dataManager.toggleTrackSavedState(for: currentTrack)

                await MainActor.run {
                    if let savedTrack {
                        audioPlayer.syncCurrentTrackReference(with: savedTrack)
                    }
                }
            } catch {
                debugLog("Player favorite toggle failed: \(error.localizedDescription)")
                await MainActor.run {
                    favoriteActionErrorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct PlayerPlaceholderSheet: View {
    let title: String
    let description: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(description)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding()
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct PlayerLyricsSheet: View {
    let track: Track?

    var body: some View {
        NavigationStack {
            TrackLyricsView(track: track)
                .navigationTitle("Lyrics")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        DismissButton()
                    }
                }
        }
    }
}

struct TrackLyricsView: View {
    let track: Track?

    @EnvironmentObject private var dataManager: DataManager

    @State private var lyricsText: String?
    @State private var lyricsSourceLabel: String?
    @State private var isLoadingLyrics = false

    private var trackIdentity: String {
        track?.sourceID ?? track?.id ?? "no-track"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track?.displayTitle ?? "Nothing playing")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                        Text(track?.displayArtist ?? "")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                    }

                    if isLoadingLyrics {
                        HStack(spacing: 12) {
                            ProgressView()
                                .tint(.white)
                            Text("Loading lyrics...")
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(.top, 12)
                    } else if let lyricsText {
                        VStack(alignment: .leading, spacing: 12) {
                            if let lyricsSourceLabel {
                                Text(lyricsSourceLabel)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.48))
                            }

                            Text(lyricsText)
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.9))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.top, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Lyrics unavailable")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                            Text("No saved, embedded, or online lyrics were found for this track.")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.58))
                        }
                        .padding(.top, 12)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        }
        .task(id: trackIdentity) {
            await loadLyrics()
        }
    }

    @MainActor
    private func loadLyrics() async {
        guard let track else {
            lyricsText = nil
            lyricsSourceLabel = nil
            isLoadingLyrics = false
            debugLog("Lyrics unavailable because there is no current track")
            return
        }

        if let storedLyrics = cleanedLyricsText(track.lyricsText) {
            lyricsText = storedLyrics
            lyricsSourceLabel = lyricsSourceLabel(for: track.lyricsSource)
        }

        isLoadingLyrics = true
        let currentIdentity = trackIdentity
        let resolvedLyrics = await LyricsMetadataResolver.shared.resolvedLyrics(for: track)

        guard currentIdentity == trackIdentity else { return }

        lyricsText = resolvedLyrics?.text
        lyricsSourceLabel = resolvedLyrics.flatMap { lyricsSourceLabel(for: $0.source) }
        isLoadingLyrics = false
        if let resolvedLyrics {
            _ = dataManager.persistLyrics(resolvedLyrics, for: track)
        }
        debugLog("Lyrics \(resolvedLyrics == nil ? "unavailable" : "loaded") for \(track.displayTitle)")
    }

    private func cleanedLyricsText(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleanedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedValue.isEmpty ? nil : cleanedValue
    }

    private func lyricsSourceLabel(for source: String?) -> String? {
        guard let source = source?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !source.isEmpty else {
            return nil
        }

        switch source {
        case "embedded":
            return "Embedded lyrics"
        case "genius":
            return "Lyrics from Genius"
        case "lrclib":
            return "Lyrics via LRCLIB"
        case "lyricsovh":
            return "Lyrics via Lyrics.ovh"
        default:
            return source.capitalized
        }
    }
}

private struct DismissButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Close") {
            dismiss()
        }
    }
}

struct ResolvedTrackLyrics: Equatable {
    let text: String
    let source: String
    let url: String?
    let lastUpdated: Date
}

actor LyricsMetadataResolver {
    static let shared = LyricsMetadataResolver()

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()
    private let browserUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    private var resolvedLyricsCache: [String: ResolvedTrackLyrics] = [:]

    func resolvedLyrics(for track: Track) async -> ResolvedTrackLyrics? {
        if let persistedLyrics = persistedLyrics(for: track) {
            return persistedLyrics
        }

        let cacheKey = lyricsCacheKey(for: track)
        if let cachedLyrics = resolvedLyricsCache[cacheKey] {
            return cachedLyrics
        }

        guard let fileURL = localFileURL(for: track),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            if let resolvedNetworkLyrics = await resolvedNetworkLyrics(for: track) {
                resolvedLyricsCache[cacheKey] = resolvedNetworkLyrics
                return resolvedNetworkLyrics
            }
            return nil
        }

        let asset = AVURLAsset(url: fileURL)
        if let metadataLyrics = metadataLyrics(from: asset) {
            let resolvedLyrics = ResolvedTrackLyrics(
                text: metadataLyrics,
                source: "embedded",
                url: nil,
                lastUpdated: Date()
            )
            resolvedLyricsCache[cacheKey] = resolvedLyrics
            return resolvedLyrics
        }

        if let resolvedNetworkLyrics = await resolvedNetworkLyrics(for: track) {
            resolvedLyricsCache[cacheKey] = resolvedNetworkLyrics
            return resolvedNetworkLyrics
        }

        return nil
    }

    private func localFileURL(for track: Track) -> URL? {
        guard let fileURL = track.fileURL else { return nil }

        if let parsedURL = URL(string: fileURL),
           parsedURL.isFileURL {
            return parsedURL
        }

        if URL(string: fileURL)?.scheme != nil {
            return nil
        }

        return AppFileManager.shared.resolveStoredFileURL(for: fileURL)
    }

    private func persistedLyrics(for track: Track) -> ResolvedTrackLyrics? {
        guard let lyricsText = cleanedLyricsText(track.lyricsText) else { return nil }

        return ResolvedTrackLyrics(
            text: lyricsText,
            source: cleanedLyricsText(track.lyricsSource) ?? "saved",
            url: cleanedLyricsText(track.lyricsURL),
            lastUpdated: track.lyricsLastUpdated ?? Date()
        )
    }

    private func lyricsCacheKey(for track: Track) -> String {
        let identity = track.sourceID ?? track.id
        return "\(identity)::\(normalizedComparisonText(track.displayArtist))::\(normalizedComparisonText(track.displayTitle))"
    }

    private func metadataLyrics(from asset: AVURLAsset) -> String? {
        let metadataCollections = [asset.commonMetadata] + asset.availableMetadataFormats.map { asset.metadata(forFormat: $0) }

        for items in metadataCollections {
            for item in items {
                let identifier = item.identifier?.rawValue.lowercased() ?? ""
                let commonKey = item.commonKey?.rawValue.lowercased() ?? ""

                guard identifier.contains("lyric") || commonKey.contains("lyric") else {
                    continue
                }

                if let cleanedString = cleanedLyricsText(item.stringValue) {
                    return cleanedString
                }

                if let value = item.value as? String,
                   let cleanedValue = cleanedLyricsText(value) {
                    return cleanedValue
                }

                if let dataValue = item.dataValue {
                    for encoding in [String.Encoding.utf8, .utf16, .unicode, .isoLatin1] {
                        if let decodedValue = String(data: dataValue, encoding: encoding),
                           let cleanedValue = cleanedLyricsText(decodedValue) {
                            return cleanedValue
                        }
                    }
                }
            }
        }

        return nil
    }

    private func resolvedNetworkLyrics(for track: Track) async -> ResolvedTrackLyrics? {
        guard let lookupMetadata = lookupMetadata(for: track) else {
            debugLog("Lyrics lookup skipped for \(track.displayTitle): insufficient artist/title metadata")
            return nil
        }

        if let geniusLyrics = await geniusLyrics(using: lookupMetadata) {
            return geniusLyrics
        }

        if let lrcLibLyrics = await lrcLibLyrics(using: lookupMetadata) {
            return lrcLibLyrics
        }

        if let lyricsOVH = await lyricsOVHLyrics(using: lookupMetadata) {
            return lyricsOVH
        }

        return nil
    }

    private func geniusLyrics(using lookupMetadata: LyricsLookupMetadata) async -> ResolvedTrackLyrics? {
        for searchQuery in lookupMetadata.geniusSearchQueries {
            guard let encodedQuery = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let searchURL = URL(string: "https://genius.com/api/search/multi?per_page=8&q=\(encodedQuery)") else {
                continue
            }

            do {
                let searchData = try await fetchData(from: searchURL)
                guard let response = try? JSONDecoder().decode(GeniusSearchEnvelope.self, from: searchData),
                      let bestMatch = bestGeniusMatch(
                        forTitleCandidates: lookupMetadata.normalizedTitleCandidates,
                        artistCandidates: lookupMetadata.normalizedArtistCandidates,
                        in: response.response.sections.flatMap { $0.hits ?? [] }
                      ) else {
                    continue
                }

                let lyricsPageURLString = cleanedLyricsText(bestMatch.url) ??
                    cleanedLyricsText(bestMatch.path).map { "https://genius.com\($0)" }

                guard let lyricsPageURLString,
                      let lyricsPageURL = URL(string: lyricsPageURLString) else {
                    continue
                }

                let pageHTML = try await fetchHTML(from: lyricsPageURL)
                guard let lyricsHTML = extractLyricsHTML(from: pageHTML),
                      let lyricsText = plainTextLyrics(fromHTML: lyricsHTML) else {
                    continue
                }

                return ResolvedTrackLyrics(
                    text: lyricsText,
                    source: "genius",
                    url: lyricsPageURLString,
                    lastUpdated: Date()
                )
            } catch {
                debugLog("Genius lyrics lookup failed for query \(searchQuery): \(error.localizedDescription)")
                return nil
            }
        }

        return nil
    }

    private func lrcLibLyrics(using lookupMetadata: LyricsLookupMetadata) async -> ResolvedTrackLyrics? {
        for query in lookupMetadata.providerQueries {
            guard var components = URLComponents(string: "https://lrclib.net/api/get") else {
                continue
            }

            components.queryItems = [
                URLQueryItem(name: "artist_name", value: query.artist),
                URLQueryItem(name: "track_name", value: query.title)
            ]

            guard let requestURL = components.url else { continue }

            do {
                let data = try await fetchData(from: requestURL)
                let result = try JSONDecoder().decode(LRCLibLyricsResult.self, from: data)
                guard let lyricsText = cleanedLyricsText(result.plainLyrics) ??
                        cleanedLyricsText(result.syncedLyrics).flatMap(strippedSyncedLyrics(from:)) else {
                    continue
                }

                debugLog("Lyrics resolved through LRCLIB for \(query.artist) - \(query.title)")
                return ResolvedTrackLyrics(
                    text: lyricsText,
                    source: "lrclib",
                    url: result.url,
                    lastUpdated: Date()
                )
            } catch {
                continue
            }
        }

        return nil
    }

    private func lyricsOVHLyrics(using lookupMetadata: LyricsLookupMetadata) async -> ResolvedTrackLyrics? {
        let pathAllowedCharacterSet = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))

        for query in lookupMetadata.providerQueries {
            guard let encodedArtist = query.artist.addingPercentEncoding(withAllowedCharacters: pathAllowedCharacterSet),
                  let encodedTitle = query.title.addingPercentEncoding(withAllowedCharacters: pathAllowedCharacterSet),
                  let requestURL = URL(string: "https://api.lyrics.ovh/v1/\(encodedArtist)/\(encodedTitle)") else {
                continue
            }

            do {
                let data = try await fetchData(from: requestURL)
                let result = try JSONDecoder().decode(LyricsOVHResponse.self, from: data)
                guard let lyricsText = cleanedLyricsText(result.lyrics) else {
                    continue
                }

                debugLog("Lyrics resolved through Lyrics.ovh for \(query.artist) - \(query.title)")
                return ResolvedTrackLyrics(
                    text: lyricsText,
                    source: "lyricsovh",
                    url: nil,
                    lastUpdated: Date()
                )
            } catch {
                continue
            }
        }

        return nil
    }

    private func fetchData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return data
    }

    private func fetchHTML(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode) else {
            throw URLError(.cannotDecodeContentData)
        }

        return html
    }

    private func bestGeniusMatch(
        forTitleCandidates titleCandidates: Set<String>,
        artistCandidates: Set<String>,
        in hits: [GeniusSearchHit]
    ) -> GeniusSongHitResult? {
        hits.compactMap { hit -> (result: GeniusSongHitResult, score: Int, titleScore: Int, artistScore: Int)? in
            let result = hit.result
            guard let title = cleanedLyricsText(result.title),
                  cleanedLyricsText(result.path) != nil || cleanedLyricsText(result.url) != nil else {
                return nil
            }

            let candidateTitleScore = comparisonScore(
                expectedCandidates: titleCandidates,
                actualCandidates: normalizedTitleCandidates(
                    for: [
                        title,
                        result.fullTitle,
                        result.titleWithFeatured
                    ]
                    .compactMap { $0 }
                    .joined(separator: " ")
                )
            )
            let candidateArtistScore = comparisonScore(
                expectedCandidates: artistCandidates,
                actualCandidates: normalizedArtistCandidates(
                    for: [
                        result.artistNames,
                        result.primaryArtist?.name
                    ]
                    .compactMap { $0 }
                    .joined(separator: ", ")
                )
            )
            var score = candidateTitleScore + candidateArtistScore

            if result.lyricsState?.lowercased() == "complete" {
                score += 10
            }

            if hasVersionMismatch(expectedCandidates: titleCandidates, candidateTitle: title) {
                score -= 25
            }

            guard candidateTitleScore >= 58 else {
                return nil
            }

            guard candidateArtistScore >= 34 || candidateTitleScore >= 94 else {
                return nil
            }

            return (result, score, candidateTitleScore, candidateArtistScore)
        }
        .sorted { left, right in
            if left.score != right.score {
                return left.score > right.score
            }

            if left.titleScore != right.titleScore {
                return left.titleScore > right.titleScore
            }

            return left.artistScore > right.artistScore
        }
        .first?.result
    }

    private func comparisonScore(expectedCandidates: Set<String>, actualCandidates: Set<String>) -> Int {
        guard !expectedCandidates.isEmpty, !actualCandidates.isEmpty else { return 0 }

        if !expectedCandidates.intersection(actualCandidates).isEmpty {
            return 100
        }

        if expectedCandidates.contains(where: { expected in
            actualCandidates.contains(where: { actual in
                expected.count > 4 && actual.count > 4 && (expected.contains(actual) || actual.contains(expected))
            })
        }) {
            return 82
        }

        let expectedTokens = Set(expectedCandidates.flatMap { $0.split(separator: " ").map(String.init) })
        let actualTokens = Set(actualCandidates.flatMap { $0.split(separator: " ").map(String.init) })
        let sharedTokens = expectedTokens.intersection(actualTokens)
        let tokenOverlapRatio = Int(
            (
                Double(sharedTokens.count) /
                Double(max(1, min(expectedTokens.count, actualTokens.count)))
            ) * 100
        )

        if tokenOverlapRatio >= 90 {
            return 92
        }

        if tokenOverlapRatio >= 72 {
            return 78
        }

        if tokenOverlapRatio >= 55 {
            return 64
        }

        if sharedTokens.count >= min(3, max(1, expectedTokens.count)) {
            return 64
        }

        if sharedTokens.count >= 2 {
            return 56
        }

        return 0
    }

    private func normalizedTitleCandidates(for title: String) -> Set<String> {
        Set(titleSearchVariants(for: title).map(normalizedComparisonText).filter { !$0.isEmpty })
    }

    private func normalizedArtistCandidates(for artist: String) -> Set<String> {
        Set(artistSearchVariants(for: artist).map(normalizedComparisonText).filter { !$0.isEmpty })
    }

    private func normalizedComparisonText(_ value: String) -> String {
        let strippedValue = value
            .replacingOccurrences(of: "\u{0451}", with: "\u{0435}")
            .replacingOccurrences(of: #"(feat\.?|ft\.?|featuring)\s+.+$"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)(prod\.?|produced by)\s+.+$"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)(official audio|official video|lyrics video|lyric video|visualizer|nightcore|sped up|slowed(?:\s*\+\s*reverb)?|remix|mix|edit|live|version|remaster(ed)?)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\[[^\]]*\]|\([^)]*\)|\{[^}]*\}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        return strippedValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func hasVersionMismatch(expectedCandidates: Set<String>, candidateTitle: String) -> Bool {
        let normalizedCandidateTitle = candidateTitle.lowercased()
        let versionMarkers = ["live", "remix", "edit", "sped up", "slowed", "remaster"]

        return versionMarkers.contains { marker in
            normalizedCandidateTitle.contains(marker) &&
                !expectedCandidates.contains(where: { $0.contains(marker) })
        }
    }

    private func extractLyricsHTML(from pageHTML: String) -> String? {
        let lowercasedHTML = pageHTML.lowercased()
        if lowercasedHTML.contains("cloudflare_error.challenge") ||
            lowercasedHTML.contains("make sure you're a human") {
            return nil
        }

        if let preloadedStateLyricsHTML = extractLyricsHTMLFromPreloadedState(from: pageHTML) {
            return preloadedStateLyricsHTML
        }

        return extractLyricsHTMLFromContainers(from: pageHTML)
    }

    private func extractLyricsHTMLFromPreloadedState(from pageHTML: String) -> String? {
        let marker = "window.__PRELOADED_STATE__ = JSON.parse('"
        guard let markerRange = pageHTML.range(of: marker) else {
            return nil
        }

        let stateStartIndex = markerRange.upperBound
        var stateEndIndex = stateStartIndex
        var isEscaped = false

        while stateEndIndex < pageHTML.endIndex {
            let currentCharacter = pageHTML[stateEndIndex]

            if currentCharacter == "'" && !isEscaped {
                break
            }

            isEscaped = currentCharacter == "\\" && !isEscaped
            if currentCharacter != "\\" {
                isEscaped = false
            }
            stateEndIndex = pageHTML.index(after: stateEndIndex)
        }

        guard stateEndIndex < pageHTML.endIndex else {
            return nil
        }

        let escapedJSON = String(pageHTML[stateStartIndex..<stateEndIndex])
        let wrappedJSONString = "\"\(escapedJSON)\""

        guard let decodedJSONString = try? JSONDecoder().decode(String.self, from: Data(wrappedJSONString.utf8)),
              let pageStateData = decodedJSONString.data(using: .utf8),
              let pageState = try? JSONDecoder().decode(GeniusSongPageState.self, from: pageStateData) else {
            return nil
        }

        return cleanedLyricsText(pageState.songPage?.lyricsData?.body?.html)
    }

    private func extractLyricsHTMLFromContainers(from pageHTML: String) -> String? {
        let pattern = #"<div[^>]*data-lyrics-container=\"true\"[^>]*>(.*?)</div>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let range = NSRange(pageHTML.startIndex..., in: pageHTML)
        let snippets = regex.matches(in: pageHTML, options: [], range: range).compactMap { match -> String? in
            guard let captureRange = Range(match.range(at: 1), in: pageHTML) else {
                return nil
            }

            return String(pageHTML[captureRange])
        }

        guard !snippets.isEmpty else {
            return nil
        }

        return cleanedLyricsText(snippets.joined(separator: "<br><br>"))
    }

    private func plainTextLyrics(fromHTML html: String) -> String? {
        guard let data = html.data(using: .utf8),
              let attributedString = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return cleanedLyricsText(html
                .replacingOccurrences(of: "<br>", with: "\n")
                .replacingOccurrences(of: "<br/>", with: "\n")
                .replacingOccurrences(of: "<br />", with: "\n"))
        }

        return cleanedLyricsText(
            attributedString.string.replacingOccurrences(
                of: #"\n{3,}"#,
                with: "\n\n",
                options: .regularExpression
            )
        )
    }

    private func cleanedLyricsText(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleanedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedValue.isEmpty ? nil : cleanedValue
    }

    private func lookupMetadata(for track: Track) -> LyricsLookupMetadata? {
        let titleVariants = titleSearchVariants(for: track.displayTitle)
        let artistVariants = artistSearchVariants(for: track.displayArtist)
        let normalizedTitleCandidates = Set(titleVariants.map(normalizedComparisonText).filter { !$0.isEmpty })
        let normalizedArtistCandidates = Set(artistVariants.map(normalizedComparisonText).filter { !$0.isEmpty })

        guard !titleVariants.isEmpty,
              !artistVariants.isEmpty,
              !normalizedTitleCandidates.isEmpty,
              !normalizedArtistCandidates.isEmpty else {
            return nil
        }

        return LyricsLookupMetadata(
            titleVariants: titleVariants,
            artistVariants: artistVariants,
            normalizedTitleCandidates: normalizedTitleCandidates,
            normalizedArtistCandidates: normalizedArtistCandidates
        )
    }

    private func titleSearchVariants(for title: String) -> [String] {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return [] }

        let strippedBracketedTitle = trimmedTitle.replacingOccurrences(
            of: #"\[[^\]]*\]|\([^)]*\)|\{[^}]*\}"#,
            with: " ",
            options: .regularExpression
        )
        let strippedNoiseTitle = strippedBracketedTitle
            .replacingOccurrences(of: #"(?:^|\s)(feat\.?|ft\.?|featuring|prod\.?|produced by)\s+.+$"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)(official audio|official video|lyrics video|lyric video|visualizer|nightcore|sped up(?:\s*\+\s*reverb)?|slowed(?:\s*\+\s*reverb)?|remix|mix|edit|live|version|remaster(?:ed)?)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var variants: [String] = [
            trimmedTitle,
            strippedBracketedTitle,
            strippedNoiseTitle
        ]

        let titleSeparators = [" - ", " – ", " — ", " | ", ":"]
        for separator in titleSeparators {
            guard let range = trimmedTitle.range(of: separator) else { continue }
            let prefix = String(trimmedTitle[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = String(trimmedTitle[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

            if containsLyricsNoise(in: suffix) {
                variants.append(prefix)
            }
        }

        return deduplicatedNonEmptyValues(variants)
    }

    private func artistSearchVariants(for artist: String) -> [String] {
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedArtist.isEmpty, trimmedArtist != "Unknown Artist" else { return [] }

        let strippedArtist = trimmedArtist
            .replacingOccurrences(of: #"\[[^\]]*\]|\([^)]*\)|\{[^}]*\}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(feat\.?|ft\.?|featuring|prod\.?|produced by)\s+.+$"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var variants: [String] = [trimmedArtist, strippedArtist]
        let lowercasedArtist = strippedArtist.lowercased()
        let separators = [" feat", " ft", ",", "&", " x ", " and ", " with "]
        let separatorIndex = separators.compactMap { lowercasedArtist.range(of: $0)?.lowerBound }.min()
        if let separatorIndex {
            variants.append(String(strippedArtist[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return deduplicatedNonEmptyValues(variants)
    }

    private func deduplicatedNonEmptyValues(_ values: [String]) -> [String] {
        var seenNormalizedValues: Set<String> = []
        var orderedValues: [String] = []

        for value in values {
            let cleanedValue = value
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedValue.isEmpty else { continue }

            let normalizedValue = cleanedValue.lowercased()
            guard seenNormalizedValues.insert(normalizedValue).inserted else { continue }
            orderedValues.append(cleanedValue)
        }

        return orderedValues
    }

    private func containsLyricsNoise(in value: String) -> Bool {
        let normalizedValue = value.lowercased()
        let markers = [
            "feat", "ft", "featuring", "prod", "produced by", "official audio", "official video",
            "lyrics video", "lyric video", "visualizer", "nightcore", "slowed", "sped up",
            "remix", "edit", "mix", "live", "version", "remaster"
        ]

        return markers.contains { normalizedValue.contains($0) }
    }

    private func strippedSyncedLyrics(from value: String) -> String? {
        let plainText = value
            .replacingOccurrences(of: #"(?m)^\[[^\]]+\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)

        return cleanedLyricsText(plainText)
    }
}

private struct GeniusSearchEnvelope: Decodable {
    let response: GeniusSearchPayload
}

private struct GeniusSearchPayload: Decodable {
    let sections: [GeniusSearchSection]
}

private struct GeniusSearchSection: Decodable {
    let hits: [GeniusSearchHit]?
}

private struct GeniusSearchHit: Decodable {
    let result: GeniusSongHitResult
}

private struct GeniusSongHitResult: Decodable {
    let id: Int
    let title: String?
    let fullTitle: String?
    let titleWithFeatured: String?
    let artistNames: String?
    let primaryArtist: GeniusPrimaryArtist?
    let path: String?
    let url: String?
    let lyricsState: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case fullTitle = "full_title"
        case titleWithFeatured = "title_with_featured"
        case artistNames = "artist_names"
        case primaryArtist = "primary_artist"
        case path
        case url
        case lyricsState = "lyrics_state"
    }
}

private struct GeniusPrimaryArtist: Decodable {
    let name: String?
}

private struct GeniusSongPageState: Decodable {
    let songPage: GeniusSongPageLyricsData?
}

private struct GeniusSongPageLyricsData: Decodable {
    let lyricsData: GeniusLyricsPayload?
}

private struct GeniusLyricsPayload: Decodable {
    let body: GeniusLyricsBody?
}

private struct GeniusLyricsBody: Decodable {
    let html: String?
}

private struct LyricsLookupMetadata {
    let titleVariants: [String]
    let artistVariants: [String]
    let normalizedTitleCandidates: Set<String>
    let normalizedArtistCandidates: Set<String>

    var geniusSearchQueries: [String] {
        var queries: [String] = []

        for artist in artistVariants.prefix(2) {
            for title in titleVariants.prefix(3) {
                queries.append("\(artist) \(title)")
            }
        }

        return deduplicatedQueries(queries)
    }

    var providerQueries: [(artist: String, title: String)] {
        var queries: [(artist: String, title: String)] = []

        for artist in artistVariants.prefix(2) {
            for title in titleVariants.prefix(4) {
                queries.append((artist: artist, title: title))
            }
        }

        var seenKeys: Set<String> = []
        var orderedQueries: [(artist: String, title: String)] = []

        for query in queries {
            let identity = "\(query.artist.lowercased())::\(query.title.lowercased())"
            guard seenKeys.insert(identity).inserted else { continue }
            orderedQueries.append(query)
        }

        return orderedQueries
    }

    private func deduplicatedQueries(_ queries: [String]) -> [String] {
        var seenValues: Set<String> = []
        var orderedValues: [String] = []

        for query in queries {
            let cleanedQuery = query
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedQuery.isEmpty else { continue }

            let normalizedQuery = cleanedQuery.lowercased()
            guard seenValues.insert(normalizedQuery).inserted else { continue }
            orderedValues.append(cleanedQuery)
        }

        return orderedValues
    }
}

private struct LRCLibLyricsResult: Decodable {
    let trackName: String?
    let artistName: String?
    let plainLyrics: String?
    let syncedLyrics: String?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case trackName
        case artistName
        case plainLyrics
        case syncedLyrics
        case url
    }
}

private struct LyricsOVHResponse: Decodable {
    let lyrics: String?
}

#Preview {
    PlayerView(isPresented: .constant(true))
        .environmentObject(AudioPlayer.shared)
        .environmentObject(AppRouter())
}
