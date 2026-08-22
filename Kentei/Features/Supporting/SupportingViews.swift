import SwiftUI

struct LearnView: View {
    let reviewDueCount: Int
    let onStartLearning: (LearningSessionOrigin) -> Void

    @State private var selectedLevel: CertificationLevel = .e

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
                        badge: nil,
                        identifier: "learn.recommended",
                        action: { onStartLearning(.recommended) }
                    )
                    levelPicker

                    learningMode(
                        title: "learn.byLevel",
                        detail: "learn.byLevel.detail",
                        icon: "medal.fill",
                        tint: KenteiTheme.brandPrimary,
                        badge: selectedLevel.displayText,
                        identifier: "learn.byLevel",
                        action: { onStartLearning(.level(selectedLevel)) }
                    )
                    learningMode(
                        title: "learn.review",
                        detail: "learn.review.detail",
                        icon: "arrow.clockwise",
                        tint: .orange,
                        badge: reviewDueCount > 0 ? "\(reviewDueCount)" : nil,
                        identifier: "learn.review",
                        action: { onStartLearning(.review) }
                    )
                }
                .padding(.horizontal, KenteiTheme.horizontalPadding)
                .padding(.bottom, 32)
            }
            .background(KenteiTheme.skyBackground.ignoresSafeArea())
            .navigationTitle("learn.title")
        }
    }

    /// 級別入口で出す級。提供している級だけを並べる。
    private var levelPicker: some View {
        Picker("learn.level", selection: $selectedLevel) {
            ForEach(CertificationLevel.availableLevels, id: \.rawValue) { level in
                Text(level.displayText).tag(level)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("learn.levelPicker")
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
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func learningMode(
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        icon: String,
        tint: Color,
        badge: String?,
        identifier: String,
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
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)

                    if let badge {
                        Text(badge)
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(tint, in: Capsule())
                    }

                    Image(systemName: "chevron.right")
                        .foregroundStyle(KenteiTheme.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

struct LearningProgressView: View {
    let masteredQuestionCount: Int
    let totalQuestionCount: Int
    let reviewDueCount: Int
    let scenarioProgressList: [ScenarioProgress]

    private var masteryRatio: Double {
        guard totalQuestionCount > 0 else { return 0 }
        return Double(masteredQuestionCount) / Double(totalQuestionCount)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    levelCard

                    SectionTitle(title: "progress.skills")

                    ForEach(scenarioProgressList) { progress in
                        scenarioRow(progress)
                    }

                    SectionTitle(title: "progress.recent")

                    KenteiCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("progress.reviewDue", systemImage: "arrow.clockwise")
                                .font(.headline)
                                .foregroundStyle(KenteiTheme.textPrimary)
                            Text("\(reviewDueCount)")
                                .font(.title2.bold().monospacedDigit())
                                .foregroundStyle(reviewDueCount > 0 ? .orange : KenteiTheme.textSecondary)
                            Text("progress.reviewDue.detail")
                                .font(.subheadline)
                                .foregroundStyle(KenteiTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
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
                ProgressRing(progress: masteryRatio, label: "E級", size: 92)

                VStack(alignment: .leading, spacing: 6) {
                    Text("progress.currentLevel")
                        .font(.caption.bold())
                        .foregroundStyle(KenteiTheme.brandAccent)
                    Text("progress.level.title")
                        .font(.title2.bold())
                        .foregroundStyle(KenteiTheme.textPrimary)
                    Text("progress.mastered")
                        .font(.caption)
                        .foregroundStyle(KenteiTheme.textSecondary)
                    Text("\(masteredQuestionCount) / \(totalQuestionCount)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(KenteiTheme.textPrimary)
                }
            }
        }
    }

    private func scenarioRow(_ progress: ScenarioProgress) -> some View {
        KenteiCard {
            HStack(spacing: 14) {
                Image(systemName: progress.scenario.systemImage)
                    .font(.headline)
                    .foregroundStyle(KenteiTheme.brandPrimary)
                    .frame(width: 42, height: 42)
                    .background(KenteiTheme.brandPrimarySoft, in: Circle())

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(LocalizedStringKey(progress.scenario.titleKey))
                            .font(.headline)
                            .foregroundStyle(KenteiTheme.textPrimary)
                        Spacer()
                        Text("\(Int((progress.achievement * 100).rounded()))%")
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(KenteiTheme.brandPrimary)
                    }
                    ProgressView(value: progress.achievement)
                        .tint(KenteiTheme.brandPrimary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

struct SettingsView: View {
    let contentPack: LearningContentPack
    let contentIssueCount: Int

    @AppStorage(LearningPreferenceKey.playbackRate) private var playbackRate = PlaybackRate.standard.rawValue
    @AppStorage(LearningPreferenceKey.autoplay) private var autoplay = true
    @AppStorage(LearningPreferenceKey.haptics) private var haptics = true
    @AppStorage(LearningPreferenceKey.reducedEffects) private var reducedEffects = false

    var body: some View {
        NavigationStack {
            Form {
                Section("settings.learning") {
                    Picker("settings.speed", selection: $playbackRate) {
                        ForEach(PlaybackRate.allCases, id: \.rawValue) { rate in
                            Text(rate.displayText).tag(rate.rawValue)
                        }
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

                Section("settings.content") {
                    LabeledContent("settings.content.version") {
                        Text(verbatim: contentPack.version)
                            .font(.footnote.monospaced())
                    }
                    LabeledContent("settings.content.checksum") {
                        // 全文は長いため先頭のみ出す。破損検知は自動検査で行う。
                        Text(verbatim: String(contentPack.checksum.prefix(12)))
                            .font(.footnote.monospaced())
                    }
                    LabeledContent("settings.content.questions") {
                        Text("\(contentPack.deliverableQuestions.count)")
                            .monospacedDigit()
                    }
                    ForEach(CertificationLevel.availableLevels, id: \.rawValue) { level in
                        LabeledContent(level.displayText) {
                            Text("\(contentPack.deliverableQuestions(at: level).count)")
                                .monospacedDigit()
                        }
                    }
                    LabeledContent("settings.content.validation") {
                        Label(
                            contentIssueCount == 0 ? "settings.content.valid" : "settings.content.invalid",
                            systemImage: contentIssueCount == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                        )
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(contentIssueCount == 0 ? KenteiTheme.success : KenteiTheme.error)
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
