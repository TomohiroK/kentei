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
}
