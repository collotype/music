//
//  AppFileManager.swift
//  FreeMusicPlayer
//
//  File system layout for library, temp downloads, and persistent data.
//

import AVFoundation
import Foundation
import UniformTypeIdentifiers

final class AppFileManager {
    static let shared = AppFileManager()

    private let fileManager = FileManager.default

    private init() {}

    var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    var appDataDirectory: URL {
        documentsDirectory.appendingPathComponent("AppData", isDirectory: true)
    }

    var tempMusicDirectory: URL {
        appDataDirectory.appendingPathComponent("temp_music", isDirectory: true)
    }

    var musicDirectory: URL {
        appDataDirectory.appendingPathComponent("music", isDirectory: true)
    }

    var dataDirectory: URL {
        appDataDirectory.appendingPathComponent("data", isDirectory: true)
    }

    var artworkDirectory: URL {
        dataDirectory.appendingPathComponent("artwork", isDirectory: true)
    }

    private let supportedAudioExtensions: Set<String> = [
        "aac", "aif", "aiff", "alac", "caf", "flac", "m4a", "m4b",
        "mp3", "mp4", "ogg", "opus", "wav", "wma"
    ]

    func prepareDirectories(resetTemporaryStorage: Bool = false) {
        createDirectoryIfNeeded(appDataDirectory)
        createDirectoryIfNeeded(tempMusicDirectory)
        createDirectoryIfNeeded(musicDirectory)
        createDirectoryIfNeeded(dataDirectory)
        createDirectoryIfNeeded(artworkDirectory)

        if resetTemporaryStorage {
            clearDirectoryContents(tempMusicDirectory)
            debugLog("Prepared app storage. Temp music cleared at \(tempMusicDirectory.path)")
        } else {
            debugLog("Prepared app storage at \(appDataDirectory.path)")
        }
    }

    func clearAllAppData() {
        if fileManager.fileExists(atPath: appDataDirectory.path) {
            try? fileManager.removeItem(at: appDataDirectory)
        }
        prepareDirectories()
    }

    func dataFileURL(named fileName: String) -> URL {
        dataDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    func resolveStoredFileURL(for storedPath: String) -> URL {
        if storedPath.hasPrefix("/") {
            return URL(fileURLWithPath: storedPath)
        }

        let appDataURL = appDataDirectory.appendingPathComponent(storedPath)
        if fileManager.fileExists(atPath: appDataURL.path) {
            return appDataURL
        }

        return documentsDirectory.appendingPathComponent(storedPath)
    }

    func relativePath(for fileURL: URL) -> String? {
        let appDataPath = appDataDirectory.standardizedFileURL.path
        let targetPath = fileURL.standardizedFileURL.path

        guard targetPath.hasPrefix(appDataPath) else { return nil }

        let relative = String(targetPath.dropFirst(appDataPath.count))
        return relative.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    func temporaryAudioURL(for sourceID: String, fileExtension: String) -> URL {
        let sanitizedID = sanitizedFileName(sourceID)
        let finalExtension = fileExtension.isEmpty ? "m4a" : fileExtension
        return tempMusicDirectory
            .appendingPathComponent("online_\(sanitizedID)")
            .appendingPathExtension(finalExtension)
    }

    func uniqueLibraryURL(baseName: String, fileExtension: String) -> URL {
        let cleanBaseName = sanitizedFileName(baseName)
        let cleanExtension = fileExtension.isEmpty ? "m4a" : fileExtension
        let initialURL = musicDirectory
            .appendingPathComponent(cleanBaseName)
            .appendingPathExtension(cleanExtension)

        guard fileManager.fileExists(atPath: initialURL.path) else {
            return initialURL
        }

        for index in 1...999 {
            let candidateURL = musicDirectory
                .appendingPathComponent("\(cleanBaseName)-\(index)")
                .appendingPathExtension(cleanExtension)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return musicDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(cleanExtension)
    }

    func copyToLibrary(from sourceURL: URL, preferredName: String) throws -> URL {
        let fileExtension = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let destinationURL = uniqueLibraryURL(baseName: preferredName, fileExtension: fileExtension)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        debugLog("Copied track into library storage: \(destinationURL.path)")
        return destinationURL
    }

    func saveArtworkData(_ data: Data, preferredName: String) throws -> URL {
        let destinationURL = uniqueArtworkURL(baseName: preferredName, fileExtension: "jpg")
        try data.write(to: destinationURL, options: .atomic)
        debugLog("Stored artwork at \(destinationURL.lastPathComponent)")
        return destinationURL
    }

    func savePersistentImageData(_ data: Data, preferredName: String, fileExtension: String) throws -> URL {
        let cleanBaseName = sanitizedFileName(preferredName)
        let cleanExtension = sanitizedImageExtension(fileExtension)
        let destinationURL = artworkDirectory
            .appendingPathComponent(cleanBaseName)
            .appendingPathExtension(cleanExtension)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try? fileManager.removeItem(at: destinationURL)
        }

        try data.write(to: destinationURL, options: .atomic)
        debugLog("Stored persistent image at \(destinationURL.lastPathComponent)")
        return destinationURL
    }

    func fileExists(at storedPath: String?) -> Bool {
        guard let storedPath else { return false }
        return fileManager.fileExists(atPath: resolveStoredFileURL(for: storedPath).path)
    }

    func bookmarkData(for directoryURL: URL) throws -> Data {
        do {
            return try directoryURL.bookmarkData(
                options: [.minimalBookmark],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw AppFileManagerError.bookmarkCreationFailed(error.localizedDescription)
        }
    }

    func resolveBookmarkedURL(from bookmarkData: Data) throws -> URL {
        var isStale = false

        do {
            let resolvedURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                debugLog("Resolved bookmarked directory with stale bookmark: \(resolvedURL.path)")
            }

            return resolvedURL
        } catch {
            throw AppFileManagerError.bookmarkResolutionFailed(error.localizedDescription)
        }
    }

    func withSecurityScopedAccess<T>(to url: URL, perform: (URL) throws -> T) rethrows -> T {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try perform(url)
    }

    func withBookmarkedDirectoryAccess<T>(bookmarkData: Data, perform: (URL) throws -> T) throws -> T {
        let directoryURL = try resolveBookmarkedURL(from: bookmarkData)
        return try withSecurityScopedAccess(to: directoryURL, perform: perform)
    }

    func audioFiles(in directoryURL: URL) throws -> [URL] {
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .contentTypeKey]
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        ) else {
            throw AppFileManagerError.directoryEnumerationFailed(directoryURL.lastPathComponent)
        }

        var discoveredFiles: [URL] = []

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: Set(resourceKeys)),
                  resourceValues.isRegularFile == true else {
                continue
            }

            if isSupportedAudioFile(fileURL, resourceValues: resourceValues) {
                debugLog("Folder scan accepted file: \(fileURL.lastPathComponent)")
                discoveredFiles.append(fileURL)
            } else {
                debugLog("Folder scan skipped file: \(fileURL.lastPathComponent) because it is not recognized as playable audio")
            }
        }

        return discoveredFiles.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    private func createDirectoryIfNeeded(_ directoryURL: URL) {
        guard !fileManager.fileExists(atPath: directoryURL.path) else { return }
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func clearDirectoryContents(_ directoryURL: URL) {
        createDirectoryIfNeeded(directoryURL)
        let contents = (try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)) ?? []
        for fileURL in contents {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private func sanitizedFileName(_ rawValue: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let filtered = rawValue
            .components(separatedBy: allowedCharacters.inverted)
            .joined()
            .replacingOccurrences(of: " ", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return filtered.isEmpty ? UUID().uuidString : filtered
    }

    private func isSupportedAudioFile(_ url: URL, resourceValues: URLResourceValues) -> Bool {
        if let contentType = resourceValues.contentType,
           contentType.conforms(to: .audio) {
            debugLog("Audio detection accepted \(url.lastPathComponent) via UTType audio")
            return true
        }

        if supportedAudioExtensions.contains(url.pathExtension.lowercased()) {
            debugLog("Audio detection accepted \(url.lastPathComponent) via extension \(url.pathExtension.lowercased())")
            return true
        }

        if isPlayableAudioByProbe(url) {
            debugLog("Audio detection accepted \(url.lastPathComponent) via AVFoundation probe")
            return true
        }

        return false
    }

    private func uniqueArtworkURL(baseName: String, fileExtension: String) -> URL {
        let cleanBaseName = sanitizedFileName(baseName)
        let initialURL = artworkDirectory
            .appendingPathComponent(cleanBaseName)
            .appendingPathExtension(fileExtension)

        guard fileManager.fileExists(atPath: initialURL.path) else {
            return initialURL
        }

        for index in 1...999 {
            let candidateURL = artworkDirectory
                .appendingPathComponent("\(cleanBaseName)-\(index)")
                .appendingPathExtension(fileExtension)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return artworkDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
    }

    private func sanitizedImageExtension(_ rawValue: String) -> String {
        let trimmedValue = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "")
            .lowercased()

        return trimmedValue.isEmpty ? "jpg" : trimmedValue
    }

    private func isPlayableAudioByProbe(_ url: URL) -> Bool {
        let asset = AVURLAsset(url: url)
        let hasAudioTracks = !asset.tracks(withMediaType: .audio).isEmpty
        if hasAudioTracks || asset.isPlayable {
            return true
        }

        if let player = try? AVAudioPlayer(contentsOf: url) {
            return player.duration > 0 || player.prepareToPlay()
        }

        return false
    }
}

enum AppFileManagerError: LocalizedError {
    case bookmarkCreationFailed(String)
    case bookmarkResolutionFailed(String)
    case directoryEnumerationFailed(String)

    var errorDescription: String? {
        switch self {
        case .bookmarkCreationFailed(let details):
            return "Failed to save access to the selected folder. \(details)"
        case .bookmarkResolutionFailed(let details):
            return "Failed to reopen the selected music folder. \(details)"
        case .directoryEnumerationFailed(let folderName):
            return "Failed to scan the folder \"\(folderName)\" for audio files."
        }
    }
}
