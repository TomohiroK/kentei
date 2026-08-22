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
    /// 習得記録。生活図鑑の達成率と復習の優先度はこれを根拠にする。
    private(set) var mastery: [QuestionID: QuestionMastery] = [:]
    /// 初回導入で受け取った学習者の前提。未設定なら初回導入から始める。
    private(set) var learnerProfile: LearnerProfile?

    var needsOnboarding: Bool {
        learnerProfile == nil
    }

    /// 表示言語。初回導入の選択を全画面へ適用する。
    var interfaceLocale: Locale {
        Locale(identifier: (learnerProfile?.interfaceLanguage ?? .systemDefault).localeIdentifier)
    }

    /// 初回導入の聞こえ確認で使う。学習セッションと同じ再生実装を共有する。
    var sampleAudioPlayer: any QuestionAudioPlaying {
        audioPlayer
    }

    private(set) var contentPack: LearningContentPack
    /// 適用しなかった教材の不備。教材管理側へ差し戻す材料として画面に出す。
    private(set) var contentIssues: [ContentIssue] = []

    private let store: any LearningSessionStoring
    private let masteryStore: any MasteryStoring
    private let masteryEvaluator: MasteryEvaluator
    private let atlasEvaluator: LifeAtlasEvaluator
    private let audioPlayer: any QuestionAudioPlaying
    private let clock: any SessionClock
    private let identifierGenerator: any IdentifierGenerating
    private let randomProvider: any RandomGeneratorProviding
    private let profileStore: any LearnerProfileStoring
    private var restoredState: LearningSessionState?
    private var restoredSessionID: UUID?
    private var restoredStartedAt: Date?

    init(
        contentPack: LearningContentPack = DemoLearningContent.pack,
        store: any LearningSessionStoring,
        masteryStore: any MasteryStoring = DisabledMasteryStore(),
        masteryEvaluator: MasteryEvaluator = MasteryEvaluator(),
        atlasEvaluator: LifeAtlasEvaluator = LifeAtlasEvaluator(),
        audioPlayer: any QuestionAudioPlaying = SpeechQuestionAudioPlayer(),
        clock: any SessionClock = SystemSessionClock(),
        identifierGenerator: any IdentifierGenerating = SystemIdentifierGenerator(),
        randomProvider: any RandomGeneratorProviding = SystemRandomGeneratorProvider(),
        profileStore: any LearnerProfileStoring = UserDefaultsLearnerProfileStore()
    ) {
        // 検証を通った版だけを有効にする。落ちた場合も学習を止めず、不備を画面に出す。
        let activation = ContentPackActivator().activate(candidate: contentPack, current: nil)
        switch activation {
        case let .success(result):
            self.contentPack = result.pack
            contentIssues = result.rejectedIssues
        case let .failure(.noUsablePack(issues)), let .failure(.rejected(issues)):
            self.contentPack = contentPack
            contentIssues = issues
        }
        self.store = store
        self.masteryStore = masteryStore
        self.masteryEvaluator = masteryEvaluator
        self.atlasEvaluator = atlasEvaluator
        self.audioPlayer = audioPlayer
        self.clock = clock
        self.identifierGenerator = identifierGenerator
        self.randomProvider = randomProvider
        self.profileStore = profileStore
        learnerProfile = profileStore.load()
    }

    /// 初回導入の完了を保存する。以降の起動では導入を出さない。
    func completeOnboarding(with profile: LearnerProfile) {
        profileStore.save(profile)
        learnerProfile = profile
    }

    /// 既定の保存先を用意できない場合でも学習は継続できるようにする。
    static func live(profileStore: any LearnerProfileStoring = UserDefaultsLearnerProfileStore()) -> AppModel {
        let stores = makeStores()
        return AppModel(store: stores.session, masteryStore: stores.mastery, profileStore: profileStore)
    }

    /// 保存先を用意できない場合は、保存しない実装へまとめて落とす。片方だけ保存する状態を作らない。
    private static func makeStores() -> (session: any LearningSessionStoring, mastery: any MasteryStoring) {
        do {
            return (
                FileLearningSessionStore(fileURL: try FileLearningSessionStore.defaultFileURL()),
                FileMasteryStore(fileURL: try FileMasteryStore.defaultFileURL())
            )
        } catch {
            return (DisabledLearningSessionStore(), DisabledMasteryStore())
        }
    }

    /// 保存済みの学習データと初回導入の結果を消す。UIテストを決まった状態から始めるために使う。
    func resetStoredLearningData() async {
        try? await store.clear()
        try? await masteryStore.clear()
        mastery = [:]
        profileStore.clear()
        learnerProfile = profileStore.load()
        clearRestored()
    }

    /// 保存済みセッションを読み、現行教材へ復帰できるかを判定する。
    ///
    /// 破損・教材版違い・問題構成違いは復帰させず、保存を破棄して新規開始できる状態に戻す。
    /// 習得記録を読み直す。読めない場合は空として扱い、学習を止めない。
    func refreshMastery() async {
        mastery = ((try? await masteryStore.load()) ?? nil)?.byQuestionID ?? [:]
    }

    /// 生活図鑑の各カテゴリの進捗。解放判定の根拠つきで返す。
    func scenarioProgressList(at date: Date? = nil) -> [ScenarioProgress] {
        let evaluatedAt = date ?? clock.now()
        return DemoLifeAtlas.scenarios.map { scenario in
            atlasEvaluator.progress(
                for: scenario,
                pack: contentPack,
                mastery: mastery,
                at: evaluatedAt
            )
        }
    }

    /// 生活図鑑全体の達成率。
    func atlasAchievement(at date: Date? = nil) -> Double {
        let list = scenarioProgressList(at: date)
        let totalActions = list.reduce(0) { $0 + $1.actionStatuses.count }
        guard totalActions > 0 else { return 0 }
        let unlocked = list.reduce(0) { $0 + $1.unlockedActionCount }
        return Double(unlocked) / Double(totalActions)
    }

    /// 復習対象の問題数。ホームと学習入口に出す。
    func reviewDueCount(at date: Date? = nil) -> Int {
        let evaluatedAt = date ?? clock.now()
        return contentPack.questions.count { question in
            switch mastery[question.id]?.state(at: evaluatedAt) {
            case .dueForReview, .relearning: true
            default: false
            }
        }
    }

    var masteredQuestionCount: Int {
        let now = clock.now()
        return contentPack.questions.count { mastery[$0.id]?.isMastered(at: now) == true }
    }

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

    func makeNewSessionModel(origin: LearningSessionOrigin = .recommended) -> LearningSessionModel {
        LearningSessionModel.newSession(
            contentPack: contentPack,
            origin: origin,
            store: store,
            masteryStore: masteryStore,
            masteryRecords: mastery,
            masteryEvaluator: masteryEvaluator,
            audioPlayer: audioPlayer,
            clock: clock,
            identifierGenerator: identifierGenerator,
            randomProvider: randomProvider
        )
    }

    /// UIテストとプレビューで、決まった状態から始めるモデルを作る。
    func makeSessionModel(state: LearningSessionState) -> LearningSessionModel {
        LearningSessionModel(
            state: state,
            store: store,
            masteryStore: masteryStore,
            masteryRecords: mastery,
            masteryEvaluator: masteryEvaluator,
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
            masteryStore: masteryStore,
            masteryRecords: mastery,
            masteryEvaluator: masteryEvaluator,
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
