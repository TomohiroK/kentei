import Foundation

/// 習得状態。1回の正解では `mastered` にしない。
enum MasteryState: String, Codable, Equatable, Sendable {
    case unseen
    case learning
    case provisional
    case mastered
    case dueForReview
    case relearning
}

/// 問題1件の習得記録。
struct QuestionMastery: Codable, Equatable, Sendable {
    let questionID: QuestionID
    var state: MasteryState
    var masteryScore: Int
    var correctStreak: Int
    var incorrectStreak: Int
    var lastAnsweredAt: Date?
    var nextReviewAt: Date?
    /// 判定に使った設定の版。係数を変えても過去の判定根拠を説明できるようにする。
    var evaluatedWithSettingsVersion: String

    init(
        questionID: QuestionID,
        state: MasteryState = .unseen,
        masteryScore: Int = 0,
        correctStreak: Int = 0,
        incorrectStreak: Int = 0,
        lastAnsweredAt: Date? = nil,
        nextReviewAt: Date? = nil,
        evaluatedWithSettingsVersion: String = MasteryScoringSettings.current.version
    ) {
        self.questionID = questionID
        self.state = state
        self.masteryScore = masteryScore
        self.correctStreak = correctStreak
        self.incorrectStreak = incorrectStreak
        self.lastAnsweredAt = lastAnsweredAt
        self.nextReviewAt = nextReviewAt
        self.evaluatedWithSettingsVersion = evaluatedWithSettingsVersion
    }

    /// 復習期限を過ぎた習得済みは、復習対象として扱う。
    func state(at date: Date) -> MasteryState {
        guard state == .mastered, let nextReviewAt, date >= nextReviewAt else { return state }
        return .dueForReview
    }

    func isMastered(at date: Date) -> Bool {
        state(at: date) == .mastered
    }
}

/// 習得点と状態遷移の運用設定。コード定数ではなく設定値として扱い、版を判定結果に残す。
struct MasteryScoringSettings: Codable, Equatable, Sendable {
    static let current = MasteryScoringSettings(
        version: "mastery-2026-08-v1",
        correct: 10,
        replayedOnce: 1,
        replayedManyTimes: 0,
        incorrect: -5,
        repeatedMistake: -3,
        provisionalScore: 10,
        masteredScore: 20,
        requiredCorrectStreak: 2,
        reviewIntervalDays: 7,
        manyReplaysThreshold: 3
    )

    let version: String
    let correct: Int
    let replayedOnce: Int
    let replayedManyTimes: Int
    let incorrect: Int
    let repeatedMistake: Int
    let provisionalScore: Int
    let masteredScore: Int
    let requiredCorrectStreak: Int
    let reviewIntervalDays: Int
    let manyReplaysThreshold: Int
}

/// 回答から習得記録を更新する。副作用を持たず、同じ入力からは同じ結果になる。
struct MasteryEvaluator: Sendable {
    let settings: MasteryScoringSettings
    let calendar: Calendar

    init(settings: MasteryScoringSettings = .current, calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.settings = settings
        self.calendar = calendar
    }

    func updated(_ current: QuestionMastery?, with answer: AnsweredQuestion) -> QuestionMastery {
        var record = current ?? QuestionMastery(questionID: answer.questionID)

        record.masteryScore += scoreDelta(for: answer, previous: current)
        record.evaluatedWithSettingsVersion = settings.version
        record.lastAnsweredAt = answer.answeredAt

        if answer.isCorrect {
            record.correctStreak += 1
            record.incorrectStreak = 0
        } else {
            record.correctStreak = 0
            record.incorrectStreak += 1
        }

        record.state = nextState(for: record, wasCorrect: answer.isCorrect, previousState: current?.state ?? .unseen)
        record.nextReviewAt = record.state == .mastered
            ? calendar.date(byAdding: .day, value: settings.reviewIntervalDays, to: answer.answeredAt)
            : nil

        return record
    }

    private func scoreDelta(for answer: AnsweredQuestion, previous: QuestionMastery?) -> Int {
        var delta = answer.isCorrect ? settings.correct : settings.incorrect

        if answer.isCorrect {
            delta += answer.audioPlayCount >= settings.manyReplaysThreshold
                ? settings.replayedManyTimes
                : settings.replayedOnce
        } else if (previous?.incorrectStreak ?? 0) > 0 {
            // 同じ問題を続けて間違えた場合は、弱点として強く扱う。
            delta += settings.repeatedMistake
        }

        return delta
    }

    private func nextState(
        for record: QuestionMastery,
        wasCorrect: Bool,
        previousState: MasteryState
    ) -> MasteryState {
        guard wasCorrect else {
            return previousState == .mastered || previousState == .dueForReview ? .relearning : .learning
        }

        if record.masteryScore >= settings.masteredScore, record.correctStreak >= settings.requiredCorrectStreak {
            return .mastered
        }
        if record.masteryScore >= settings.provisionalScore {
            return .provisional
        }
        return .learning
    }
}

/// 行動の解放条件。閾値は教材検証で調整できるよう設定値として持つ。
struct UnlockPolicy: Codable, Equatable, Sendable {
    static let current = UnlockPolicy(version: "unlock-2026-08-v1", requiredMasteredRatio: 0.8)

    let version: String
    /// 関連問題のうち習得済みが占める割合の下限。
    let requiredMasteredRatio: Double
}

/// 行動1件の解放判定。根拠（必要問題・習得済み・使用した設定版）を伴う。
struct ActionUnlockStatus: Identifiable, Equatable, Sendable {
    let action: LifeAction
    let masteredQuestionIDs: [QuestionID]
    let isUnlocked: Bool
    /// 実戦チェックの合格も条件か。条件なら合否も根拠に含める。
    let requiresPracticalCheck: Bool
    let hasPassedPracticalCheck: Bool
    let policyVersion: String
    let atlasVersion: String

    var id: ActionID { action.id }

    var requiredCount: Int { action.requiredQuestionIDs.count }
    var masteredCount: Int { masteredQuestionIDs.count }

    var progress: Double {
        guard requiredCount > 0 else { return 0 }
        return Double(masteredCount) / Double(requiredCount)
    }

    /// 解放までに残っている問題数。ロック理由を利用者に推測させないために使う。
    var remainingCount: Int {
        max(requiredCount - masteredCount, 0)
    }

    /// 問題は足りているが、実戦チェックだけが残っている状態。
    var awaitsPracticalCheck: Bool {
        requiresPracticalCheck && hasPassedPracticalCheck == false && remainingCount == 0
    }
}

/// 生活図鑑のカテゴリ1件の進捗。
struct ScenarioProgress: Identifiable, Equatable, Sendable {
    let scenario: LifeScenario
    let actionStatuses: [ActionUnlockStatus]
    let questionCount: Int
    let masteredQuestionCount: Int
    let dueForReviewQuestionIDs: [QuestionID]
    /// 直近の実戦チェック結果。未実施なら nil。
    let practicalCheck: PracticalCheckResult?

    var requiresPracticalCheck: Bool {
        scenario.actions.contains { $0.requiresPracticalCheck }
    }

    var id: ScenarioID { scenario.id }

    var unlockedActionCount: Int {
        actionStatuses.count(where: \.isUnlocked)
    }

    /// 達成率は解放済み行動の割合とする。
    var achievement: Double {
        guard actionStatuses.isEmpty == false else { return 0 }
        return Double(unlockedActionCount) / Double(actionStatuses.count)
    }
}

/// 習得記録から生活図鑑の進捗を組み立てる。
struct LifeAtlasEvaluator: Sendable {
    let policy: UnlockPolicy
    let atlasVersion: String

    init(policy: UnlockPolicy = .current, atlasVersion: String = DemoLifeAtlas.version) {
        self.policy = policy
        self.atlasVersion = atlasVersion
    }

    func progress(
        for scenario: LifeScenario,
        pack: LearningContentPack,
        mastery: [QuestionID: QuestionMastery],
        practicalCheck: PracticalCheckResult? = nil,
        at date: Date
    ) -> ScenarioProgress {
        let statuses = scenario.actions.map { action in
            unlockStatus(for: action, mastery: mastery, practicalCheck: practicalCheck, at: date)
        }

        let questionIDs = scenario.questionIDs(in: pack)
        let masteredQuestionIDs = questionIDs.filter { mastery[$0]?.isMastered(at: date) == true }
        let dueForReview = questionIDs.filter { mastery[$0]?.state(at: date) == .dueForReview }

        return ScenarioProgress(
            scenario: scenario,
            actionStatuses: statuses,
            questionCount: questionIDs.count,
            masteredQuestionCount: masteredQuestionIDs.count,
            dueForReviewQuestionIDs: dueForReview,
            practicalCheck: practicalCheck
        )
    }

    func unlockStatus(
        for action: LifeAction,
        mastery: [QuestionID: QuestionMastery],
        practicalCheck: PracticalCheckResult? = nil,
        at date: Date
    ) -> ActionUnlockStatus {
        let mastered = action.requiredQuestionIDs.filter { mastery[$0]?.isMastered(at: date) == true }
        let ratio = action.requiredQuestionIDs.isEmpty
            ? 0
            : Double(mastered.count) / Double(action.requiredQuestionIDs.count)

        let hasPassed = practicalCheck?.isPassed == true
        let meetsMastery = ratio >= policy.requiredMasteredRatio
        // 実戦チェックが要る行動は、問題の習得だけでは解放しない。
        let isUnlocked = meetsMastery && (action.requiresPracticalCheck == false || hasPassed)

        return ActionUnlockStatus(
            action: action,
            masteredQuestionIDs: mastered,
            isUnlocked: isUnlocked,
            requiresPracticalCheck: action.requiresPracticalCheck,
            hasPassedPracticalCheck: hasPassed,
            policyVersion: policy.version,
            atlasVersion: atlasVersion
        )
    }
}
