import SwiftUI

struct LearningSessionContainer: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: LearningSessionModel
    @State private var isShowingExitConfirmation = false

    init(model: LearningSessionModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        Group {
            switch model.state.phase {
            case .answering:
                QuestionScreen(
                    model: model,
                    onRequestExit: { isShowingExitConfirmation = true }
                )
            case .midpoint:
                MidpointResultView(
                    state: model.state,
                    onContinue: { model.continueAfterMidpoint() },
                    onExit: { dismiss() }
                )
            case .finalResult:
                FinalResultView(
                    state: model.state,
                    onRestart: { model.restart() },
                    onFinish: {
                        model.finish()
                        dismiss()
                    }
                )
            }
        }
        .onChange(of: model.state.phase) { _, phase in
            // 区切り・結果へ移ったら、鳴っている音声も予約された再生も打ち切る。
            guard phase != .answering else { return }
            model.stopAudio()
        }
        .confirmationDialog(
            "session.exit.title",
            isPresented: $isShowingExitConfirmation,
            titleVisibility: .visible
        ) {
            Button("session.exit.confirm", role: .destructive) {
                dismiss()
            }
            Button("session.exit.cancel", role: .cancel) {}
        } message: {
            Text("session.exit.message")
        }
    }
}

private struct QuestionScreen: View {
    let model: LearningSessionModel
    let onRequestExit: () -> Void

    /// 回答直後に出す解説。下へスクロールしないと読めない位置には置かない。
    @State private var feedbackQuestion: LearningQuestion?

    private var session: LearningSessionState { model.state }

    var body: some View {
        VStack(spacing: 0) {
            sessionHeader

            if let question = session.currentQuestion {
                ScrollView {
                    VStack(spacing: 12) {
                        if model.hasPersistenceFailure {
                            persistenceWarning
                        }

                        AudioPlaybackBar(
                            model: model,
                            questionID: question.id,
                            scenarioTitleKey: question.scenarioTitleKey
                        )
                        .id(question.id)

                        choices(for: question)
                    }
                    .padding(.horizontal, KenteiTheme.horizontalPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                }
                .scrollBounceBehavior(.basedOnSize)
                .safeAreaInset(edge: .bottom) {
                    bottomAction
                }
            } else {
                ContentUnavailableView(
                    "session.empty.title",
                    systemImage: "exclamationmark.triangle",
                    description: Text("session.empty.message")
                )
            }
        }
        .background(KenteiTheme.skyBackground.ignoresSafeArea())
        .sheet(item: $feedbackQuestion) { question in
            AnswerFeedbackSheet(
                question: question,
                isCorrect: session.isSubmittedAnswerCorrect,
                nextTitle: nextButtonTitle
            ) {
                feedbackQuestion = nil
                model.advance()
            }
        }
        .onAppear {
            presentFeedbackIfAnswered()
        }
    }

    private func presentFeedbackIfAnswered() {
        guard session.submittedChoiceID != nil, feedbackQuestion == nil else { return }
        feedbackQuestion = session.currentQuestion
    }

    private var sessionHeader: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: onRequestExit) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundStyle(KenteiTheme.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(KenteiTheme.elevatedSurface, in: Circle())
                }
                .accessibilityLabel(Text("common.close"))

                Spacer()

                Text("\(session.currentIndex + 1) / \(session.questions.count)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(KenteiTheme.textPrimary)

                Spacer()

                HStack(spacing: 5) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(KenteiTheme.success)
                    Text("\(session.correctCount)")
                        .font(.subheadline.bold().monospacedDigit())
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("session.correctSoFar"))
                .accessibilityValue(Text("\(session.correctCount)"))
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(KenteiTheme.brandPrimarySoft)
                    Capsule()
                        .fill(KenteiTheme.brandPrimary)
                        .frame(
                            width: proxy.size.width * CGFloat(session.currentIndex + 1) / CGFloat(max(session.questions.count, 1))
                        )
                }
            }
            .frame(height: 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("session.progress.label"))
            .accessibilityValue(Text("\(session.currentIndex + 1) / \(session.questions.count)"))
        }
        .padding(.horizontal, KenteiTheme.horizontalPadding)
        .padding(.bottom, 10)
        .background(KenteiTheme.elevatedSurface)
    }

    private var persistenceWarning: some View {
        Label("session.saveFailed", systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(KenteiTheme.error)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(KenteiTheme.error.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .combine)
    }

    private func choices(for question: LearningQuestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("session.chooseAnswer")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KenteiTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(Array(question.choices.enumerated()), id: \.element.id) { index, choice in
                AnswerChoiceRow(
                    index: index,
                    choice: choice,
                    correctChoiceID: question.correctChoiceID,
                    selectedChoiceID: session.selectedChoiceID,
                    submittedChoiceID: session.submittedChoiceID,
                    onSelect: { model.select(choice.id) }
                )
            }
        }
    }

    /// 会話の話者を短い記号で示す。誰の発話かを色だけに頼らず伝える。
    private func speakerLabel(for speakerIndex: Int) -> String {
        let symbols = ["A", "B", "C"]
        return symbols[speakerIndex % symbols.count]
    }

    private var bottomAction: some View {
        VStack(spacing: 10) {
            // 正誤は常に見える位置に置く。選択肢まで戻らせない。
            if session.submittedChoiceID != nil {
                HStack(spacing: 8) {
                    Image(systemName: session.isSubmittedAnswerCorrect
                          ? "checkmark.circle.fill"
                          : "arrow.counterclockwise.circle.fill")
                    Text(session.isSubmittedAnswerCorrect ? "session.correct" : "session.incorrect")
                }
                .font(.headline)
                .foregroundStyle(session.isSubmittedAnswerCorrect ? KenteiTheme.success : KenteiTheme.error)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .overlay(alignment: .trailing) {
                    Button("session.showExplanation") {
                        feedbackQuestion = session.currentQuestion
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KenteiTheme.brandPrimary)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("session.showExplanation")
                }
            }

            if session.submittedChoiceID == nil {
                Button("session.submit") {
                    model.submit()
                    presentFeedbackIfAnswered()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(session.selectedChoiceID == nil)
                .accessibilityIdentifier("session.submitAnswer")
            } else {
                Button(nextButtonTitle) {
                    model.advance()
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("session.nextQuestion")
            }
        }
        .padding(.horizontal, KenteiTheme.horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private var nextButtonTitle: LocalizedStringKey {
        if session.currentIndex == LearningSessionState.checkpointQuestionCount - 1 {
            return "session.toMidpoint"
        }
        if session.currentIndex == session.questions.count - 1 {
            return "session.toResult"
        }
        return "session.next"
    }
}

/// 音声再生の操作。問題画面では選択肢と同時に見える高さに収める。
private struct AudioPlaybackBar: View {
    let model: LearningSessionModel
    let questionID: QuestionID
    let scenarioTitleKey: LocalizedStringKey?

    @AppStorage(LearningPreferenceKey.playbackRate) private var storedRate = PlaybackRate.standard.rawValue
    @AppStorage(LearningPreferenceKey.autoplay) private var isAutoplayEnabled = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var rate: PlaybackRate {
        PlaybackRate(rawValue: storedRate) ?? .standard
    }

    private var isPlaying: Bool {
        model.audioState == .playing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                playButton

                VStack(alignment: .leading, spacing: 8) {
                    Text(isPlaying ? "session.audio.listening" : "session.audio.instruction")
                        .font(.headline)
                        .foregroundStyle(KenteiTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    ratePicker
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                if let scenarioTitleKey {
                    Label(scenarioTitleKey, systemImage: "location.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(KenteiTheme.brandPrimary)
                        .accessibilityElement(children: .combine)
                }

                Spacer(minLength: 8)

                // 大きい文字設定では補助文が選択肢を押し出すため、操作に必要な要素だけ残す。
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("session.audio.noTextHint")
                        .font(.caption)
                        .foregroundStyle(KenteiTheme.textSecondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            audioFailureMessage
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kenteiCard()
        .task(id: questionID) {
            model.recordQuestionDisplayed()
            guard isAutoplayEnabled, model.state.phase == .answering else { return }
            model.playCurrentQuestion(rate: rate)
        }
        .onDisappear {
            model.stopAudio()
        }
    }

    private var playButton: some View {
        Button {
            model.playCurrentQuestion(rate: rate)
        } label: {
            ZStack {
                Circle()
                    .fill(KenteiTheme.brandPrimary)
                    .frame(width: 68, height: 68)
                    .shadow(color: KenteiTheme.brandPrimary.opacity(0.22), radius: 10, y: 5)

                Image(systemName: isPlaying ? "waveform" : "play.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isPlaying)
            }
        }
        .accessibilityLabel(Text(isPlaying ? "session.audio.playing" : "session.audio.play"))
        .accessibilityValue(Text("\(model.state.audioPlayCount)"))
        .accessibilityIdentifier("session.playAudio")
    }

    /// E級教材のみ 0.8 倍を許容する。標準速度を既定にする。
    private var ratePicker: some View {
        Picker("session.audio.rate", selection: $storedRate) {
            ForEach(PlaybackRate.allCases, id: \.rawValue) { option in
                Text(option.displayText).tag(option.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 168)
        .accessibilityIdentifier("session.audioRate")
    }

    @ViewBuilder
    private var audioFailureMessage: some View {
        if case let .failed(error) = model.audioState {
            Label(
                error == .voiceUnavailable ? "session.audio.voiceMissing" : "session.audio.failed",
                systemImage: "speaker.slash.fill"
            )
            .font(.footnote.weight(.semibold))
            .foregroundStyle(KenteiTheme.error)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct AnswerChoiceRow: View {
    let index: Int
    let choice: LearningChoice
    let correctChoiceID: ChoiceID
    let selectedChoiceID: ChoiceID?
    let submittedChoiceID: ChoiceID?
    let onSelect: () -> Void

    private var isSelected: Bool { selectedChoiceID == choice.id }
    private var isSubmitted: Bool { submittedChoiceID != nil }
    private var isCorrect: Bool { choice.id == correctChoiceID }
    private var isSubmittedWrongChoice: Bool { submittedChoiceID == choice.id && !isCorrect }

    private var strokeColor: Color {
        if isSubmitted && isCorrect { return KenteiTheme.success }
        if isSubmittedWrongChoice { return KenteiTheme.error }
        if isSelected { return KenteiTheme.brandPrimary }
        return KenteiTheme.divider
    }

    private var backgroundColor: Color {
        if isSubmitted && isCorrect { return KenteiTheme.success.opacity(0.11) }
        if isSubmittedWrongChoice { return KenteiTheme.error.opacity(0.09) }
        if isSelected { return KenteiTheme.brandPrimarySoft }
        return KenteiTheme.elevatedSurface
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Text(choiceLetter)
                    .font(.subheadline.bold())
                    .foregroundStyle(isSelected ? .white : KenteiTheme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(isSelected ? KenteiTheme.brandPrimary : KenteiTheme.brandPrimarySoft, in: Circle())

                Text(choice.text)
                    .font(.body.weight(.medium))
                    .foregroundStyle(KenteiTheme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                if isSubmitted && isCorrect {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(KenteiTheme.success)
                } else if isSubmittedWrongChoice {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(KenteiTheme.error)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(strokeColor, lineWidth: isSelected || isSubmitted ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isSubmitted)
        .accessibilityIdentifier("session.choice.\(index)")
    }

    private var choiceLetter: String {
        let letters = ["A", "B", "C", "D"]
        guard letters.indices.contains(index) else { return "•" }
        return letters[index]
    }
}

private struct MidpointResultView: View {
    let state: LearningSessionState
    let onContinue: () -> Void
    let onExit: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                LearningCompanionView(expression: .celebrate, size: 180)

                VStack(spacing: 8) {
                    Text("midpoint.eyebrow")
                        .font(.subheadline.bold())
                        .foregroundStyle(KenteiTheme.brandAccent)
                    Text("midpoint.title")
                        .font(.largeTitle.bold())
                        .foregroundStyle(KenteiTheme.textPrimary)
                    Text("midpoint.message")
                        .font(.body)
                        .foregroundStyle(KenteiTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 12) {
                    MetricChip(
                        systemImage: "checkmark.circle.fill",
                        value: "\(state.correctCountUpToCheckpoint) / \(LearningSessionState.checkpointQuestionCount)",
                        label: "midpoint.correct",
                        tint: KenteiTheme.success
                    )
                    MetricChip(
                        systemImage: "headphones",
                        value: "\(Int((state.accuracy * 100).rounded()))%",
                        label: "midpoint.accuracy",
                        tint: KenteiTheme.brandPrimary
                    )
                }

                KenteiCard {
                    Label("midpoint.achievement", systemImage: "suitcase.rolling.fill")
                        .font(.headline)
                        .foregroundStyle(KenteiTheme.textPrimary)
                    Text("midpoint.achievement.detail")
                        .font(.subheadline)
                        .foregroundStyle(KenteiTheme.textSecondary)
                        .padding(.top, 4)
                }

                Button("midpoint.continue", action: onContinue)
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("midpoint.continue")

                Button("midpoint.stop", action: onExit)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KenteiTheme.textSecondary)
            }
            .padding(.horizontal, KenteiTheme.horizontalPadding)
            .padding(.vertical, 30)
        }
        .background(KenteiTheme.skyBackground.ignoresSafeArea())
    }
}

private struct FinalResultView: View {
    let state: LearningSessionState
    let onRestart: () -> Void
    let onFinish: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                LearningCompanionView(expression: .celebrate, size: 190)

                VStack(spacing: 8) {
                    Text("result.eyebrow")
                        .font(.subheadline.bold())
                        .foregroundStyle(KenteiTheme.brandAccent)
                    Text("result.title")
                        .font(.largeTitle.bold())
                        .foregroundStyle(KenteiTheme.textPrimary)
                    Text("result.message")
                        .font(.body)
                        .foregroundStyle(KenteiTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 20) {
                    ProgressRing(
                        progress: state.accuracy,
                        label: "\(Int((state.accuracy * 100).rounded()))%",
                        size: 96
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Label("result.correct", systemImage: "checkmark.circle.fill")
                        Text("\(state.correctCount) / \(state.questions.count)")
                            .font(.title2.bold().monospacedDigit())
                    }
                    .foregroundStyle(KenteiTheme.textPrimary)
                }

                KenteiCard {
                    HStack(spacing: 14) {
                        Image(systemName: "lock.open.fill")
                            .font(.title2)
                            .foregroundStyle(KenteiTheme.brandAccent)
                            .frame(width: 52, height: 52)
                            .background(KenteiTheme.brandAccentSoft, in: Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text("result.unlocked")
                                .font(.caption.bold())
                                .foregroundStyle(KenteiTheme.brandAccent)
                            Text("result.unlocked.action")
                                .font(.headline)
                                .foregroundStyle(KenteiTheme.textPrimary)
                        }
                    }
                }

                Button("result.finish", action: onFinish)
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("result.finish")

                Button("result.retry", action: onRestart)
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, KenteiTheme.horizontalPadding)
            .padding(.vertical, 30)
        }
        .background(KenteiTheme.skyBackground.ignoresSafeArea())
    }
}

/// 回答直後の解説。正誤、聞こえた文、解説、次への導線をひとまとめにして前面に出す。
private struct AnswerFeedbackSheet: View {
    let question: LearningQuestion
    let isCorrect: Bool
    let nextTitle: LocalizedStringKey
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    verdict

                    VStack(alignment: .leading, spacing: 8) {
                        Text("session.transcript")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(KenteiTheme.textSecondary)

                        transcript
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("session.explanation")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(KenteiTheme.textSecondary)

                        Text(question.explanation)
                            .font(.body)
                            .foregroundStyle(KenteiTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, KenteiTheme.horizontalPadding)
                .padding(.top, 22)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)

            Button(nextTitle, action: onNext)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, KenteiTheme.horizontalPadding)
                .padding(.bottom, 12)
                .accessibilityIdentifier("session.feedbackNext")
        }
        .background(KenteiTheme.skyBackground.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// 正誤は記号と文言の両方で示し、色だけに頼らない。
    private var verdict: some View {
        HStack(spacing: 10) {
            Image(systemName: isCorrect ? "checkmark.circle.fill" : "arrow.counterclockwise.circle.fill")
                .font(.title)
            Text(isCorrect ? "session.correct" : "session.incorrect")
                .font(.title2.bold())
        }
        .foregroundStyle(isCorrect ? KenteiTheme.success : KenteiTheme.error)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var transcript: some View {
        transcriptContent
            .accessibilityIdentifier("session.transcriptValue")
    }

    @ViewBuilder
    private var transcriptContent: some View {
        if question.isConversation {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(question.utterances.enumerated()), id: \.offset) { _, utterance in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(speakerLabel(for: utterance.speakerIndex))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(KenteiTheme.brandPrimary)
                            .frame(minWidth: 22, alignment: .leading)
                        Text(utterance.text)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(KenteiTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } else {
            Text(question.transcript)
                .font(.title3.weight(.semibold))
                .foregroundStyle(KenteiTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func speakerLabel(for speakerIndex: Int) -> String {
        let symbols = ["A", "B", "C"]
        return symbols[speakerIndex % symbols.count]
    }
}
