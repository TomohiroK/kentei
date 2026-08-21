import Foundation

/// アプリ全体の依存と、起動時の再開状態を所有する。
@MainActor
@Observable
final class AppModel {
    /// 保存済みセッションから再開できるかどうか。
    enum ResumeState: Equatable {
        case unavailable
        case available(answeredCount: Int, totalCount: Int, updatedAt: Date)

        var answeredCount: Int? {
            guard case let .available(answeredCount, _, _) = self else { return nil }
            return answeredCount
        }
    }

    private(set) var resumeState: ResumeState = .unavailable

    let contentPack: LearningContentPack

    private let store: any LearningSessionStoring
    private let audioPlayer: any QuestionAudioPlaying
    private let clock: any SessionClock
    private let identifierGenerator: any IdentifierGenerating
    private var restoredState: LearningSessionState?
    private var restoredSessionID: UUID?
    private var restoredStartedAt: Date?

    init(
        contentPack: LearningContentPack = DemoLearningContent.pack,
        store: any LearningSessionStoring,
        audioPlayer: any QuestionAudioPlaying = SpeechQuestionAudioPlayer(),
        clock: any SessionClock = SystemSessionClock(),
        identifierGenerator: any IdentifierGenerating = SystemIdentifierGenerator()
    ) {
        self.contentPack = contentPack
        self.store = store
        self.audioPlayer = audioPlayer
        self.clock = clock
        self.identifierGenerator = identifierGenerator
    }

    /// 既定の保存先を用意できない場合でも学習は継続できるようにする。
    static func live() -> AppModel {
        let store: any LearningSessionStoring
        do {
            store = FileLearningSessionStore(fileURL: try FileLearningSessionStore.defaultFileURL())
        } catch {
            store = DisabledLearningSessionStore()
        }
        return AppModel(store: store)
    }

    /// 保存済みセッションを読み、現行教材へ復帰できるかを判定する。
    ///
    /// 破損・教材版違い・問題構成違いは復帰させず、保存を破棄して新規開始できる状態に戻す。
    func refreshResumeState() async {
        do {
            guard let snapshot = try await store.load() else {
                clearRestored()
                return
            }

            let state = try LearningSessionState.restored(from: snapshot, contentPack: contentPack)
            guard state.answeredCount > 0 else {
                await discardStoredSession()
                return
            }

            restoredState = state
            restoredSessionID = snapshot.sessionID
            restoredStartedAt = snapshot.startedAt
            resumeState = .available(
                answeredCount: state.answeredCount,
                totalCount: state.questions.count,
                updatedAt: snapshot.updatedAt
            )
        } catch {
            await discardStoredSession()
        }
    }

    func makeNewSessionModel() -> LearningSessionModel {
        LearningSessionModel.newSession(
            contentPack: contentPack,
            store: store,
            audioPlayer: audioPlayer,
            clock: clock,
            identifierGenerator: identifierGenerator
        )
    }

    /// UIテストとプレビューで、決まった状態から始めるモデルを作る。
    func makeSessionModel(state: LearningSessionState) -> LearningSessionModel {
        LearningSessionModel(
            state: state,
            store: store,
            audioPlayer: audioPlayer,
            clock: clock,
            sessionID: identifierGenerator.newIdentifier(),
            startedAt: clock.now()
        )
    }

    /// 復帰可能な保存データがある場合だけ、その続きから始めるモデルを作る。
    func makeResumedSessionModel() -> LearningSessionModel? {
        guard let restoredState, let restoredSessionID, let restoredStartedAt else { return nil }
        return LearningSessionModel(
            state: restoredState,
            store: store,
            audioPlayer: audioPlayer,
            clock: clock,
            sessionID: restoredSessionID,
            startedAt: restoredStartedAt
        )
    }

    private func discardStoredSession() async {
        try? await store.clear()
        clearRestored()
    }

    private func clearRestored() {
        restoredState = nil
        restoredSessionID = nil
        restoredStartedAt = nil
        resumeState = .unavailable
    }
}
