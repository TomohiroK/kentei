import SwiftUI

struct LearnView: View {
    let onStartLearning: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    recommendedCard

                    SectionTitle(title: "learn.modes")

                    learningMode(
                        title: "learn.recommended",
                        detail: "learn.recommended.detail",
                        icon: "sparkles",
                        tint: KenteiTheme.brandAccent,
                        action: onStartLearning
                    )
                    learningMode(
                        title: "learn.byLevel",
                        detail: "learn.byLevel.detail",
                        icon: "medal.fill",
                        tint: KenteiTheme.brandPrimary,
                        action: onStartLearning
                    )
                    learningMode(
                        title: "learn.review",
                        detail: "learn.review.detail",
                        icon: "arrow.clockwise",
                        tint: .orange,
                        action: onStartLearning
                    )
                }
                .padding(.horizontal, KenteiTheme.horizontalPadding)
                .padding(.bottom, 32)
            }
            .background(KenteiTheme.skyBackground.ignoresSafeArea())
            .navigationTitle("learn.title")
        }
    }

    private var recommendedCard: some View {
        KenteiCard {
            HStack(spacing: 14) {
                LearningCompanionView(expression: .happy, size: 104)

                VStack(alignment: .leading, spacing: 7) {
                    Text("learn.hero.eyebrow")
                        .font(.caption.bold())
                        .foregroundStyle(KenteiTheme.brandAccent)
                    Text("learn.hero.title")
                        .font(.title3.bold())
                        .foregroundStyle(KenteiTheme.textPrimary)
                    Text("learn.hero.detail")
                        .font(.caption)
                        .foregroundStyle(KenteiTheme.textSecondary)
                }
            }
        }
    }

    private func learningMode(
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            KenteiCard {
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(tint)
                        .frame(width: 52, height: 52)
                        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(KenteiTheme.textPrimary)
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(KenteiTheme.textSecondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(KenteiTheme.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct LearningProgressView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    levelCard

                    SectionTitle(title: "progress.skills")

                    skillRow(title: "progress.listening", icon: "ear.fill", value: 0.68, tint: KenteiTheme.brandPrimary)
                    skillRow(title: "progress.vocabulary", icon: "text.book.closed.fill", value: 0.54, tint: KenteiTheme.brandAccent)
                    skillRow(title: "progress.dailyLife", icon: "figure.walk", value: 0.41, tint: .orange)

                    SectionTitle(title: "progress.recent")

                    KenteiCard {
                        Label("progress.recent.airport", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(KenteiTheme.textPrimary)
                        Text("progress.recent.airport.detail")
                            .font(.subheadline)
                            .foregroundStyle(KenteiTheme.textSecondary)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, KenteiTheme.horizontalPadding)
                .padding(.bottom, 32)
            }
            .background(KenteiTheme.skyBackground.ignoresSafeArea())
            .navigationTitle("progress.title")
        }
    }

    private var levelCard: some View {
        KenteiCard {
            HStack(spacing: 18) {
                ProgressRing(progress: 0.64, label: "E級", size: 92)

                VStack(alignment: .leading, spacing: 6) {
                    Text("progress.currentLevel")
                        .font(.caption.bold())
                        .foregroundStyle(KenteiTheme.brandAccent)
                    Text("progress.level.title")
                        .font(.title2.bold())
                        .foregroundStyle(KenteiTheme.textPrimary)
                    Text("progress.level.detail")
                        .font(.subheadline)
                        .foregroundStyle(KenteiTheme.textSecondary)
                }
            }
        }
    }

    private func skillRow(
        title: LocalizedStringKey,
        icon: String,
        value: Double,
        tint: Color
    ) -> some View {
        KenteiCard {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(KenteiTheme.textPrimary)
                        Spacer()
                        Text("\(Int((value * 100).rounded()))%")
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(tint)
                    }
                    ProgressView(value: value)
                        .tint(tint)
                }
            }
        }
    }
}

struct SettingsView: View {
    @State private var autoplay = true
    @State private var haptics = true
    @State private var reducedEffects = false

    var body: some View {
        NavigationStack {
            Form {
                Section("settings.learning") {
                    Picker("settings.speed", selection: .constant(1.0)) {
                        Text("0.8×").tag(0.8)
                        Text("1.0×").tag(1.0)
                    }
                    Toggle("settings.autoplay", isOn: $autoplay)
                    Toggle("settings.haptics", isOn: $haptics)
                    Toggle("settings.reducedEffects", isOn: $reducedEffects)
                }

                Section("settings.language") {
                    HStack {
                        Text("settings.interfaceLanguage")
                        Spacer()
                        Text("settings.language.japanese")
                            .foregroundStyle(KenteiTheme.textSecondary)
                    }
                }

                Section("settings.data") {
                    Label("settings.downloads", systemImage: "arrow.down.circle")
                    Label("settings.privacy", systemImage: "hand.raised")
                    Label("settings.help", systemImage: "questionmark.circle")
                }
            }
            .scrollContentBackground(.hidden)
            .background(KenteiTheme.skyBackground)
            .navigationTitle("settings.title")
        }
    }
}
