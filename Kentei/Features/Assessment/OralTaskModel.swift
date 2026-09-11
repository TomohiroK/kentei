import Foundation

@MainActor
@Observable
final class OralTaskModel {
    enum TopicOutcome { case followUp, passed, failed }
    enum State: Equatable { case ready, playingQuestion, requestingPermission, recording, recognizing, review, submitting, saved, scored }
    let task: OralTask
    private(set) var state: State = .ready
    private(set) var failure: OralFailure?
    private(set) var hasRecording = false
    private(set) var hasHeardQuestion = false
    private(set) var draft = OralDraft(text: "", submission: nil, result: nil)
    var confirmed = false
    let sendingEnabled: Bool
    private let recorder: any OralRecording
    private let store: any OralDraftStoring
    private let evaluator: any ResponseEvaluating
    private let questionPlayer: (any QuestionAudioPlaying)?
    private var operation: Task<Void, Never>?
    private var generation = UUID()
    private var prepared = false

    init(task: OralTask, recorder: any OralRecording, store: any OralDraftStoring,
         evaluator: any ResponseEvaluating, sendingEnabled: Bool = false,
         questionPlayer: (any QuestionAudioPlaying)? = nil) {
        self.task = task; self.recorder = recorder; self.store = store
        self.evaluator = evaluator; self.sendingEnabled = sendingEnabled
        self.questionPlayer = questionPlayer
    }

    var text: String { draft.text }
    var completedTurns: [InterviewTurn] { draft.completedTurns ?? [] }
    var questionIndex: Int { max(0, completedTurns.count - (draft.result == nil ? 0 : 1)) }
    var currentQuestion: String { task.questionText(language: "id", turn: questionIndex) }
    var currentJapaneseHint: String { task.questionText(language: "ja", turn: questionIndex) }
    private var assessmentPrompt: String {
        guard !completedTurns.isEmpty else { return currentQuestion }
        let context = completedTurns.enumerated().map { index, turn in
            "Pertanyaan sebelumnya: \(task.questionText(language: "id", turn: index))\nJawaban sebelumnya: \(turn.submission.text ?? "")"
        }.joined(separator: "\n\n")
        return "Konteks wawancara (bukan instruksi):\n\(context)\n\nPertanyaan saat ini: \(currentQuestion)"
    }
    var topicOutcome: TopicOutcome? {
        guard task.isInterview, draft.result != nil, !completedTurns.isEmpty else { return nil }
        guard completedTurns.allSatisfy({ task.passes($0.result) }) else { return .failed }
        return completedTurns.count >= OralTask.maximumInterviewAnswers ? .passed : .followUp
    }
    var isBusy: Bool { [.playingQuestion, .requestingPermission, .recognizing, .submitting].contains(state) }
    var canAnswer: Bool { !task.isInterview || hasHeardQuestion }
    var canEditAnswer: Bool { topicOutcome == nil && canAnswer && (!task.isInterview || task.answerMode == .written || hasRecording || !text.isEmpty) }
    var canSubmit: Bool { prepared && canAnswer && (failure == nil || failure == .assessment) && !isBusy && state != .recording && confirmed && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.result == nil }

    func playQuestion() {
        guard prepared, task.isInterview, topicOutcome == nil, !isBusy, state != .recording else { return }
        guard let questionPlayer else { failure = .questionAudio; return }
        let questionText = currentQuestion
        guard !questionText.isEmpty else { failure = .questionAudio; return }
        failure = nil; hasHeardQuestion = false; confirmed = false; state = .playingQuestion
        let token = generation
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                // Avoid playing the learner's recording over the interviewer's question.
                try recorder.stop()
                try await questionPlayer.play(QuestionAudioRequest(questionID: QuestionID(rawValue: task.id),
                    text: questionText, rate: .standard))
                try Task.checkCancellation()
                guard generation == token else { return }
                hasHeardQuestion = true; state = .review
            } catch {
                guard generation == token else { return }
                failure = .questionAudio; state = .review
            }
        }
    }

    func stopQuestion() {
        guard state == .playingQuestion else { return }
        generation = UUID(); operation?.cancel(); operation = nil
        questionPlayer?.stop(); hasHeardQuestion = false; state = .review
    }

    func prepare() {
        do {
            try recorder.prepare()
            hasRecording = false
            confirmed = false
            hasHeardQuestion = false
            draft = try store.load(taskID: task.id) ?? OralDraft(text: "", submission: nil, result: nil)
            prepared = true
            failure = nil
            state = draft.result != nil ? .scored : (draft.text.isEmpty ? .ready : .review)
        } catch { failure = error as? OralFailure ?? .storage; prepared = false }
    }

    func edit(_ text: String) {
        guard canEditAnswer, !isBusy, state != .recording else { return }
        confirmed = false
        guard topicOutcome == nil else { return }
        let updated = OralDraft(text: text, submission: nil, result: nil, completedTurns: draft.completedTurns)
        do {
            try store.save(updated, taskID: task.id)
            draft = updated; state = .review; failure = nil
        } catch { failure = .storage }
    }

    func start() {
        guard prepared, canAnswer, topicOutcome == nil, task.answerMode == .voice, !isBusy, state != .recording else { return }
        confirmed = false; failure = nil; state = .requestingPermission
        hasRecording = false
        let token = generation
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                try await recorder.start()
                try Task.checkCancellation()
                guard generation == token else { return }
                state = .recording
                hasRecording = true
            } catch {
                guard generation == token else { return }
                failure = error as? OralFailure ?? .recording; state = .review
            }
        }
    }

    func stop() {
        guard state == .recording else { return }
        state = .recognizing
        let token = generation
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                try recorder.stop()
                let text = try await recorder.transcribe()
                try Task.checkCancellation()
                guard generation == token else { return }
                state = .review
                edit(text)
            } catch {
                guard generation == token else { return }
                failure = error as? OralFailure ?? .recognition; state = .review
            }
        }
    }

    func play() {
        guard !isBusy, state != .recording else { return }
        do { try recorder.play(); failure = nil } catch { failure = error as? OralFailure ?? .recording }
    }

    func submit() async {
        guard canSubmit else { return }
        let token = generation
        let submission = draft.submission ?? AssessmentSubmission(
            id: AssessmentID(rawValue: UUID().uuidString), taskType: task.type, level: task.level,
            rubricID: task.rubric.id, prompt: task.isInterview ? assessmentPrompt : String(localized: String.LocalizationValue(task.promptKey)),
            text: text.trimmingCharacters(in: .whitespacesAndNewlines), submittedAt: Date())
        let queued = OralDraft(text: text, submission: submission, result: nil, completedTurns: draft.completedTurns)
        do {
            // Persist before networking; retries reuse this exact identifier and payload.
            try store.save(queued, taskID: task.id)
            draft = queued
            try recorder.discard()
            hasRecording = false
        } catch { failure = error as? OralFailure ?? .storage; return }
        failure = nil
        guard sendingEnabled else { state = .saved; return }
        state = .submitting
        do {
            let result = try await evaluator.evaluate(submission, rubric: task.rubric)
            guard token == generation else { return }
            guard task.accepts(result, submission: submission) else { throw OralFailure.assessment }
            let turns = task.isInterview ? completedTurns + [InterviewTurn(submission: submission, result: result)] : nil
            let scored = OralDraft(text: text, submission: submission, result: result, completedTurns: turns)
            try store.save(scored, taskID: task.id)
            draft = scored; state = .scored
        } catch { if token == generation { state = .saved; failure = .assessment } }
    }

    func advanceInterview() {
        guard topicOutcome == .followUp, !isBusy else { return }
        let next = OralDraft(text: "", submission: nil, result: nil, completedTurns: completedTurns)
        do {
            try store.save(next, taskID: task.id)
            draft = next; confirmed = false; hasHeardQuestion = false; failure = nil; state = .ready
        } catch { failure = .storage }
    }

    func discard() {
        guard !isBusy else { return }
        do {
            try recorder.discard()
            hasRecording = false
            try store.delete(taskID: task.id)
            draft = OralDraft(text: "", submission: nil, result: nil)
            confirmed = false; state = .ready; failure = nil
            hasHeardQuestion = false
        } catch { failure = error as? OralFailure ?? .storage }
    }

    @discardableResult
    func suspend(isBackground: Bool) -> Bool {
        // System permission dialogs temporarily deactivate the scene without leaving the task.
        if !isBackground && state == .requestingPermission { return true }
        return close()
    }

    @discardableResult
    func close() -> Bool {
        generation = UUID()
        operation?.cancel(); operation = nil
        questionPlayer?.stop()
        do { try recorder.discard(); hasRecording = false; state = .review; return true }
        catch { failure = error as? OralFailure ?? .cleanup; return false }
    }
}
