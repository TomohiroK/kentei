import Foundation
@testable import Kentei

/// 決定的な時刻。保存データの時刻検証をテストから固定する。
final class FixedClock: SessionClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        current = start
    }

    func now() -> Date {
        lock.withLock { current }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(interval) }
    }
}

struct FixedIdentifierGenerator: IdentifierGenerating {
    let identifier: UUID

    init(identifier: UUID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!) {
        self.identifier = identifier
    }

    func newIdentifier() -> UUID {
        identifier
    }
}

/// メモリ上のセッション保存。保存回数も数え、回答直後に保存されたことを検証できるようにする。
actor InMemoryLearningSessionStore: LearningSessionStoring {
    private(set) var snapshot: LearningSessionSnapshot?
    private(set) var saveCount = 0
    private(set) var clearCount = 0
    private var loadError: (any Error)?

    init(snapshot: LearningSessionSnapshot? = nil, loadError: (any Error)? = nil) {
        self.snapshot = snapshot
        self.loadError = loadError
    }

    func load() async throws -> LearningSessionSnapshot? {
        if let loadError {
            throw loadError
        }
        return snapshot
    }

    func save(_ snapshot: LearningSessionSnapshot) async throws {
        self.snapshot = snapshot
        saveCount += 1
    }

    func clear() async throws {
        snapshot = nil
        clearCount += 1
    }
}

/// 保存が必ず失敗するストア。失敗が握りつぶされていないことを検証する。
struct FailingLearningSessionStore: LearningSessionStoring {
    struct Failure: Error {}

    func load() async throws -> LearningSessionSnapshot? { nil }
    func save(_ snapshot: LearningSessionSnapshot) async throws { throw Failure() }
    func clear() async throws { throw Failure() }
}

/// 音声再生の代役。再生要求と停止回数を記録する。
@MainActor
final class FakeQuestionAudioPlayer: QuestionAudioPlaying {
    var onSpeechMark: (() -> Void)?
    private(set) var playedRequests: [QuestionAudioRequest] = []
    private(set) var preparedRequests: [QuestionAudioRequest] = []
    private(set) var stopCount = 0
    var playError: (any Error)?
    /// 再生完了を任意のタイミングにするための待ち合わせ。
    var completesImmediately = true

    private var pendingContinuations: [CheckedContinuation<Void, any Error>] = []

    func play(_ request: QuestionAudioRequest) async throws {
        playedRequests.append(request)
        if let playError {
            throw playError
        }
        guard !completesImmediately else { return }
        try await withCheckedThrowingContinuation { continuation in
            pendingContinuations.append(continuation)
        }
    }

    func prepare(_ request: QuestionAudioRequest) {
        preparedRequests.append(request)
    }

    /// 発話中の口の動きを再現するための拍を送る。
    func emitSpeechMarks(_ count: Int) {
        for _ in 0..<count {
            onSpeechMark?()
        }
    }

    func stop() {
        stopCount += 1
        let continuations = pendingContinuations
        pendingContinuations = []
        for continuation in continuations {
            continuation.resume()
        }
    }
}

/// 回答送信の代役。受理するキーと失敗を差し替えられる。
final class FakeAnswerSyncer: AnswerSyncing, @unchecked Sendable {
    private let lock = NSLock()
    private var batches: [[PendingAnswer]] = []
    private var failure: AnswerSyncError?
    private var acceptedKeyLimit: Int?

    init(failure: AnswerSyncError? = nil, acceptedKeyLimit: Int? = nil) {
        self.failure = failure
        self.acceptedKeyLimit = acceptedKeyLimit
    }

    var receivedBatches: [[PendingAnswer]] {
        lock.withLock { batches }
    }

    var receivedKeys: [SyncIdempotencyKey] {
        lock.withLock { batches.flatMap { $0.map(\.key) } }
    }

    func setFailure(_ failure: AnswerSyncError?) {
        lock.withLock { self.failure = failure }
    }

    func send(_ answers: [PendingAnswer]) async throws -> [SyncIdempotencyKey] {
        let (currentFailure, limit) = lock.withLock { () -> (AnswerSyncError?, Int?) in
            batches.append(answers)
            return (failure, acceptedKeyLimit)
        }

        if let currentFailure {
            throw currentFailure
        }
        guard let limit else {
            return answers.map(\.key)
        }
        return answers.prefix(limit).map(\.key)
    }
}

/// メモリ上の未同期キュー保存。
actor InMemoryPendingAnswerStore: PendingAnswerStoring {
    private var queue: PendingAnswerQueue?

    init(queue: PendingAnswerQueue? = nil) {
        self.queue = queue
    }

    func load() async throws -> PendingAnswerQueue? { queue }
    func save(_ queue: PendingAnswerQueue) async throws { self.queue = queue }
    func clear() async throws { queue = nil }
}

/// AI評価の代役。決められた点数を返し、失敗も差し替えられる。
struct FakeResponseEvaluator: ResponseEvaluating {
    let scores: [String: Int]
    let modelVersion: String
    let failure: AssessmentError?

    init(scores: [String: Int] = [:], modelVersion: String = "fake-model-v1", failure: AssessmentError? = nil) {
        self.scores = scores
        self.modelVersion = modelVersion
        self.failure = failure
    }

    func evaluate(_ submission: AssessmentSubmission, rubric: Rubric) async throws -> AssessmentResult {
        if let failure {
            throw failure
        }

        let normalized = rubric.normalizedScore(from: scores)
        return AssessmentResult(
            submissionID: submission.id,
            scores: rubric.criteria.map { criterion in
                CriterionScore(criterionID: criterion.id, score: scores[criterion.id] ?? 0, commentKey: nil)
            },
            overallComment: "テスト用の講評",
            normalizedScore: normalized,
            isPassed: rubric.isPassing(normalized),
            modelVersion: modelVersion,
            rubricVersion: rubric.version,
            evaluatedAt: submission.submittedAt,
            humanReview: .notRequested
        )
    }
}

/// 提出ごとに点数を変えられる評価器。基準回答の回帰試験で使う。
struct ScriptedResponseEvaluator: ResponseEvaluating {
    let scoresBySubmissionID: [String: [String: Int]]
    let modelVersion: String

    init(scoresBySubmissionID: [String: [String: Int]], modelVersion: String = "fake-model-v1") {
        self.scoresBySubmissionID = scoresBySubmissionID
        self.modelVersion = modelVersion
    }

    func evaluate(_ submission: AssessmentSubmission, rubric: Rubric) async throws -> AssessmentResult {
        let scores = scoresBySubmissionID[submission.id.rawValue] ?? [:]
        let normalized = rubric.normalizedScore(from: scores)

        return AssessmentResult(
            submissionID: submission.id,
            scores: rubric.criteria.map { criterion in
                CriterionScore(criterionID: criterion.id, score: scores[criterion.id] ?? 0, commentKey: nil)
            },
            overallComment: "テスト用の講評",
            normalizedScore: normalized,
            isPassed: rubric.isPassing(normalized),
            modelVersion: modelVersion,
            rubricVersion: rubric.version,
            evaluatedAt: submission.submittedAt,
            humanReview: .notRequested
        )
    }
}

/// メモリ上の採点キュー保存。
actor InMemoryAssessmentQueueStore: AssessmentQueueStoring {
    private var state: AssessmentQueueState?

    init(state: AssessmentQueueState? = nil) {
        self.state = state
    }

    func load() async throws -> AssessmentQueueState? { state }
    func save(_ state: AssessmentQueueState) async throws { self.state = state }
    func clear() async throws { state = nil }
}

// MARK: - セッション生成のヘルパー

enum TestSession {
    /// 種を固定した決定的なセッション。並びを検証したいテストから使う。
    static func makeState(
        seed: UInt64 = 1,
        pack: LearningContentPack = DemoLearningContent.pack
    ) throws -> LearningSessionState {
        var generator = SeededRandomNumberGenerator(seed: seed)
        let plan = LearningSessionPlanner.makePlan(from: pack, using: &generator)
        return try LearningSessionState(contentPack: pack, plan: plan)
    }

    static func makePlan(
        seed: UInt64 = 1,
        pack: LearningContentPack = DemoLearningContent.pack
    ) -> LearningSessionPlan {
        var generator = SeededRandomNumberGenerator(seed: seed)
        return LearningSessionPlanner.makePlan(from: pack, using: &generator)
    }

    /// 出題を指定して作る計画。特定の問題に依存するテストで使う。
    static func makePlan(questionNumbers: [Int], pack: LearningContentPack = DemoLearningContent.pack) -> LearningSessionPlan {
        LearningSessionPlan(
            entries: questionNumbers.compactMap { number in
                let questionID = QuestionID(rawValue: "demo-question-\(number)")
                guard let question = pack.question(with: questionID) else { return nil }
                return LearningSessionPlan.Entry(questionID: questionID, choiceIDs: question.choices.map(\.id))
            }
        )
    }
}

/// 端末の Keychain を使わない差し替え。テストが実機の保管領域を汚さないようにする。
final class InMemoryAssessmentCredentialStore: AssessmentCredentialStoring, @unchecked Sendable {
    private var token: String?

    init(token: String? = nil) {
        self.token = token
    }

    func loadToken() -> String? {
        token
    }

    func save(token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        // 本番の実装と同じく、空白だけの入力は未設定として扱う。
        self.token = trimmed.isEmpty ? nil : trimmed
    }

    func clear() {
        token = nil
    }
}
