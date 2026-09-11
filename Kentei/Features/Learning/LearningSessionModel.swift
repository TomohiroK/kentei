import Foundation

/// 1回の学習セッションの進行と保存を所有する。
///
/// 回答確定・区切り通過・再挑戦のたびにローカル保存し、途中離脱しても
/// 最後の完了問題から再開できる状態を常に残す。未確定の選択は保存しない。
@MainActor
@Observable
final class LearningSessionModel: Identifiable {
    nonisolated var id: UUID { sessionID }

    private(set) var state: LearningSessionState
    /// 保存に失敗したことをUIへ伝える。失敗を握りつぶして学習を続けさせない。
    private(set) var hasPersistenceFailure = false

    /// 音声再生の状態。学習画面の中心操作なので、失敗も含めて明示的に持つ。
    enum AudioPlaybackState: Equatable {
        case idle
        case playing
        case failed(QuestionAudioError)
    }

    private(set) var audioState: AudioPlaybackState = .idle
    /// 発話の拍。増えるたびにキャラクターが一度口を動かす。
    private(set) var speechPulse = 0
    /// 性能の実測。問題表示と音声開始が目標内かを見る。
    let performance: PerformanceRecorder

    private let store: any LearningSessionStoring
    private let masteryStore: any MasteryStoring
    private let masteryEvaluator: MasteryEvaluator
    private let syncQueue: AnswerSyncQueue?
    private let origin: LearningSessionOrigin
    private let practicalCheckEvaluator: PracticalCheckEvaluator
    private var practicalChecks: [ScenarioID: PracticalCheckResult]
    private var masteryRecords: [QuestionID: QuestionMastery]
    private let audioPlayer: any QuestionAudioPlaying
    private let clock: any SessionClock
    private let sessionID: UUID
    private let startedAt: Date
    private var persistenceChain: Task<Void, Never>?

    private var playbackTask: Task<Void, Never>?
    private var questionShownRequestedAt: Date?
    private var playbackRequestedAt: Date?

    init(
        state: LearningSessionState,
        store: any LearningSessionStoring,
        masteryStore: any MasteryStoring = DisabledMasteryStore(),
        masteryRecords: [QuestionID: QuestionMastery] = [:],
        masteryEvaluator: MasteryEvaluator = MasteryEvaluator(),
        syncQueue: AnswerSyncQueue? = nil,
        origin: LearningSessionOrigin = .recommended,
        practicalChecks: [ScenarioID: PracticalCheckResult] = [:],
        practicalCheckEvaluator: PracticalCheckEvaluator = PracticalCheckEvaluator(),
        performance: PerformanceRecorder = PerformanceRecorder(),
        audioPlayer: any QuestionAudioPlaying,
        clock: any SessionClock,
        sessionID: UUID,
        startedAt: Date
    ) {
        self.state = state
        self.store = store
        self.masteryStore = masteryStore
        self.masteryRecords = masteryRecords
        self.masteryEvaluator = masteryEvaluator
        self.syncQueue = syncQueue
        self.origin = origin
        self.practicalChecks = practicalChecks
        self.practicalCheckEvaluator = practicalCheckEvaluator
        self.performance = performance
        self.audioPlayer = audioPlayer
        self.clock = clock
        self.sessionID = sessionID
        self.startedAt = startedAt
        questionShownRequestedAt = clock.now()

        audioPlayer.onSpeechMark = { [weak self] in
            guard let self else { return }
            // 最初の発話が始まった時点を「音声開始」とする。
            if let requestedAt = playbackRequestedAt {
                performance.record(.audioStart, duration: clock.now().timeIntervalSince(requestedAt))
                playbackRequestedAt = nil
            }
            speechPulse += 1
        }
    }

    /// 出題順と選択肢順を毎回引き直して、新しいセッションを始める。
    static func newSession(
        contentPack: LearningContentPack,
        origin: LearningSessionOrigin = .recommended,
        store: any LearningSessionStoring,
        masteryStore: any MasteryStoring = DisabledMasteryStore(),
        masteryRecords: [QuestionID: QuestionMastery] = [:],
        masteryEvaluator: MasteryEvaluator = MasteryEvaluator(),
        syncQueue: AnswerSyncQueue? = nil,
        practicalChecks: [ScenarioID: PracticalCheckResult] = [:],
        audioPlayer: any QuestionAudioPlaying,
        clock: any SessionClock,
        identifierGenerator: any IdentifierGenerating,
        randomProvider: any RandomGeneratorProviding
    ) -> LearningSessionModel {
        var generator = randomProvider.makeGenerator()
        let plan = LearningSessionPlanner.makePlan(
            from: contentPack,
            origin: origin,
            mastery: masteryRecords,
            at: clock.now(),
            questionCount: origin.sessionQuestionCount,
            using: &generator
        )
        // 計画は教材パックそのものから作るため食い違わない。万一に備え原稿順へ落とす。
        let state = (try? LearningSessionState(contentPack: contentPack, plan: plan))
            ?? LearningSessionState(contentPack: contentPack)

        return LearningSessionModel(
            state: state,
            store: store,
            masteryStore: masteryStore,
            masteryRecords: masteryRecords,
            masteryEvaluator: masteryEvaluator,
            syncQueue: syncQueue,
            origin: origin,
            practicalChecks: practicalChecks,
            audioPlayer: audioPlayer,
            clock: clock,
            sessionID: identifierGenerator.newIdentifier(),
            startedAt: clock.now()
        )
    }

    func select(_ choiceID: ChoiceID) {
        state.select(choiceID)
    }

    /// 現在の問題の音声を再生する。連打しても多重再生にならないよう、前の再生を止めてから始める。
    ///
    /// 回答中以外では鳴らさない。区切りや結果の画面へ切り替わる途中で問題画面が
    /// 新しい問題として再評価されても、次の問題の音声が先走らないようにする。
    func playCurrentQuestion(rate: PlaybackRate) {
        guard state.phase == .answering, let question = state.currentQuestion else { return }

        playbackTask?.cancel()
        audioPlayer.stop()
        audioState = .playing
        speechPulse = 0
        playbackRequestedAt = clock.now()

        playbackTask = Task { [audioPlayer] in
            // 開始前に次の再生へ置き換えられた場合は、鳴らさず数えない。
            guard !Task.isCancelled else { return }
            do {
                // 会話問題は話者ごとの発話を順に鳴らす。単独発話は1件だけ。
                for utterance in question.utterances {
                    try await audioPlayer.play(
                        QuestionAudioRequest(
                            questionID: question.id,
                            text: utterance.text,
                            speakerIndex: utterance.speakerIndex,
                            rate: rate
                        )
                    )
                }
                // 再生が実際に始まった場合だけ数える。開始に失敗した試行は学習イベントにしない。
                state.registerAudioPlayback()
                audioState = .idle
            } catch is CancellationError {
                state.registerAudioPlayback()
                audioState = .idle
            } catch QuestionAudioError.interrupted {
                state.registerAudioPlayback()
                audioState = .idle
            } catch let error as QuestionAudioError {
                audioState = .failed(error)
            } catch {
                audioState = .failed(.sessionUnavailable)
            }
        }
    }

    /// 画面離脱・セッション終了・問題切り替えで再生を止める。
    /// 問題が画面に出た時点を記録する。表示までの時間が目標内かを見る。
    func recordQuestionDisplayed() {
        guard let requestedAt = questionShownRequestedAt else { return }
        performance.record(.questionDisplay, duration: clock.now().timeIntervalSince(requestedAt))
        questionShownRequestedAt = nil
    }

    func stopAudio() {
        playbackTask?.cancel()
        playbackTask = nil
        audioPlayer.stop()
        audioState = .idle
    }

    func submit() {
        guard state.submit(at: clock.now()) else { return }

        // 回答は習得記録にも即時反映する。生活図鑑の解放判定はこの記録だけを根拠にする。
        if let answer = state.answers.last {
            masteryRecords[answer.questionID] = masteryEvaluator.updated(
                masteryRecords[answer.questionID],
                with: answer
            )
            enqueueForSync(answer)
        }
        persist()
    }

    func advance() {
        let previousPhase = state.phase
        let previousIndex = state.currentIndex
        stopAudio()
        state.advance()
        questionShownRequestedAt = clock.now()
        prepareNextQuestionAudio()
        evaluatePracticalCheckIfFinished()
        guard state.phase != previousPhase || state.currentIndex != previousIndex else { return }
        persist()
    }

    func continueAfterMidpoint() {
        guard state.phase == .midpoint else { return }
        state.continueAfterMidpoint()
        persist()
    }

    func restart() {
        state.restart()
        persist()
    }

    /// セッションを完了として閉じる。保存済みの再開データは破棄する。
    func finish() {
        stopAudio()
        let previous = persistenceChain
        persistenceChain = Task { [store] in
            await previous?.value
            do {
                try await store.clear()
            } catch {
                self.hasPersistenceFailure = true
            }
        }
    }

    /// 保存の完了を待つ。テストと、画面を閉じる直前の取りこぼし防止に使う。
    func waitForPendingPersistence() async {
        await persistenceChain?.value
    }

    /// 次問の音声を用意する。実音声アセット実装ではここが先読みになる。
    private func prepareNextQuestionAudio() {
        guard let question = state.currentQuestion else { return }
        for utterance in question.utterances {
            audioPlayer.prepare(
                QuestionAudioRequest(
                    questionID: question.id,
                    text: utterance.text,
                    speakerIndex: utterance.speakerIndex,
                    rate: .standard
                )
            )
        }
    }

    /// 実戦チェックのセッションが終わったら採点し、結果を保存する。
    private func evaluatePracticalCheckIfFinished() {
        guard state.phase == .finalResult,
              let scenarioID = origin.practicalCheckScenarioID else {
            return
        }

        practicalChecks[scenarioID] = practicalCheckEvaluator.evaluate(
            scenarioID: scenarioID,
            answers: state.answers,
            at: clock.now()
        )
        persist()
    }

    /// このセッションの実戦チェック結果。実戦チェック以外では nil。
    var practicalCheckResult: PracticalCheckResult? {
        guard let scenarioID = origin.practicalCheckScenarioID else { return nil }
        return practicalChecks[scenarioID]
    }

    /// 回答を未同期キューへ積む。オフラインでも積み、再接続後に一度だけ送る。
    private func enqueueForSync(_ answer: AnsweredQuestion) {
        guard let syncQueue else { return }

        let pending = PendingAnswer(
            key: SyncIdempotencyKey(sessionID: sessionID, questionID: answer.questionID, attempt: 1),
            answer: answer,
            contentVersion: state.contentVersion,
            queuedAt: clock.now()
        )
        Task {
            await syncQueue.enqueue(pending)
        }
    }

    private func persist() {
        let snapshot = state.snapshot(
            sessionID: sessionID,
            startedAt: startedAt,
            updatedAt: clock.now()
        )
        let records = MasteryRecords(
            settingsVersion: masteryEvaluator.settings.version,
            records: Array(masteryRecords.values).sorted { $0.questionID.rawValue < $1.questionID.rawValue },
            practicalChecks: Array(practicalChecks.values).sorted { $0.scenarioID.rawValue < $1.scenarioID.rawValue }
        )
        let previous = persistenceChain
        persistenceChain = Task { [store, masteryStore] in
            await previous?.value
            do {
                try await store.save(snapshot)
                try await masteryStore.save(records)
                self.hasPersistenceFailure = false
            } catch {
                self.hasPersistenceFailure = true
            }
        }
    }
}
