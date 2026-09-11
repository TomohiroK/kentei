import SwiftUI

struct LearnView: View {
    let reviewDueCount: Int
    let isAssessmentConfigured: Bool
    let onStartLearning: (LearningSessionOrigin) -> Void
    let onStartWriting: (WritingTask) -> Void
    var onStartOral: (OralTask) -> Void = { _ in }

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

                    advancedSection
                }
                .padding(.horizontal, KenteiTheme.horizontalPadding)
                .padding(.bottom, 32)
            }
            .background(KenteiTheme.skyBackground.ignoresSafeArea())
            .navigationTitle("learn.title")
        }
    }

    /// B級・A級の入口。
    ///
    /// 始められない課題も含めて常に出す。導線ごと消すと、利用者からは
    /// 機能が存在しないように見え、いつ使えるようになるかも分からない。
    private var advancedSection: some View {
        VStack(spacing: 16) {
            SectionTitle(title: "learn.advanced")

            Text("learn.advanced.detail")
                .font(.footnote)
                .foregroundStyle(KenteiTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(AdvancedTaskCatalog.entriesByLevel(isAssessmentConfigured: isAssessmentConfigured), id: \.level.rawValue) { group in
                VStack(spacing: 12) {
                    Text(group.level.displayText)
                        .font(.subheadline.bold())
                        .foregroundStyle(KenteiTheme.brandAccent)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(group.entries) { entry in
                        advancedRow(entry)
                    }
                }
            }
        }
    }

    private func advancedRow(_ entry: AdvancedTaskEntry) -> some View {
        Button {
            if let task = entry.writingTask, entry.availability.canStart {
                onStartWriting(task)
            } else if let task = entry.oralTask, entry.availability.canStart {
                onStartOral(task)
            }
        } label: {
            KenteiCard {
                HStack(spacing: 14) {
                    Image(systemName: entry.taskType.requiresRecording ? "mic" : "square.and.pencil")
                        .font(.title2)
                        .foregroundStyle(entry.availability.canStart ? KenteiTheme.brandPrimary : KenteiTheme.textSecondary)
                        .frame(width: 52, height: 52)
                        .background(
                            (entry.availability.canStart ? KenteiTheme.brandPrimary : KenteiTheme.textSecondary)
                                .opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedStringKey(entry.titleKey))
                            .font(.headline)
                            .foregroundStyle(entry.availability.canStart ? KenteiTheme.textPrimary : KenteiTheme.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        // 始められない場合は理由を、開始できるが条件がある場合は
                        // 注意書きを出す。どちらもなければ課題の説明を出す。
                        if let noticeKey = entry.availability.reasonKey ?? entry.noticeKey {
                            Text(LocalizedStringKey(noticeKey))
                                .font(.footnote)
                                .foregroundStyle(KenteiTheme.textSecondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(LocalizedStringKey(entry.detailKey))
                                .font(.subheadline)
                                .foregroundStyle(KenteiTheme.textSecondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 4)

                    Image(systemName: entry.availability.canStart ? "chevron.right" : "lock.fill")
                        .font(.footnote.bold())
                        .foregroundStyle(KenteiTheme.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(entry.availability.canStart == false)
        .accessibilityIdentifier("learn.advanced.\(entry.id)")
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

    /// リング内の表示。全級合計の習得率なので、級名ではなく割合を出す。
    /// 級名を出すと、学習中の級と一致せず誤解を招く。
    private var masteryRatioText: String {
        "\(Int((masteryRatio * 100).rounded()))%"
    }

    private var levelCard: some View {
        KenteiCard {
            HStack(spacing: 18) {
                ProgressRing(progress: masteryRatio, label: masteryRatioText, size: 92)

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
    let isAssessmentConfigured: Bool
    let assessmentTokenSource: AssessmentTokenSource
    let contentIssueCount: Int
    let pendingSyncCount: Int
    let isOnline: Bool
    let onDeleteLearningData: () -> Void

    @State private var isShowingDeleteConfirmation = false

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

                Section("settings.sync") {
                    LabeledContent("settings.sync.connection") {
                        Label(
                            isOnline ? "settings.sync.online" : "settings.sync.offline",
                            systemImage: isOnline ? "wifi" : "wifi.slash"
                        )
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(isOnline ? KenteiTheme.success : KenteiTheme.textSecondary)
                    }
                    LabeledContent("settings.sync.pending") {
                        Text("\(pendingSyncCount)")
                            .monospacedDigit()
                    }
                    Text("settings.sync.detail")
                        .font(.footnote)
                        .foregroundStyle(KenteiTheme.textSecondary)
                }

                // 採点の状態。入力は求めない。トークンは開発中の都合であって、
                // 学習者が知る必要のあるものではない。値そのものは表示しない。
                Section("settings.assessment") {
                    LabeledContent("settings.assessment.state") {
                        Text(isAssessmentConfigured ? "settings.assessment.configured" : "settings.assessment.notConfigured")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(isAssessmentConfigured ? KenteiTheme.success : KenteiTheme.textSecondary)
                    }
                    LabeledContent("settings.assessment.source") {
                        Text(LocalizedStringKey(assessmentTokenSource.descriptionKey))
                            .font(.footnote)
                            .foregroundStyle(KenteiTheme.textSecondary)
                    }
                    .accessibilityIdentifier("settings.assessmentSource")

                    Text("settings.assessment.detail")
                        .font(.footnote)
                        .foregroundStyle(KenteiTheme.textSecondary)
                }

                Section("settings.privacy") {
                    Text("settings.privacy.detail")
                        .font(.footnote)
                        .foregroundStyle(KenteiTheme.textSecondary)

                    Button(role: .destructive) {
                        isShowingDeleteConfirmation = true
                    } label: {
                        Label("settings.deleteData", systemImage: "trash")
                    }
                    .accessibilityIdentifier("settings.deleteData")
                }
            }
            .scrollContentBackground(.hidden)
            .background(KenteiTheme.skyBackground)
            .navigationTitle("settings.title")
            .confirmationDialog(
                "settings.deleteData.title",
                isPresented: $isShowingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("settings.deleteData.confirm", role: .destructive, action: onDeleteLearningData)
                    .accessibilityIdentifier("settings.deleteData.confirm")
                Button("common.cancel", role: .cancel) {}
            } message: {
                Text("settings.deleteData.message")
            }
        }
    }
}
