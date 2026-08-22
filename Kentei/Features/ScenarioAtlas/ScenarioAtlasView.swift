import SwiftUI

struct ScenarioAtlasView: View {
    let progressList: [ScenarioProgress]
    let totalAchievement: Double
    let onSelectScenario: (ScenarioProgress) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero

                    SectionTitle(title: "atlas.scenes")

                    ForEach(progressList) { progress in
                        Button {
                            onSelectScenario(progress)
                        } label: {
                            scenarioCard(progress)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("atlas.scenario.\(progress.scenario.id.rawValue)")
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
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                ProgressRing(
                    progress: totalAchievement,
                    label: "\(Int((totalAchievement * 100).rounded()))%",
                    size: 82
                )
            }
        }
    }

    private func scenarioCard(_ progress: ScenarioProgress) -> some View {
        KenteiCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Image(systemName: progress.scenario.systemImage)
                        .font(.title2)
                        .foregroundStyle(KenteiTheme.brandPrimary)
                        .frame(width: 52, height: 52)
                        .background(
                            KenteiTheme.brandPrimarySoft,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedStringKey(progress.scenario.titleKey))
                            .font(.headline)
                            .foregroundStyle(KenteiTheme.textPrimary)
                        Text(LocalizedStringKey(progress.scenario.detailKey))
                            .font(.subheadline)
                            .foregroundStyle(KenteiTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .foregroundStyle(KenteiTheme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        // 達成率は解放済み行動の割合。数字の意味を必ず添える。
                        Text("atlas.unlockedActions")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(KenteiTheme.textSecondary)
                        Text("\(progress.unlockedActionCount) / \(progress.actionStatuses.count)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(KenteiTheme.textSecondary)
                        Spacer()
                        Text("\(Int((progress.achievement * 100).rounded()))%")
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(KenteiTheme.brandPrimary)
                    }

                    ProgressView(value: progress.achievement)
                        .tint(KenteiTheme.brandPrimary)

                    if progress.dueForReviewQuestionIDs.isEmpty == false {
                        Label {
                            HStack(spacing: 4) {
                                Text("atlas.dueForReview")
                                Text("\(progress.dueForReviewQuestionIDs.count)")
                                    .monospacedDigit()
                            }
                        } icon: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
