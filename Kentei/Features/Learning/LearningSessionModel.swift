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

    private let store: any LearningSessionStoring
    private let audioPlayer: any QuestionAudioPlaying
    private let clock: any SessionClock
    private let sessionID: UUID
    private let startedAt: Date
    private var persistenceChain: Task<Void, Never>?

    private var playbackTask: Task<Void, Never>?

    init(
        state: LearningSessionState,
        store: any LearningSessionStoring,
        audioPlayer: any QuestionAudioPlaying,
        clock: any SessionClock,
        sessionID: UUID,
        startedAt: Date
    ) {
        self.state = state
        self.store = store
        self.audioPlayer = audioPlayer
        self.clock = clock
        self.sessionID = sessionID
        self.startedAt = startedAt

        audioPlayer.onSpeechMark = { [weak self] in
            self?.speechPulse += 1
        }
    }

    static func newSession(
        contentPack: LearningContentPack,
        store: any LearningSessionStoring,
        audioPlayer: any QuestionAudioPlaying,
        clock: any SessionClock,
        identifierGenerator: any IdentifierGenerating
    ) -> LearningSessionModel {
        LearningSessionModel(
            state: LearningSessionState(contentPack: contentPack),
            store: store,
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
    func playCurrentQuestion(rate: PlaybackRate) {
        guard let question = state.currentQuestion else { return }

        playbackTask?.cancel()
        audioPlayer.stop()
        audioState = .playing
        speechPulse = 0

        playbackTask = Task { [audioPlayer] in
            // 開始前に次の再生へ置き換えられた場合は、鳴らさず数えない。
            guard !Task.isCancelled else { return }
            do {
                try await audioPlayer.play(
                    QuestionAudioRequest(
                        questionID: question.id,
                        text: question.transcript,
                        rate: rate
                    )
                )
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
    func stopAudio() {
        playbackTask?.cancel()
        playbackTask = nil
        audioPlayer.stop()
        audioState = .idle
    }

    func submit() {
        guard state.submit(at: clock.now()) else { return }
        persist()
    }

    func advance() {
        let previousPhase = state.phase
        let previousIndex = state.currentIndex
        stopAudio()
        state.advance()
        prepareNextQuestionAudio()
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
        audioPlayer.prepare(
            QuestionAudioRequest(questionID: question.id, text: question.transcript, rate: .standard)
        )
    }

    private func persist() {
        let snapshot = state.snapshot(
            sessionID: sessionID,
            startedAt: startedAt,
            updatedAt: clock.now()
        )
        let previous = persistenceChain
        persistenceChain = Task { [store] in
            await previous?.value
            do {
                try await store.save(snapshot)
                self.hasPersistenceFailure = false
            } catch {
                self.hasPersistenceFailure = true
            }
        }
    }
}
