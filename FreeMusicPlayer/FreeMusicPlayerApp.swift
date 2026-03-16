//
//  FreeMusicPlayerApp.swift
//  FreeMusicPlayer
//
//  Created on 2026-03-15.
//

import SwiftUI

@main
struct FreeMusicPlayerApp: App {
    @StateObject private var audioPlayer = AudioPlayer.shared
    @StateObject private var dataManager = DataManager.shared
    @StateObject private var router = AppRouter()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioPlayer)
                .environmentObject(dataManager)
                .environmentObject(router)
        }
    }
}
