import XCTest
@testable import Kentei

final class AnswerSyncTests: XCTestCase {
    private let sessionID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - 冪等キー

    func testIdempotencyKeyIdentifiesSessionQuestionAndAttempt() {
        let first = SyncIdempotencyKey(sessionID: sessionID, questionID: questionID(1), attempt: 1)
        let sameAnswer = SyncIdempotencyKey(sessionID: sessionID, questionID: questionID(1), attempt: 1)
        let retry = SyncIdempotencyKey(sessionID: sessionID, questionID: questionID(1), attempt: 2)

        XCTAssertEqual(first, sameAnswer)
        XCTAssertNotEqual(first, retry)
        XCTAssertTrue(first.rawValue.contains(sessionID.uuidString))
    }

    // MARK: - キュー

    func testQueueDoesNotStoreTheSameAnswerTwice() async {
        let queue = AnswerSyncQueue(store: InMemoryPendingAnswerStore())

        await queue.enqueue(pendingAnswer(1))
        await queue.enqueue(pendingAnswer(1))

        let count = await queue.pendingCount
        XCTAssertEqual(count, 1, "同じ冪等キーは二度積まない")
    }

    func testOfflineAnswersAreKeptUntilAccepted() async {
        let queue = AnswerSyncQueue(store: InMemoryPendingAnswerStore())
        await queue.enqueue(pendingAnswer(1))
        await queue.enqueue(pendingAnswer(2))

        let offlineSyncer = FakeAnswerSyncer(failure: .offline)
        let failed = await queue.flush(using: offlineSyncer)

        XCTAssertFalse(failed.didSyncAnything)
        XCTAssertEqual(failed.remainingCount, 2, "送れなかった回答は消さない")
        XCTAssertEqual(failed.failure, .offline)
    }

    func testReconnectingSendsEachAnswerExactlyOnce() async {
        let store = InMemoryPendingAnswerStore()
        let queue = AnswerSyncQueue(store: store)
        await queue.enqueue(pendingAnswer(1))
        await queue.enqueue(pendingAnswer(2))

        // オフライン中は送れない。
        let offlineSyncer = FakeAnswerSyncer(failure: .offline)
        await queue.flush(using: offlineSyncer)

        // 再接続後に送る。
        let onlineSyncer = FakeAnswerSyncer()
        let first = await queue.flush(using: onlineSyncer)
        let second = await queue.flush(using: onlineSyncer)

        XCTAssertEqual(first.syncedKeys.count, 2)
        XCTAssertEqual(first.remainingCount, 0)
        XCTAssertEqual(second.syncedKeys.count, 0, "同期済みを再送しない")
        XCTAssertEqual(
            onlineSyncer.receivedKeys.count,
            2,
            "再接続後に各回答が一度だけ送られる"
        )
    }

    func testOnlyAcceptedKeysLeaveTheQueue() async {
        let queue = AnswerSyncQueue(store: InMemoryPendingAnswerStore())
        await queue.enqueue(pendingAnswer(1))
        await queue.enqueue(pendingAnswer(2))
        await queue.enqueue(pendingAnswer(3))

        // サーバーが2件だけ受理した状況。
        let partialSyncer = FakeAnswerSyncer(acceptedKeyLimit: 2)
        let result = await queue.flush(using: partialSyncer)

        XCTAssertEqual(result.syncedKeys.count, 2)
        XCTAssertEqual(result.remainingCount, 1, "サーバー確認が取れたものだけ外す")
    }

    func testUnconfiguredBackendKeepsAnswersQueued() async {
        let queue = AnswerSyncQueue(store: InMemoryPendingAnswerStore())
        await queue.enqueue(pendingAnswer(1))

        let result = await queue.flush(using: UnconfiguredAnswerSyncer())

        XCTAssertEqual(result.failure, .backendNotConfigured)
        XCTAssertEqual(result.remainingCount, 1, "送信先が決まるまで端末に保持する")
    }

    func testQueueIsRestoredFromStorage() async {
        let store = InMemoryPendingAnswerStore(
            queue: PendingAnswerQueue(pending: [pendingAnswer(1), pendingAnswer(2)])
        )
        let queue = AnswerSyncQueue(store: store)

        await queue.load()
        let count = await queue.pendingCount

        XCTAssertEqual(count, 2, "アプリを閉じても未送信の回答は残る")
    }

    func testClearingRemovesEverything() async {
        let queue = AnswerSyncQueue(store: InMemoryPendingAnswerStore())
        await queue.enqueue(pendingAnswer(1))

        await queue.clear()

        let count = await queue.pendingCount
        XCTAssertEqual(count, 0)
    }

    // MARK: - オフライン学習

    func testASessionCanBeBuiltWithoutNetwork() throws {
        // 教材は同梱のため、通信なしで1セッション分を組める。
        var generator = SeededRandomNumberGenerator(seed: 31)
        let plan = LearningSessionPlanner.makePlan(from: DemoLearningContent.pack, using: &generator)

        XCTAssertGreaterThanOrEqual(
            plan.entries.count,
            LearningSessionState.checkpointQuestionCount,
            "オフラインでも最低10問を学習できる"
        )
        XCTAssertEqual(plan.entries.count, LearningSessionPlanner.defaultQuestionCount)
    }

    // MARK: - Helpers

    private func questionID(_ number: Int) -> QuestionID {
        QuestionID(rawValue: "demo-question-\(number)")
    }

    private func pendingAnswer(_ number: Int) -> PendingAnswer {
        PendingAnswer(
            key: SyncIdempotencyKey(sessionID: sessionID, questionID: questionID(number), attempt: 1),
            answer: AnsweredQuestion(
                questionID: questionID(number),
                choiceID: ChoiceID(rawValue: "demo-question-\(number)-choice-1"),
                isCorrect: true,
                answeredAt: date,
                audioPlayCount: 1
            ),
            contentVersion: DemoLearningContent.version,
            queuedAt: date
        )
    }
}

@MainActor
final class PerformanceBudgetTests: XCTestCase {
    func testWithinBudgetIsNotCountedAsExceeded() {
        let recorder = PerformanceRecorder()

        recorder.record(.audioStart, duration: 0.3)
        recorder.record(.questionDisplay, duration: 0.4)

        XCTAssertTrue(recorder.isWithinBudget(.audioStart))
        XCTAssertTrue(recorder.isWithinBudget(.questionDisplay))
        XCTAssertFalse(recorder.hasExceededAnyBudget)
    }

    func testExceedingTheBudgetIsRecorded() {
        let recorder = PerformanceRecorder()

        recorder.record(.audioStart, duration: 0.8)

        XCTAssertFalse(recorder.isWithinBudget(.audioStart), "音声開始の目標は500ms")
        XCTAssertEqual(recorder.exceededCount[.audioStart], 1)
        XCTAssertTrue(recorder.hasExceededAnyBudget)
    }

    func testBudgetMatchesTheDocumentedTargets() {
        let budget = PerformanceBudget.current

        XCTAssertEqual(budget.limit(for: .questionDisplay), 1.0, "問題画面表示1秒以内")
        XCTAssertEqual(budget.limit(for: .audioStart), 0.5, "音声開始500ms以内")
    }
}
