//
//  AppFileManager.swift
//  FreeMusicPlayer
//
//  File system layout for library, temp downloads, and persistent data.
//

import Foundation

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

    func prepareDirectories() {
        createDirectoryIfNeeded(appDataDirectory)
        createDirectoryIfNeeded(tempMusicDirectory)
        createDirectoryIfNeeded(musicDirectory)
        createDirectoryIfNeeded(dataDirectory)
        clearDirectoryContents(tempMusicDirectory)
        debugLog("Prepared app storage. Temp music cleared at \(tempMusicDirectory.path)")
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
            .appendingPathComponent("youtube_\(sanitizedID)")
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

    func fileExists(at storedPath: String?) -> Bool {
        guard let storedPath else { return false }
        return fileManager.fileExists(atPath: resolveStoredFileURL(for: storedPath).path)
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
}
