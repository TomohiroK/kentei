import SwiftUI

/// 生活図鑑のカテゴリ詳細。
///
/// 解放済み・未解放の行動と、その解放条件・残り件数を示す。
/// ロック理由を利用者に推測させない。
struct ScenarioDetailView: View {
    let progress: ScenarioProgress
    let onStartLearning: (ScenarioID) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summary

                    SectionTitle(title: "atlas.actions")

                    ForEach(progress.actionStatuses) { status in
                        actionRow(status)
                    }

                    unlockPolicyNote
                }
                .padding(.horizontal, KenteiTheme.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(KenteiTheme.skyBackground.ignoresSafeArea())
            .navigationTitle(LocalizedStringKey(progress.scenario.titleKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    onStartLearning(progress.scenario.id)
                } label: {
                    Label("atlas.startScenario", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, KenteiTheme.horizontalPadding)
                .padding(.vertical, 10)
                .background(.bar)
                .accessibilityIdentifier("atlas.startScenario")
            }
        }
    }

    private var summary: some View {
        KenteiCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(LocalizedStringKey(progress.scenario.detailKey))
                    .font(.subheadline)
                    .foregroundStyle(KenteiTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    MetricChip(
                        systemImage: "lock.open.fill",
                        value: "\(progress.unlockedActionCount) / \(progress.actionStatuses.count)",
                        label: "atlas.metric.actions",
                        tint: KenteiTheme.brandPrimary
                    )
                    MetricChip(
                        systemImage: "checkmark.seal.fill",
                        value: "\(progress.masteredQuestionCount) / \(progress.questionCount)",
                        label: "atlas.metric.mastered",
                        tint: KenteiTheme.success
                    )
                }
            }
        }
    }

    private func actionRow(_ status: ActionUnlockStatus) -> some View {
        KenteiCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    // 解放状態は記号と文言の両方で示し、色だけに頼らない。
                    Image(systemName: status.isUnlocked ? "checkmark.circle.fill" : "lock.fill")
                        .foregroundStyle(status.isUnlocked ? KenteiTheme.success : KenteiTheme.textSecondary)

                    Text(LocalizedStringKey(status.action.titleKey))
                        .font(.headline)
                        .foregroundStyle(KenteiTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 4)
                }

                ProgressView(value: status.progress)
                    .tint(status.isUnlocked ? KenteiTheme.success : KenteiTheme.brandPrimary)

                HStack(spacing: 6) {
                    Text(status.isUnlocked ? "atlas.action.unlocked" : "atlas.action.locked")
                    Text("\(status.masteredCount) / \(status.requiredCount)")
                        .monospacedDigit()
                    if status.isUnlocked == false {
                        Text("atlas.action.remaining")
                        Text("\(status.remainingCount)")
                            .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundStyle(KenteiTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// 判定に使った設定の版を示し、解放根拠を後から再現できるようにする。
    private var unlockPolicyNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("atlas.unlockCondition")
                .font(.caption.weight(.semibold))
                .foregroundStyle(KenteiTheme.textSecondary)

            Text("atlas.unlockConditionDetail")
                .font(.caption)
                .foregroundStyle(KenteiTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let status = progress.actionStatuses.first {
                // 設定版は識別子なので翻訳しない。
                Text(verbatim: "\(status.policyVersion) / \(status.atlasVersion)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(KenteiTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }
}
