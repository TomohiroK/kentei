import SwiftUI

struct LearningSessionContainer: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session: LearningSessionState
    @State private var isShowingExitConfirmation = false

    init(initialState: LearningSessionState = .demo) {
        _session = State(initialValue: initialState)
    }

    var body: some View {
        Group {
            switch session.phase {
            case .answering:
                QuestionScreen(
                    session: $session,
                    onRequestExit: { isShowingExitConfirmation = true }
                )
            case .midpoint:
                MidpointResultView(
                    session: session,
                    onContinue: { session.continueAfterMidpoint() },
                    onExit: { dismiss() }
                )
            case .finalResult:
                FinalResultView(
                    session: session,
                    onRestart: { session.restart() },
                    onFinish: { dismiss() }
                )
            }
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
    @Binding var session: LearningSessionState
    let onRequestExit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            sessionHeader

            if let question = session.currentQuestion {
                ScrollView {
                    VStack(spacing: 22) {
                        scenarioBadge(question.scenarioName)

                        AudioPromptControl(
                            playCount: session.audioPlayCount,
                            onPlay: { session.registerAudioPlayback() }
                        )
                        .id(question.id)

                        choices(for: question)

                        if session.submittedChoiceID != nil {
                            feedback(for: question)
                        }
                    }
                    .padding(.horizontal, KenteiTheme.horizontalPadding)
                    .padding(.vertical, 20)
                }
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
    }

    private var sessionHeader: some View {
        VStack(spacing: 12) {
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
                    Image(systemName: "flame.fill")
                        .foregroundStyle(KenteiTheme.brandAccent)
                    Text("12")
                        .font(.subheadline.bold().monospacedDigit())
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("home.streak"))
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
            .frame(height: 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("session.progress.label"))
            .accessibilityValue(Text("\(session.currentIndex + 1) / \(session.questions.count)"))
        }
        .padding(.horizontal, KenteiTheme.horizontalPadding)
        .padding(.vertical, 10)
        .background(KenteiTheme.elevatedSurface)
    }

    private func scenarioBadge(_ scenario: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "location.fill")
            Text(scenario)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(KenteiTheme.brandPrimary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(KenteiTheme.brandPrimarySoft, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private func choices(for question: LearningQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("session.chooseAnswer")
                .font(.title3.bold())
                .foregroundStyle(KenteiTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(Array(question.choices.enumerated()), id: \.element.id) { index, choice in
                AnswerChoiceRow(
                    index: index,
                    choice: choice,
                    correctChoiceID: question.correctChoiceID,
                    selectedChoiceID: session.selectedChoiceID,
                    submittedChoiceID: session.submittedChoiceID,
                    onSelect: { session.select(choice.id) }
                )
            }
        }
    }

    private func feedback(for question: LearningQuestion) -> some View {
        KenteiCard {
            VStack(alignment: .leading, spacing: 14) {
                if session.isSubmittedAnswerCorrect {
                    Label("session.correct", systemImage: "checkmark.circle.fill")
                        .font(.title3.bold())
                        .foregroundStyle(KenteiTheme.success)
                } else {
                    Label("session.incorrect", systemImage: "arrow.counterclockwise.circle.fill")
                        .font(.title3.bold())
                        .foregroundStyle(KenteiTheme.error)
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("session.transcript")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(KenteiTheme.textSecondary)
                    Text(question.transcript)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(KenteiTheme.textPrimary)
                }

                Text(question.explanation)
                    .font(.body)
                    .foregroundStyle(KenteiTheme.textSecondary)
            }
        }
    }

    private var bottomAction: some View {
        VStack(spacing: 0) {
            Divider()

            if session.submittedChoiceID == nil {
                Button("session.submit") {
                    session.submit()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(session.selectedChoiceID == nil)
                .accessibilityIdentifier("session.submitAnswer")
            } else {
                Button(nextButtonTitle) {
                    session.advance()
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("session.nextQuestion")
            }
        }
        .padding(.horizontal, KenteiTheme.horizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.regularMaterial)
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

private struct AudioPromptControl: View {
    let playCount: Int
    let onPlay: () -> Void

    @State private var playbackRequest = 0
    @State private var isPlaying = false

    var body: some View {
        KenteiCard {
            VStack(spacing: 16) {
                LearningCompanionView(expression: isPlaying ? .thinking : .normal, size: 92)

                Button {
                    onPlay()
                    playbackRequest += 1
                } label: {
                    ZStack {
                        Circle()
                            .fill(KenteiTheme.brandPrimary)
                            .frame(width: 84, height: 84)
                            .shadow(color: KenteiTheme.brandPrimary.opacity(0.25), radius: 12, y: 7)
                        Image(systemName: isPlaying ? "waveform" : "play.fill")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .accessibilityLabel(Text(isPlaying ? "session.audio.playing" : "session.audio.play"))
                .accessibilityValue(Text("\(playCount)"))
                .accessibilityIdentifier("session.playAudio")

                VStack(spacing: 4) {
                    Text(isPlaying ? "session.audio.listening" : "session.audio.instruction")
                        .font(.headline)
                        .foregroundStyle(KenteiTheme.textPrimary)
                    Text("session.audio.noTextHint")
                        .font(.caption)
                        .foregroundStyle(KenteiTheme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .task(id: playbackRequest) {
            guard playbackRequest > 0 else { return }
            isPlaying = true

            do {
                try await Task.sleep(for: .seconds(1.25))
                if !Task.isCancelled {
                    isPlaying = false
                }
            } catch {
                isPlaying = false
            }
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
            HStack(spacing: 14) {
                Text(choiceLetter)
                    .font(.subheadline.bold())
                    .foregroundStyle(isSelected ? .white : KenteiTheme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(isSelected ? KenteiTheme.brandPrimary : KenteiTheme.brandPrimarySoft, in: Circle())

                Text(choice.text)
                    .font(.body.weight(.medium))
                    .foregroundStyle(KenteiTheme.textPrimary)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 8)

                if isSubmitted && isCorrect {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(KenteiTheme.success)
                } else if isSubmittedWrongChoice {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(KenteiTheme.error)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
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
    let session: LearningSessionState
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
                        value: "\(session.correctCount) / 10",
                        label: "midpoint.correct",
                        tint: KenteiTheme.success
                    )
                    MetricChip(
                        systemImage: "headphones",
                        value: "\(Int((session.accuracy * 100).rounded()))%",
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
    let session: LearningSessionState
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
                        progress: session.accuracy,
                        label: "\(Int((session.accuracy * 100).rounded()))%",
                        size: 96
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Label("result.correct", systemImage: "checkmark.circle.fill")
                        Text("\(session.correctCount) / \(session.questions.count)")
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
