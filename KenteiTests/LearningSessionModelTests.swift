import XCTest
@testable import Kentei

@MainActor
final class LearningSessionModelTests: XCTestCase {
    private var store: InMemoryLearningSessionStore!
    private var audioPlayer: FakeQuestionAudioPlayer!
    private var clock: FixedClock!

    override func setUp() async throws {
        try await super.setUp()
        store = InMemoryLearningSessionStore()
        audioPlayer = FakeQuestionAudioPlayer()
        clock = FixedClock()
    }

    // MARK: - 回答直後の保存

    func testAnswerIsPersistedImmediately() async throws {
        let model = makeModel()

        try answerCurrentQuestionCorrectly(in: model)
        await model.waitForPendingPersistence()

        let saved = await store.snapshot
        let saveCount = await store.saveCount
        let snapshot = try XCTUnwrap(saved)
        XCTAssertEqual(snapshot.answers.count, 1)
        XCTAssertEqual(snapshot.answers[0].isCorrect, true)
        XCTAssertEqual(snapshot.phase, .answering)
        XCTAssertEqual(saveCount, 1, "回答確定ごとに1回だけ保存する")
    }

    func testSelectingWithoutSubmittingIsNotPersisted() async throws {
        let model = makeModel()
        let question = try XCTUnwrap(model.state.currentQuestion)

        model.select(question.correctChoiceID)
        await model.waitForPendingPersistence()

        let saveCount = await store.saveCount
        XCTAssertEqual(saveCount, 0, "未確定の選択は保存しない")
    }

    func testResumedSessionContinuesWithoutDuplicatingAnswers() async throws {
        let model = makeModel()
        for _ in 0..<3 {
            try answerCurrentQuestionCorrectly(in: model)
            model.advance()
        }
        await model.waitForPendingPersistence()

        // 強制終了に相当。保存済みデータだけから新しいモデルを作り直す。
        let saved = await store.snapshot
        let snapshot = try XCTUnwrap(saved)
        let restoredState = try LearningSessionState.restored(
            from: snapshot,
            contentPack: DemoLearningContent.pack
        )
        let resumed = LearningSessionModel(
            state: restoredState,
            store: store,
            audioPlayer: audioPlayer,
            clock: clock,
            sessionID: snapshot.sessionID,
            startedAt: snapshot.startedAt
        )

        XCTAssertEqual(resumed.state.answeredCount, 3)
        XCTAssertEqual(resumed.state.currentIndex, 3)

        try answerCurrentQuestionCorrectly(in: resumed)
        await resumed.waitForPendingPersistence()

        let savedAfterResume = await store.snapshot
        let resumedSnapshot = try XCTUnwrap(savedAfterResume)
        XCTAssertEqual(resumedSnapshot.answers.count, 4, "復帰後の回答が重複しない")
        XCTAssertEqual(Set(resumedSnapshot.answers.map(\.questionID)).count, 4)
    }

    func testFinishingSessionClearsStoredProgress() async throws {
        let model = makeModel()
        try answerCurrentQuestionCorrectly(in: model)
        await model.waitForPendingPersistence()

        model.finish()
        await model.waitForPendingPersistence()

        let snapshot = await store.snapshot
        let clearCount = await store.clearCount
        XCTAssertNil(snapshot, "完了したセッションは再開対象に残さない")
        XCTAssertEqual(clearCount, 1)
    }

    func testPersistenceFailureIsSurfacedInsteadOfSwallowed() async throws {
        let model = LearningSessionModel.newSession(
            contentPack: DemoLearningContent.pack,
            store: FailingLearningSessionStore(),
            audioPlayer: audioPlayer,
            clock: clock,
            identifierGenerator: FixedIdentifierGenerator(),
            randomProvider: SeededRandomGeneratorProvider(seed: 7)
        )

        try answerCurrentQuestionCorrectly(in: model)
        await model.waitForPendingPersistence()

        XCTAssertTrue(model.hasPersistenceFailure)
    }

    // MARK: - 音声

    func testPlayingAudioCountsPlaybackAndUsesSelectedRate() async throws {
        let model = try makeModel(questionNumbers: [1])

        model.playCurrentQuestion(rate: .slow)
        await model.waitForAudioIdle()

        XCTAssertEqual(model.state.audioPlayCount, 1, "1回の再生は1回だけ数える")
        XCTAssertEqual(audioPlayer.playedRequests.count, 1)
        XCTAssertEqual(audioPlayer.playedRequests[0].rate, .slow)
        XCTAssertEqual(audioPlayer.playedRequests[0].text, "Selamat pagi.")
    }

    func testConversationQuestionPlaysEachSpeakerInOrder() async throws {
        // 31番は2話者の会話問題。
        let model = try makeModel(questionNumbers: [31])
        let question = try XCTUnwrap(model.state.currentQuestion)
        XCTAssertTrue(question.isConversation)

        model.playCurrentQuestion(rate: .standard)
        await model.waitForAudioIdle()

        XCTAssertEqual(audioPlayer.playedRequests.count, question.utterances.count)
        XCTAssertEqual(audioPlayer.playedRequests.map(\.text), question.utterances.map(\.text))
        XCTAssertEqual(audioPlayer.playedRequests.map(\.speakerIndex), [0, 1], "話者を分けて順に鳴らす")
        XCTAssertEqual(model.state.audioPlayCount, 1, "会話でも再生回数は1回")
    }

    func testReplayingStopsPreviousPlaybackInsteadOfOverlapping() async throws {
        audioPlayer.completesImmediately = false
        let model = try makeModel(questionNumbers: [1])

        model.playCurrentQuestion(rate: .standard)
        await model.waitUntil { self.audioPlayer.playedRequests.count == 1 }

        model.playCurrentQuestion(rate: .standard)
        await model.waitUntil { self.audioPlayer.playedRequests.count == 2 }

        model.stopAudio()
        await model.waitUntil { model.state.audioPlayCount == 2 }

        XCTAssertEqual(audioPlayer.playedRequests.count, 2, "2回目の再生が始まっている")
        XCTAssertGreaterThanOrEqual(audioPlayer.stopCount, 2, "前の再生を止めてから次を再生する")
        XCTAssertEqual(model.state.audioPlayCount, 2, "実際に始まった再生だけを数える")
    }

    func testAdvancingStopsAudioAndPreparesNextQuestion() async throws {
        let model = makeModel()
        model.playCurrentQuestion(rate: .standard)
        await model.waitForAudioIdle()

        try answerCurrentQuestionCorrectly(in: model)
        model.advance()

        XCTAssertEqual(model.audioState, .idle)
        XCTAssertGreaterThanOrEqual(audioPlayer.stopCount, 1)
        XCTAssertEqual(
            audioPlayer.preparedRequests.last?.questionID,
            model.state.currentQuestion?.id,
            "次問の音声を用意する"
        )
    }

    func testMissingVoiceIsReportedAsFailure() async throws {
        audioPlayer.playError = QuestionAudioError.voiceUnavailable
        let model = makeModel()

        model.playCurrentQuestion(rate: .standard)
        await model.waitForAudioIdle()

        XCTAssertEqual(model.audioState, .failed(.voiceUnavailable))
        XCTAssertEqual(model.state.audioPlayCount, 0, "開始に失敗した再生は回数に含めない")
    }

    func testInterruptionReturnsToIdleWithoutErrorBanner() async throws {
        audioPlayer.playError = QuestionAudioError.interrupted
        let model = makeModel()

        model.playCurrentQuestion(rate: .standard)
        await model.waitForAudioIdle()

        XCTAssertEqual(model.audioState, .idle, "中断は失敗として扱わない")
        XCTAssertEqual(model.state.audioPlayCount, 1, "中断でも再生は始まっている")
    }

    func testSpeechMarksDriveCompanionMouthPulse() async throws {
        audioPlayer.completesImmediately = false
        let model = makeModel()

        model.playCurrentQuestion(rate: .standard)
        await model.waitUntil { self.audioPlayer.playedRequests.count == 1 }
        audioPlayer.emitSpeechMarks(3)

        XCTAssertEqual(model.speechPulse, 3, "発話の拍がキャラクターの口の動きへ届く")

        model.stopAudio()
        await model.waitUntil { model.state.audioPlayCount == 1 }

        model.playCurrentQuestion(rate: .standard)
        XCTAssertEqual(model.speechPulse, 0, "再生を始め直したら拍もリセットする")
    }

    func testAudioDoesNotPlayAtMidpoint() async throws {
        let model = makeModel()

        for _ in 0..<LearningSessionState.checkpointQuestionCount {
            try answerCurrentQuestionCorrectly(in: model)
            model.advance()
        }
        XCTAssertEqual(model.state.phase, .midpoint)

        let requestsBeforeMidpoint = audioPlayer.playedRequests.count

        // 画面切り替えの途中で問題画面が再評価されても、次の問題の音声を鳴らさない。
        model.playCurrentQuestion(rate: .standard)
        await model.waitForAudioIdle()

        XCTAssertEqual(
            audioPlayer.playedRequests.count,
            requestsBeforeMidpoint,
            "中間結果では音声を再生しない"
        )
        XCTAssertEqual(model.audioState, .idle)
    }

    func testAudioDoesNotPlayOnFinalResult() async throws {
        let model = makeModel()

        for _ in 0..<LearningSessionPlanner.defaultQuestionCount {
            try answerCurrentQuestionCorrectly(in: model)
            model.advance()
            if model.state.phase == .midpoint {
                model.continueAfterMidpoint()
            }
        }
        XCTAssertEqual(model.state.phase, .finalResult)

        let requestsBeforeResult = audioPlayer.playedRequests.count

        model.playCurrentQuestion(rate: .standard)
        await model.waitForAudioIdle()

        XCTAssertEqual(
            audioPlayer.playedRequests.count,
            requestsBeforeResult,
            "総合結果では音声を再生しない"
        )
    }

    func testAdvancingIntoMidpointStopsPlayingAudio() async throws {
        audioPlayer.completesImmediately = false
        let model = makeModel()

        for _ in 0..<(LearningSessionState.checkpointQuestionCount - 1) {
            try answerCurrentQuestionCorrectly(in: model)
            model.advance()
        }

        model.playCurrentQuestion(rate: .standard)
        await model.waitUntil { self.audioPlayer.playedRequests.isEmpty == false }
        try answerCurrentQuestionCorrectly(in: model)
        model.advance()

        XCTAssertEqual(model.state.phase, .midpoint)
        XCTAssertEqual(model.audioState, .idle, "区切りへ移るときに再生を止める")
        XCTAssertGreaterThanOrEqual(audioPlayer.stopCount, 1)
    }

    // MARK: - 3ラウンドの通し

    func testThreeConsecutiveSessionsLeaveNoResidualState() async throws {
        for round in 1...3 {
            let model = makeModel()

            for index in 0..<LearningSessionPlanner.defaultQuestionCount {
                model.playCurrentQuestion(rate: .standard)
                await model.waitForAudioIdle()
                try answerCurrentQuestionCorrectly(in: model)
                model.advance()
                if model.state.phase == .midpoint {
                    model.continueAfterMidpoint()
                }
                XCTAssertEqual(model.state.answeredCount, index + 1, "round \(round)")
            }

            await model.waitForPendingPersistence()
            XCTAssertEqual(model.state.phase, .finalResult, "round \(round): 20問で総合結果に到達する")
            XCTAssertEqual(model.state.correctCount, LearningSessionPlanner.defaultQuestionCount, "round \(round)")
            XCTAssertEqual(model.audioState, .idle, "round \(round): 音声が鳴りっぱなしにならない")

            model.finish()
            await model.waitForPendingPersistence()

            let snapshot = await store.snapshot
            XCTAssertNil(snapshot, "round \(round): 完了後に再開データが残らない")
        }
    }

    func testRestartClearsAnswersAndKeepsSessionResumable() async throws {
        let model = makeModel()
        try answerCurrentQuestionCorrectly(in: model)
        model.advance()
        await model.waitForPendingPersistence()

        model.restart()
        await model.waitForPendingPersistence()

        XCTAssertEqual(model.state.answeredCount, 0)
        XCTAssertEqual(model.state.currentIndex, 0)
        let saved = await store.snapshot
        let snapshot = try XCTUnwrap(saved)
        XCTAssertTrue(snapshot.answers.isEmpty)
    }

    // MARK: - Helpers

    /// 出題を固定したモデル。音声の数え方など、特定の問題に依存する検証で使う。
    private func makeModel(questionNumbers: [Int]) throws -> LearningSessionModel {
        let pack = DemoLearningContent.pack
        let state = try LearningSessionState(
            contentPack: pack,
            plan: TestSession.makePlan(questionNumbers: questionNumbers, pack: pack)
        )
        return LearningSessionModel(
            state: state,
            store: store,
            audioPlayer: audioPlayer,
            clock: clock,
            sessionID: FixedIdentifierGenerator().newIdentifier(),
            startedAt: clock.now()
        )
    }

    private func makeModel() -> LearningSessionModel {
        LearningSessionModel.newSession(
            contentPack: DemoLearningContent.pack,
            store: store,
            audioPlayer: audioPlayer,
            clock: clock,
            identifierGenerator: FixedIdentifierGenerator(),
            randomProvider: SeededRandomGeneratorProvider(seed: 7)
        )
    }

    private func answerCurrentQuestionCorrectly(in model: LearningSessionModel) throws {
        let question = try XCTUnwrap(model.state.currentQuestion)
        model.select(question.correctChoiceID)
        model.submit()
    }
}

private extension LearningSessionModel {
    /// 再生タスクの完了を待つ。テストから再生状態を決定的に確認するために使う。
    func waitForAudioIdle() async {
        await waitUntil { self.audioState != .playing }
    }

    /// 同一アクター上で解決される再生タスクの完了を、上限付きで待ち合わせる。
    func waitUntil(_ condition: () -> Bool) async {
        var remainingAttempts = 1_000
        while !condition() && remainingAttempts > 0 {
            remainingAttempts -= 1
            await Task.yield()
        }
    }
}
