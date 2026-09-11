import Foundation

/// 採点待ち・採点結果・受け付けなかった提出をまとめた保存形式。
struct AssessmentQueueState: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    struct RejectedSubmission: Codable, Equatable, Sendable {
        let submissionID: AssessmentID
        /// 受け付けなかった理由。再試行しても通らないものだけを入れる。
        let reason: String
        let rejectedAt: Date
    }

    let schemaVersion: Int
    let pending: [AssessmentSubmission]
    let results: [AssessmentResult]
    let rejected: [RejectedSubmission]

    init(
        schemaVersion: Int = AssessmentQueueState.currentSchemaVersion,
        pending: [AssessmentSubmission] = [],
        results: [AssessmentResult] = [],
        rejected: [RejectedSubmission] = []
    ) {
        self.schemaVersion = schemaVersion
        self.pending = pending
        self.results = results
        self.rejected = rejected
    }
}

protocol AssessmentQueueStoring: Sendable {
    func load() async throws -> AssessmentQueueState?
    func save(_ state: AssessmentQueueState) async throws
    func clear() async throws
}

/// JSONファイルによる採点キューの永続化。
actor FileAssessmentQueueStore: AssessmentQueueStoring {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    static func defaultFileURL(fileManager: FileManager = .default) throws -> URL {
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return baseURL
            .appending(path: "LearningSessions", directoryHint: .isDirectory)
            .appending(path: "assessments.json", directoryHint: .notDirectory)
    }

    func load() async throws -> AssessmentQueueState? {
        guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return nil }

        let data = try Data(contentsOf: fileURL)
        let state: AssessmentQueueState
        do {
            state = try decoder.decode(AssessmentQueueState.self, from: data)
        } catch {
            throw LearningSessionStoreError.corruptedData
        }

        guard state.schemaVersion == AssessmentQueueState.currentSchemaVersion else { return nil }
        return state
    }

    func save(_ state: AssessmentQueueState) async throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directoryURL.path(percentEncoded: false)) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        try encoder.encode(state).write(to: fileURL, options: [.atomic])
    }

    func clear() async throws {
        guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return }
        try fileManager.removeItem(at: fileURL)
    }
}

struct DisabledAssessmentQueueStore: AssessmentQueueStoring {
    func load() async throws -> AssessmentQueueState? { nil }
    func save(_ state: AssessmentQueueState) async throws {}
    func clear() async throws {}
}

/// AI採点の再評価キュー。
///
/// 一時的な失敗は提出を残して次の機会に再評価する。プロバイダーが未確定の間も
/// 提出は端末に積まれ、決まった時点でそのまま処理できる。
/// 再試行しても通らない提出（録音を含む、内容が空など）は理由を付けて外す。
actor AssessmentQueue {
    private let store: any AssessmentQueueStoring
    private let gate: SubmissionGate
    private var pending: [AssessmentSubmission] = []
    private var results: [AssessmentResult] = []
    private var rejected: [AssessmentQueueState.RejectedSubmission] = []
    private var isLoaded = false

    init(store: any AssessmentQueueStoring, gate: SubmissionGate = SubmissionGate()) {
        self.store = store
        self.gate = gate
    }

    var pendingCount: Int { pending.count }
    var resultCount: Int { results.count }
    var rejectedCount: Int { rejected.count }

    func load() async {
        guard isLoaded == false else { return }
        isLoaded = true
        // 壊れた保存で学習を止めない。読めない場合は空から始める。
        let state = (try? await store.load()) ?? nil
        pending = state?.pending ?? []
        results = state?.results ?? []
        rejected = state?.rejected ?? []
    }

    /// 提出を積む。同じ提出IDは二度積まない。
    func enqueue(_ submission: AssessmentSubmission) async {
        await load()
        guard pending.contains(where: { $0.id == submission.id }) == false,
              results.contains(where: { $0.submissionID == submission.id }) == false else {
            return
        }
        pending.append(submission)
        await persist()
    }

    /// 採点を試みる。成功した提出は結果へ移し、一時失敗は残す。
    @discardableResult
    func process(using evaluator: any ResponseEvaluating, rubric: Rubric) async -> AssessmentProcessingResult {
        await load()

        var newResults: [AssessmentResult] = []
        var stillPending: [AssessmentSubmission] = []
        var newlyRejected: [AssessmentQueueState.RejectedSubmission] = []
        var lastFailure: AssessmentError?

        for submission in pending {
            if let gateFailure = gate.validate(submission, rubric: rubric) {
                newlyRejected.append(rejection(for: submission, reason: gateFailure))
                lastFailure = gateFailure
                continue
            }

            do {
                newResults.append(try await evaluator.evaluate(submission, rubric: rubric))
            } catch let error as AssessmentError {
                switch error {
                case .temporaryFailure, .providerNotConfigured:
                    // 再評価できる見込みがあるものは残す。
                    stillPending.append(submission)
                case .recordingNotAvailable, .invalidSubmission, .rubricMismatch:
                    newlyRejected.append(rejection(for: submission, reason: error))
                }
                lastFailure = error
            } catch {
                stillPending.append(submission)
                lastFailure = .temporaryFailure
            }
        }

        pending = stillPending
        results.append(contentsOf: newResults)
        rejected.append(contentsOf: newlyRejected)
        await persist()

        return AssessmentProcessingResult(
            evaluated: newResults,
            rejected: newlyRejected,
            remainingCount: pending.count,
            failure: newResults.isEmpty ? lastFailure : nil
        )
    }

    /// 人間レビューの状態を更新する。AIの採点をそのまま最終結果にしない経路。
    @discardableResult
    func applyHumanReview(_ state: HumanReviewState, to submissionID: AssessmentID) async -> AssessmentResult? {
        await load()
        guard let index = results.firstIndex(where: { $0.submissionID == submissionID }) else { return nil }

        results[index] = results[index].withHumanReview(state)
        await persist()
        return results[index]
    }

    func result(for submissionID: AssessmentID) async -> AssessmentResult? {
        await load()
        return results.first { $0.submissionID == submissionID }
    }

    func clear() async {
        pending = []
        results = []
        rejected = []
        isLoaded = true
        try? await store.clear()
    }

    private func rejection(
        for submission: AssessmentSubmission,
        reason: AssessmentError
    ) -> AssessmentQueueState.RejectedSubmission {
        AssessmentQueueState.RejectedSubmission(
            submissionID: submission.id,
            reason: String(describing: reason),
            rejectedAt: submission.submittedAt
        )
    }

    private func persist() async {
        try? await store.save(
            AssessmentQueueState(pending: pending, results: results, rejected: rejected)
        )
    }
}

struct AssessmentProcessingResult: Equatable, Sendable {
    let evaluated: [AssessmentResult]
    let rejected: [AssessmentQueueState.RejectedSubmission]
    let remainingCount: Int
    let failure: AssessmentError?

    var didEvaluateAnything: Bool {
        evaluated.isEmpty == false
    }
}
