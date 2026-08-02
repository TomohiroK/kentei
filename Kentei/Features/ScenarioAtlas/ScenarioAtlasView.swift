import SwiftUI

private struct ScenarioCardData: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let icon: String
    let progress: Double
    let tint: Color
}

struct ScenarioAtlasView: View {
    private let scenarios = [
        ScenarioCardData(
            id: "airport",
            title: "atlas.airport",
            subtitle: "atlas.airport.detail",
            icon: "airplane.departure",
            progress: 0.72,
            tint: KenteiTheme.brandPrimary
        ),
        ScenarioCardData(
            id: "warung",
            title: "atlas.warung",
            subtitle: "atlas.warung.detail",
            icon: "fork.knife",
            progress: 0.45,
            tint: KenteiTheme.brandAccent
        ),
        ScenarioCardData(
            id: "convenience",
            title: "atlas.convenience",
            subtitle: "atlas.convenience.detail",
            icon: "basket.fill",
            progress: 0.28,
            tint: .orange
        ),
        ScenarioCardData(
            id: "grab",
            title: "atlas.grab",
            subtitle: "atlas.grab.detail",
            icon: "car.fill",
            progress: 0.18,
            tint: .green
        )
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero

                    SectionTitle(title: "atlas.scenes")

                    ForEach(scenarios) { scenario in
                        scenarioCard(scenario)
                    }
                }
                .padding(.horizontal, KenteiTheme.horizontalPadding)
                .padding(.bottom, 32)
            }
            .background(KenteiTheme.skyBackground.ignoresSafeArea())
            .navigationTitle("atlas.title")
        }
    }

    private var hero: some View {
        KenteiCard {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("atlas.hero.eyebrow")
                        .font(.caption.bold())
                        .foregroundStyle(KenteiTheme.brandAccent)
                    Text("atlas.hero.title")
                        .font(.title2.bold())
                        .foregroundStyle(KenteiTheme.textPrimary)
                    Text("atlas.hero.detail")
                        .font(.subheadline)
                        .foregroundStyle(KenteiTheme.textSecondary)
                }

                Spacer()

                ProgressRing(progress: 0.41, label: "41%", size: 82)
            }
        }
    }

    private func scenarioCard(_ scenario: ScenarioCardData) -> some View {
        Button(action: {}) {
            KenteiCard {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(scenario.tint.opacity(0.12))
                        Image(systemName: scenario.icon)
                            .font(.title2)
                            .foregroundStyle(scenario.tint)
                    }
                    .frame(width: 62, height: 62)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(scenario.title)
                            .font(.headline)
                            .foregroundStyle(KenteiTheme.textPrimary)
                        Text(scenario.subtitle)
                            .font(.caption)
                            .foregroundStyle(KenteiTheme.textSecondary)

                        ProgressView(value: scenario.progress)
                            .tint(scenario.tint)
                    }

                    Text("\(Int((scenario.progress * 100).rounded()))%")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(scenario.tint)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("atlas.scenario.\(scenario.id)")
    }
}

