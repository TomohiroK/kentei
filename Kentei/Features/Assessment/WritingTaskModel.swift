import Foundation

/// 記述課題の提出と採点の進行。
@MainActor
@Observable
final class WritingTaskModel {
    enum State: Equatable {
        case editing
        case submitting
        case scored(AssessmentResult)
        case failed(AssessmentError)
    }

    let task: WritingTask
    let rubric: Rubric

    private(set) var state: State = .editing
    var text: String = ""

    private let evaluator: any ResponseEvaluating
    private let queue: AssessmentQueue?
    private let clock: any SessionClock
    private let identifierGenerator: any IdentifierGenerating

    init(
        task: WritingTask,
        rubric: Rubric,
        evaluator: any ResponseEvaluating,
        queue: AssessmentQueue? = nil,
        clock: any SessionClock = SystemSessionClock(),
        identifierGenerator: any IdentifierGenerating = SystemIdentifierGenerator(),
        /// 採点済みの画面を直接開くための初期状態。画面確認と試験でのみ渡す。
        initialState: State = .editing
    ) {
        state = initialState
        self.task = task
        self.rubric = rubric
        self.evaluator = evaluator
        self.queue = queue
        self.clock = clock
        self.identifierGenerator = identifierGenerator
    }

    var characterCount: Int {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    var canSubmit: Bool {
        state != .submitting && characterCount >= task.minimumCharacters
    }

    /// 採点に出す。送れなかった提出は再評価キューへ積み、後で送り直せるようにする。
    func submit() async {
        guard canSubmit else { return }

        let submission = AssessmentSubmission(
            id: AssessmentID(rawValue: identifierGenerator.newIdentifier().uuidString),
            taskType: task.taskType,
            level: task.level,
            rubricID: task.rubricID,
            // 学習者が読んだ設問をそのまま送る。設問なしでは「課題への対応」を
            // 採点できず、資料を示す課題は成立しない。
            prompt: String(localized: String.LocalizationValue(task.promptKey)),
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            submittedAt: clock.now()
        )

        state = .submitting
        do {
            state = .scored(try await evaluator.evaluate(submission, rubric: rubric))
        } catch let error as AssessmentError {
            if error == .temporaryFailure || error == .providerNotConfigured {
                // 送れなかっただけの提出は捨てない。
                await queue?.enqueue(submission)
            }
            state = .failed(error)
        } catch {
            await queue?.enqueue(submission)
            state = .failed(.temporaryFailure)
        }
    }

    func backToEditing() {
        state = .editing
    }

    /// 観点の表示名。基準に無い観点は表示しない。
    func criterion(for id: String) -> RubricCriterion? {
        rubric.criteria.first { $0.id == id }
    }
}
