//
//  MyWaveSettingsView.swift
//  FreeMusicPlayer
//
//  In-app My Wave tuning sheet.
//

import SwiftUI

struct MyWaveSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataManager: DataManager

    private let chipColumns = [GridItem(.adaptive(minimum: 118), spacing: 12)]
    private let moodColumns = [GridItem(.adaptive(minimum: 76), spacing: 18)]

    private var settings: MyWaveSettings {
        dataManager.myWaveSettings
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.03, blue: 0.05),
                    Color(red: 0.09, green: 0.05, blue: 0.09),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    header

                    MyWaveSettingsSection(title: "По занятию") {
                        LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 12) {
                            ForEach(MyWaveSettings.Activity.allCases) { activity in
                                chipButton(
                                    title: activity.title,
                                    isSelected: settings.activity == activity
                                ) {
                                    dataManager.setMyWaveActivity(activity)
                                }
                            }
                        }
                    }

                    MyWaveSettingsSection(title: "По характеру") {
                        LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 12) {
                            ForEach(MyWaveSettings.Vibe.allCases) { vibe in
                                vibeCard(vibe)
                            }
                        }
                    }

                    MyWaveSettingsSection(title: "Под настроение") {
                        LazyVGrid(columns: moodColumns, alignment: .leading, spacing: 18) {
                            ForEach(MyWaveSettings.Mood.allCases) { mood in
                                moodButton(mood)
                            }
                        }
                    }

                    MyWaveSettingsSection(title: "По языку") {
                        LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 12) {
                            ForEach(MyWaveSettings.Language.allCases) { language in
                                chipButton(
                                    title: language.title,
                                    isSelected: settings.language == language
                                ) {
                                    dataManager.setMyWaveLanguage(language)
                                }
                            }
                        }
                    }

                    Button {
                        dataManager.resetMyWaveSettings()
                    } label: {
                        Text("Сбросить")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(settings.isCustomized ? 0.94 : 0.48))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color.white.opacity(settings.isCustomized ? 0.08 : 0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(Color.white.opacity(settings.isCustomized ? 0.16 : 0.08), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!settings.isCustomized)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 36)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Настроить Мою волну")
                    .font(.system(size: 31, weight: .bold))
                    .foregroundColor(.white)

                Text("Параметры сохраняются и сразу влияют на подбор треков в My Wave.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white.opacity(0.86))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.08))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func chipButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(isSelected ? 0.98 : 0.82))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.white.opacity(0.16) : Color.white.opacity(0.05))
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.white.opacity(0.36) : Color.white.opacity(0.10), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func vibeCard(_ vibe: MyWaveSettings.Vibe) -> some View {
        let isSelected = settings.vibe == vibe

        return Button {
            dataManager.setMyWaveVibe(vibe)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: vibeIcon(for: vibe))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white.opacity(isSelected ? 0.98 : 0.75))

                Text(vibe.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)

                Text(vibeDescription(for: vibe))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? Color.white.opacity(0.34) : Color.white.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func moodButton(_ mood: MyWaveSettings.Mood) -> some View {
        let isSelected = settings.mood == mood
        let color = moodColor(for: mood)

        return Button {
            dataManager.setMyWaveMood(mood)
        } label: {
            VStack(spacing: 10) {
                Circle()
                    .fill(color.opacity(isSelected ? 0.95 : 0.45))
                    .frame(width: 62, height: 62)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(isSelected ? 0.42 : 0.10), lineWidth: 2)
                    )
                    .shadow(color: color.opacity(isSelected ? 0.35 : 0), radius: 12, y: 6)

                Text(mood.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(isSelected ? 0.96 : 0.72))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func vibeIcon(for vibe: MyWaveSettings.Vibe) -> String {
        switch vibe {
        case .favorite:
            return "heart.fill"
        case .unknown:
            return "sparkles"
        case .popular:
            return "chart.line.uptrend.xyaxis"
        }
    }

    private func vibeDescription(for vibe: MyWaveSettings.Vibe) -> String {
        switch vibe {
        case .favorite:
            return "Больше знакомых артистов и любимого звучания."
        case .unknown:
            return "Смелее в discovery и меньше опоры на библиотеку."
        case .popular:
            return "Выше приоритет у заметных и популярных треков."
        }
    }

    private func moodColor(for mood: MyWaveSettings.Mood) -> Color {
        switch mood {
        case .energetic:
            return Color(red: 1.0, green: 0.43, blue: 0.24)
        case .happy:
            return Color(red: 0.96, green: 0.72, blue: 0.24)
        case .calm:
            return Color(red: 0.24, green: 0.68, blue: 0.78)
        case .sad:
            return Color(red: 0.38, green: 0.46, blue: 0.86)
        }
    }
}

private struct MyWaveSettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white.opacity(0.92))

            content
        }
    }
}
