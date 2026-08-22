import SwiftUI

/// 初回導入。目的の説明から音声の聞こえ確認まで行い、最初のセッションへ渡す。
///
/// 価値を説明する前に登録や許可だけを求めない。各手順は戻れるようにする。
struct OnboardingView: View {
    let audioPlayer: any QuestionAudioPlaying
    let onFinish: (LearnerProfile) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 画面確認用に途中の手順から開くための入口。既定は最初の手順。
    init(
        audioPlayer: any QuestionAudioPlaying,
        startingStepIndex: Int = 0,
        onFinish: @escaping (LearnerProfile) -> Void
    ) {
        self.audioPlayer = audioPlayer
        self.onFinish = onFinish
        _step = State(initialValue: Step(rawValue: startingStepIndex) ?? .purpose)
    }

    @State private var step: Step
    @State private var interfaceLanguage: InterfaceLanguage = .systemDefault
    @State private var purpose: LearnerProfile.Purpose?
    @State private var targetLevel: CertificationLevel = .e
    @State private var experience: LearnerProfile.Experience?
    @State private var audioCheck: AudioCheck = .notPlayed
    @State private var isPlayingSample = false
    @State private var speechPulse = 0

    private enum Step: Int, CaseIterable {
        case purpose
        case language
        case goal
        case level
        case audio

        var isFirst: Bool { self == .purpose }
    }

    private enum AudioCheck: Equatable {
        case notPlayed
        case heard
        case notHeard
    }

    /// 聞こえ確認で流す一文。教材と同じ話し方であることが分かる短い挨拶にする。
    private static let sampleText = "Selamat datang! Mari belajar bahasa Indonesia."

    var body: some View {
        VStack(spacing: 0) {
            progressBar

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    stepContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, KenteiTheme.horizontalPadding)
                .padding(.vertical, 24)
            }

            footer
        }
        .background(KenteiTheme.skyBackground.ignoresSafeArea())
        .environment(\.locale, Locale(identifier: interfaceLanguage.localeIdentifier))
        .onDisappear {
            audioPlayer.stop()
        }
    }

    // MARK: - 手順ごとの内容

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .purpose:
            introduction
        case .language:
            languageSelection
        case .goal:
            purposeSelection
        case .level:
            levelSelection
        case .audio:
            audioCheckStep
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 18) {
            LearningCompanionView(expression: .encourage, size: 132)
                .frame(maxWidth: .infinity)

            stepTitle("onboarding.intro.title")
            stepBody("onboarding.intro.body")

            VStack(alignment: .leading, spacing: 12) {
                bullet("onboarding.intro.point.audio", systemImage: "ear.fill")
                bullet("onboarding.intro.point.daily", systemImage: "figure.walk")
                bullet("onboarding.intro.point.short", systemImage: "clock.fill")
            }
        }
    }

    private var languageSelection: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("onboarding.language.title")
            stepBody("onboarding.language.body")

            ForEach(InterfaceLanguage.allCases, id: \.rawValue) { language in
                selectableRow(
                    title: language.localizedTitle,
                    isSelected: interfaceLanguage == language
                ) {
                    interfaceLanguage = language
                }
            }
        }
    }

    private var purposeSelection: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("onboarding.purpose.title")
            stepBody("onboarding.purpose.body")

            ForEach(LearnerProfile.Purpose.allCases, id: \.rawValue) { option in
                selectableRow(
                    title: option.localizedTitle,
                    isSelected: purpose == option
                ) {
                    purpose = option
                }
            }
        }
    }

    private var levelSelection: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("onboarding.level.title")
            stepBody("onboarding.level.body")

            Picker("onboarding.level.title", selection: $targetLevel) {
                // 未提供の級はUIへ露出しない。
                ForEach(CertificationLevel.availableLevels, id: \.rawValue) { level in
                    Text(level.displayText).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("onboarding.targetLevel")

            Text("onboarding.experience.title")
                .font(.headline)
                .foregroundStyle(KenteiTheme.textPrimary)
                .padding(.top, 4)

            ForEach(LearnerProfile.Experience.allCases, id: \.rawValue) { option in
                selectableRow(
                    title: option.localizedTitle,
                    isSelected: experience == option
                ) {
                    experience = option
                }
            }
        }
    }

    private var audioCheckStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("onboarding.audio.title")
            stepBody("onboarding.audio.body")

            VStack(spacing: 16) {
                LearningCompanionView(
                    expression: .normal,
                    size: 118,
                    isSpeaking: isPlayingSample,
                    speechPulse: speechPulse
                )

                Button {
                    playSample()
                } label: {
                    Label("onboarding.audio.play", systemImage: isPlayingSample ? "waveform" : "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("onboarding.playSample")
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                Button("onboarding.audio.heard") {
                    audioCheck = .heard
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("onboarding.audio.notHeard") {
                    audioCheck = .notHeard
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            if audioCheck == .notHeard {
                KenteiCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("onboarding.audio.help.title", systemImage: "questionmark.circle.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(KenteiTheme.brandPrimary)
                        Text("onboarding.audio.help.body")
                            .font(.footnote)
                            .foregroundStyle(KenteiTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - 共通部品

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.rawValue) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? KenteiTheme.brandPrimary : KenteiTheme.brandPrimarySoft)
                    .frame(height: 6)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: step)
        .padding(.horizontal, KenteiTheme.horizontalPadding)
        .padding(.top, 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("onboarding.progress"))
        .accessibilityValue(Text("\(step.rawValue + 1) / \(Step.allCases.count)"))
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button(action: advance) {
                Text(step == .audio ? "onboarding.start" : "onboarding.next")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canAdvance)
            .accessibilityIdentifier("onboarding.next")

            if !step.isFirst {
                Button("onboarding.back", action: goBack)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KenteiTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(.horizontal, KenteiTheme.horizontalPadding)
        .padding(.bottom, 12)
        .background(KenteiTheme.elevatedSurface)
    }

    private func stepTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.title.bold())
            .foregroundStyle(KenteiTheme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func stepBody(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.subheadline)
            .foregroundStyle(KenteiTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func bullet(_ key: LocalizedStringKey, systemImage: String) -> some View {
        Label {
            Text(key)
                .font(.subheadline)
                .foregroundStyle(KenteiTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(KenteiTheme.brandPrimary)
        }
    }

    private func selectableRow(
        title: LocalizedStringKey,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(KenteiTheme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                // 選択状態を色だけで伝えない。
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? KenteiTheme.brandPrimary : KenteiTheme.textSecondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(isSelected ? KenteiTheme.brandPrimarySoft : KenteiTheme.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: KenteiTheme.controlCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: KenteiTheme.controlCornerRadius, style: .continuous)
                    .stroke(isSelected ? KenteiTheme.brandPrimary : KenteiTheme.divider, lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("onboarding.option")
    }

    // MARK: - 進行

    private var canAdvance: Bool {
        switch step {
        case .purpose, .language:
            true
        case .goal:
            purpose != nil
        case .level:
            experience != nil
        case .audio:
            // 聞こえなかった場合も先へ進める。学習を止めず、設定で直せるようにする。
            audioCheck != .notPlayed
        }
    }

    private func advance() {
        guard canAdvance else { return }

        guard step == .audio else {
            if let next = Step(rawValue: step.rawValue + 1) {
                step = next
            }
            return
        }

        finish()
    }

    private func goBack() {
        audioPlayer.stop()
        isPlayingSample = false
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    private func finish() {
        guard let purpose, let experience else { return }

        audioPlayer.stop()
        onFinish(
            LearnerProfile(
                interfaceLanguage: interfaceLanguage,
                purpose: purpose,
                targetLevel: targetLevel,
                experience: experience,
                completedOnboardingAt: Date()
            )
        )
    }

    private func playSample() {
        audioPlayer.onSpeechMark = {
            speechPulse += 1
        }
        speechPulse = 0
        isPlayingSample = true

        Task {
            defer { isPlayingSample = false }
            do {
                try await audioPlayer.play(
                    QuestionAudioRequest(
                        questionID: QuestionID(rawValue: "onboarding-sample"),
                        text: Self.sampleText,
                        rate: .standard
                    )
                )
            } catch {
                // 再生できない場合も導入を止めない。聞こえなかった場合の案内へ誘導する。
                audioCheck = .notHeard
            }
        }
    }
}

// MARK: - 表示文言
//
// `LocalizedStringKey` を文字列補間で組み立てるとフォーマット文字列として扱われ、
// 文言カタログに一致しない。キーはリテラルで書く。

private extension InterfaceLanguage {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .japanese: "onboarding.language.ja"
        case .indonesian: "onboarding.language.id"
        }
    }
}

private extension LearnerProfile.Purpose {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .certification: "onboarding.purpose.certification"
        case .travel: "onboarding.purpose.travel"
        case .living: "onboarding.purpose.living"
        case .work: "onboarding.purpose.work"
        }
    }
}

private extension LearnerProfile.Experience {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .none: "onboarding.experience.none"
        case .beginner: "onboarding.experience.beginner"
        case .conversational: "onboarding.experience.conversational"
        }
    }
}
