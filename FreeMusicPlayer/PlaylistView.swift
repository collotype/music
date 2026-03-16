//
//  PlaylistView.swift
//  FreeMusicPlayer
//
//  Basic playlist screen placeholder used by the project file.
//

import SwiftUI

struct PlaylistView: View {
    @EnvironmentObject var dataManager: DataManager

    var body: some View {
        List {
            ForEach(dataManager.playlists) { playlist in
                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.name)
                        .foregroundColor(.white)
                    Text("\(playlist.trackCount) tracks")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.black)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle("Playlists")
    }
}

#Preview {
    NavigationView {
        PlaylistView()
            .environmentObject(DataManager.shared)
    }
}
