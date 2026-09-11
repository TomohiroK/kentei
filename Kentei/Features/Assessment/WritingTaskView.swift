import SwiftUI

/// 記述課題の画面。設問を読み、書いて、採点結果を受け取る。
struct WritingTaskView: View {
    @State private var model: WritingTaskModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isEditorFocused: Bool

    init(model: WritingTaskModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    prompt

                    switch model.state {
                    case .editing, .submitting:
                        editor
                    case let .scored(result):
                        resultCard(result)
                    case let .failed(error):
                        failureCard(error)
                    }
                }
                .padding(.horizontal, KenteiTheme.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(KenteiTheme.skyBackground.ignoresSafeArea())
            .navigationTitle("writing.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.close") { dismiss() }
                }
                ToolbarItem(placement: .keyboard) {
                    Button("writing.doneEditing") { isEditorFocused = false }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .safeAreaInset(edge: .bottom) { bottomAction }
        }
    }

    private var prompt: some View {
        KenteiCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("writing.prompt", systemImage: "text.quote")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(KenteiTheme.brandAccent)

                Text(LocalizedStringKey(model.task.promptKey))
                    .font(.headline)
                    .foregroundStyle(KenteiTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(LocalizedStringKey(model.task.hintKey))
                    .font(.subheadline)
                    .foregroundStyle(KenteiTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 解答はインドネシア語で書く。設問と手引きは日本語なので、
            // 何語で答えるのかを明示しないと日本語で書けてしまう。
            Label("writing.answerLanguage", systemImage: "globe")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KenteiTheme.brandAccent)
                .accessibilityIdentifier("writing.answerLanguage")

            TextEditor(text: $model.text)
                .focused($isEditorFocused)
                .font(.body)
                .frame(minHeight: 220)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(KenteiTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: KenteiTheme.controlCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: KenteiTheme.controlCornerRadius, style: .continuous)
                        .stroke(KenteiTheme.divider, lineWidth: 1)
                }
                .accessibilityIdentifier("writing.editor")
                .accessibilityLabel(Text("writing.editor.label"))

            HStack {
                Text("writing.characterCount")
                    .font(.caption)
                    .foregroundStyle(KenteiTheme.textSecondary)
                Text("\(model.characterCount) / \(model.task.minimumCharacters)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(
                        model.characterCount >= model.task.minimumCharacters
                            ? KenteiTheme.success
                            : KenteiTheme.textSecondary
                    )
                Spacer()
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func resultCard(_ result: AssessmentResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            KenteiCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        // 合否は記号と文言の両方で示す。
                        Image(systemName: result.isPassed ? "checkmark.seal.fill" : "arrow.counterclockwise.circle.fill")
                            .font(.title2)
                        Text(result.isPassed ? "writing.passed" : "writing.notPassed")
                            .font(.title3.bold())
                        Spacer()
                        Text("\(Int((result.normalizedScore * 100).rounded()))%")
                            .font(.title3.bold().monospacedDigit())
                    }
                    .foregroundStyle(result.isPassed ? KenteiTheme.success : KenteiTheme.error)
                    .accessibilityElement(children: .combine)

                    ProgressView(value: result.normalizedScore)
                        .tint(result.isPassed ? KenteiTheme.success : KenteiTheme.error)
                }
            }

            SectionTitle(title: "writing.byCriterion")

            ForEach(result.scores, id: \.criterionID) { score in
                criterionRow(score)
            }

            if let overall = result.overallComment, overall.isEmpty == false {
                KenteiCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("writing.overall")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(KenteiTheme.textSecondary)
                        Text(overall)
                            .font(.subheadline)
                            .foregroundStyle(KenteiTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            modelAnswer

            // 採点の根拠として、使ったモデルと基準の版を示す。
            Text(verbatim: "\(result.modelVersion) / \(result.rubricVersion)")
                .font(.caption2.monospaced())
                .foregroundStyle(KenteiTheme.textSecondary)
        }
    }

    /// 模範回答。採点が返ってから出す。
    ///
    /// 書く前に見せると写して終わりになり、自分の答案との違いを考える機会が消える。
    /// 点数と講評だけでは「ではどう書けばよかったのか」が残らないため、
    /// 観点ごとの説明を添える。
    private var modelAnswer: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "writing.model")

            Text("writing.model.caption")
                .font(.footnote)
                .foregroundStyle(KenteiTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            KenteiCard {
                Text(LocalizedStringKey(model.task.modelAnswerKey))
                    .font(.body)
                    .foregroundStyle(KenteiTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("writing.modelAnswer")

            KenteiCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("writing.model.notes")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(KenteiTheme.textSecondary)
                    Text(LocalizedStringKey(model.task.modelAnswerNotesKey))
                        .font(.subheadline)
                        .foregroundStyle(KenteiTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("writing.modelAnswerNotes")
        }
    }

    private func criterionRow(_ score: CriterionScore) -> some View {
        KenteiCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(LocalizedStringKey(model.criterion(for: score.criterionID)?.titleKey ?? score.criterionID))
                        .font(.headline)
                        .foregroundStyle(KenteiTheme.textPrimary)
                    Spacer()
                    Text("\(score.score) / \(model.criterion(for: score.criterionID)?.maxScore ?? 0)")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(KenteiTheme.brandPrimary)
                }

                if let comment = score.commentKey, comment.isEmpty == false {
                    Text(comment)
                        .font(.subheadline)
                        .foregroundStyle(KenteiTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func failureCard(_ error: AssessmentError) -> some View {
        KenteiCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(Self.messageKey(for: error), systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(KenteiTheme.error)
                    .fixedSize(horizontal: false, vertical: true)

                Text(Self.detailKey(for: error))
                    .font(.subheadline)
                    .foregroundStyle(KenteiTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var bottomAction: some View {
        VStack(spacing: 8) {
            switch model.state {
            case .editing:
                Button("writing.submit") {
                    Task { await model.submit() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.canSubmit == false)
                .accessibilityIdentifier("writing.submit")

            case .submitting:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("writing.submitting")
                        .font(.headline)
                        .foregroundStyle(KenteiTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 54)

            case .scored:
                Button("writing.writeAgain") { model.backToEditing() }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("writing.writeAgain")

            case .failed:
                Button("writing.retry") {
                    Task { await model.submit() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("writing.retry")
            }
        }
        .padding(.horizontal, KenteiTheme.horizontalPadding)
        .padding(.vertical, 10)
        .background(.bar)
    }

    static func messageKey(for error: AssessmentError) -> LocalizedStringKey {
        switch error {
        case .providerNotConfigured: "writing.error.notConfigured"
        case .recordingNotAvailable: "writing.error.recording"
        case .temporaryFailure: "writing.error.temporary"
        case .invalidSubmission: "writing.error.invalid"
        case .rubricMismatch: "writing.error.rubric"
        }
    }

    static func detailKey(for error: AssessmentError) -> LocalizedStringKey {
        switch error {
        case .providerNotConfigured: "writing.error.notConfigured.detail"
        case .temporaryFailure: "writing.error.temporary.detail"
        default: "writing.error.generic.detail"
        }
    }
}
