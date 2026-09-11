import Foundation

struct OralTask: Identifiable, Equatable, Sendable {
    enum AnswerMode: String, Sendable { case voice, written }
    let id: String
    let level: CertificationLevel
    let type: AssessmentTaskType
    let promptKey: String
    var answerMode: AnswerMode = .voice
    var isInterview: Bool { type == .interview }
    var titleKey: String { type == .speaking ? "oral.speech" : "interview.title.\(answerMode.rawValue)" }
    static let maximumInterviewAnswers = 3
    static let minimumInterviewCriterionRatio = 0.3
    func questionText(language: String, turn: Int = 0) -> String {
        let questionKey = turn == 0 ? "interview.question.\(level.rawValue)" : "interview.followup.\(level.rawValue).\(turn)"
        // The spoken question stays Indonesian regardless of the interface language.
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return "" }
        let text = bundle.localizedString(forKey: questionKey, value: nil, table: nil)
        return text == questionKey ? "" : text
    }
    var rubric: Rubric {
        Rubric(
            id: RubricID(rawValue: "rubric-\(type.rawValue)-\(level.rawValue)"),
            version: isInterview ? "interview-2026-09-v2" : "oral-2026-09-v1", level: level, taskType: type,
            criteria: [
                RubricCriterion(id: "task", titleKey: "rubric.criterion.task", weight: 0.35, maxScore: 4),
                RubricCriterion(id: "coherence", titleKey: "rubric.criterion.coherence", weight: 0.25, maxScore: 4),
                RubricCriterion(id: "grammar", titleKey: "rubric.criterion.grammar", weight: 0.2, maxScore: 4),
                RubricCriterion(id: "vocabulary", titleKey: "rubric.criterion.vocabulary", weight: 0.2, maxScore: 4)
            ], passingScore: isInterview ? 0.75 : (level == .a ? 0.7 : 0.6)
        )
    }

    func accepts(_ result: AssessmentResult, submission: AssessmentSubmission) -> Bool {
        guard result.submissionID == submission.id, result.rubricVersion == rubric.version,
              !result.modelVersion.isEmpty, result.scores.count == rubric.criteria.count,
              Set(result.scores.map(\.criterionID)).count == rubric.criteria.count else { return false }
        guard rubric.criteria.allSatisfy({ criterion in
            result.scores.contains { $0.criterionID == criterion.id && (0...criterion.maxScore).contains($0.score) }
        }) else { return false }
        let scores = Dictionary(uniqueKeysWithValues: result.scores.map { ($0.criterionID, $0.score) })
        return abs(rubric.normalizedScore(from: scores) - result.normalizedScore) < 0.000001 && result.isPassed == passes(result)
    }

    func passes(_ result: AssessmentResult) -> Bool {
        let scores = Dictionary(result.scores.map { ($0.criterionID, $0.score) }, uniquingKeysWith: { first, _ in first })
        guard rubric.isPassing(rubric.normalizedScore(from: scores)) else { return false }
        return !isInterview || rubric.criteria.allSatisfy {
            Double(scores[$0.id] ?? 0) / Double($0.maxScore) >= Self.minimumInterviewCriterionRatio
        }
    }

    // Independent draft rubrics: spoken transcripts must not be judged as written prose.
    static let all: [OralTask] = [CertificationLevel.b, .a].flatMap { level in
        let voiceTasks = [AssessmentTaskType.speaking, .interview].map { type in
            OralTask(id: "\(type.rawValue)-\(level.rawValue)", level: level, type: type,
                     promptKey: "oral.prompt.\(type.rawValue).\(level.rawValue)")
        }
        // Existing interview IDs retain their voice drafts; written answers use independent storage.
        return voiceTasks + [OralTask(id: "interview-written-\(level.rawValue)", level: level,
            type: .interview, promptKey: "oral.prompt.interview.\(level.rawValue)", answerMode: .written)]
    }
}

enum OralFailure: Error, Equatable {
    case permission, restricted, unavailable, recording, recognition, storage, cleanup, questionAudio, assessment
    var key: String { "oral.error.\(self)" }
}

struct OralDraft: Codable, Equatable, Sendable {
    var text: String
    var submission: AssessmentSubmission?
    var result: AssessmentResult?
    var completedTurns: [InterviewTurn]?
}

struct InterviewTurn: Codable, Equatable, Sendable {
    let submission: AssessmentSubmission
    let result: AssessmentResult
}

@MainActor
protocol OralDraftStoring {
    func load(taskID: String) throws -> OralDraft?
    func save(_ draft: OralDraft, taskID: String) throws
    func delete(taskID: String) throws
}

@MainActor
protocol OralRecording {
    func prepare() throws
    func start() async throws
    func stop() throws
    func transcribe() async throws -> String
    func play() throws
    func discard() throws
}
