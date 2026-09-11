import Foundation

struct QuestionID: Hashable, Sendable, RawRepresentable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

struct ChoiceID: Hashable, Sendable, RawRepresentable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// 保存データを読みやすく保つため、識別子は入れ子オブジェクトではなく素の文字列として符号化する。
extension QuestionID: Codable {
    init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension ChoiceID: Codable {
    init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct LearningChoice: Identifiable, Equatable, Sendable {
    let id: ChoiceID
    let text: String
    let isCorrect: Bool
    /// 誤答を作った理由。正答には持たせない。無作為な誤答を公開しないための記録。
    let distractorReason: DistractorReason?

    init(id: ChoiceID, text: String, isCorrect: Bool = false, distractorReason: DistractorReason? = nil) {
        self.id = id
        self.text = text
        self.isCorrect = isCorrect
        self.distractorReason = distractorReason
    }
}

/// 出題音声の1発話。会話問題では話者を分けて複数持つ。
struct ScriptedUtterance: Equatable, Sendable {
    let speakerIndex: Int
    let text: String
}

struct LearningQuestion: Identifiable, Equatable, Sendable {
    let id: QuestionID
    let level: CertificationLevel
    let questionType: QuestionType
    let status: ContentStatus
    let utterances: [ScriptedUtterance]
    /// 原稿順の選択肢。学習者に見える順序はセッションごとに決まる。
    let choices: [LearningChoice]
    let correctChoiceID: ChoiceID
    let explanation: String
    /// この問題が属する生活図鑑のカテゴリ。級別入口と生活図鑑入口で同じ教材を使うための紐付け。
    let scenarioIDs: [ScenarioID]

    /// 回答後に表示する本文。会話問題は話者ごとに行を分ける。
    var transcript: String {
        utterances.map(\.text).joined(separator: "\n")
    }

    var isConversation: Bool {
        utterances.count > 1
    }

    var primaryScenarioID: ScenarioID? {
        scenarioIDs.first
    }

    func reordering(choiceIDs: [ChoiceID]) -> LearningQuestion? {
        guard choiceIDs.count == choices.count else { return nil }

        var reordered: [LearningChoice] = []
        reordered.reserveCapacity(choiceIDs.count)
        for choiceID in choiceIDs {
            guard let choice = choices.first(where: { $0.id == choiceID }) else { return nil }
            reordered.append(choice)
        }

        return LearningQuestion(
            id: id,
            level: level,
            questionType: questionType,
            status: status,
            utterances: utterances,
            choices: reordered,
            correctChoiceID: correctChoiceID,
            explanation: explanation,
            scenarioIDs: scenarioIDs
        )
    }
}

/// バージョン付きの教材パック。版が変わった保存データは復帰対象にしない。
///
/// 公開済み教材は上書きせず、新しい版を作る。チェックサムは内容から決まり、
/// 読み込み時の破損検知に使う。
struct LearningContentPack: Equatable, Sendable {
    let version: String
    let checksum: String
    let questions: [LearningQuestion]

    init(version: String, questions: [LearningQuestion]) {
        self.init(version: version, questions: questions, checksum: LearningContentPack.checksum(of: questions))
    }

    /// チェックサムを外から与える入口。配信されたパックの申告値を検証するために使う。
    init(version: String, questions: [LearningQuestion], checksum: String) {
        self.version = version
        self.questions = questions
        self.checksum = checksum
    }

    func question(with id: QuestionID) -> LearningQuestion? {
        questions.first { $0.id == id }
    }

    /// 新規セッションで出題してよい問題。公開済み・提供級・採点できる形式に限る。
    var deliverableQuestions: [LearningQuestion] {
        questions.filter { question in
            question.status.isDeliverable
                && question.level.isProvided
                && question.questionType.isDeliverable
        }
    }

    func deliverableQuestions(at level: CertificationLevel) -> [LearningQuestion] {
        deliverableQuestions.filter { $0.level == level }
    }
}

/// セッション1回分の出題内容。出題順と選択肢の並びはここで確定する。
struct LearningSessionPlan: Equatable, Sendable, Codable {
    struct Entry: Equatable, Sendable, Codable {
        let questionID: QuestionID
        /// 表示順の選択肢。`nil` は教材の原稿順（保存形式v1からの復帰）を意味する。
        let choiceIDs: [ChoiceID]?
    }

    let entries: [Entry]

    var questionIDs: [QuestionID] {
        entries.map(\.questionID)
    }
}

/// 学習の入口。同じ教材プールを、入口ごとの選び方で出題する。
enum LearningSessionOrigin: Equatable, Sendable {
    case recommended
    case level(CertificationLevel)
    case review
    case scenario(ScenarioID)
    /// 実戦チェック。カテゴリの行動を実際に使えるかを確かめる小テスト。
    case practicalCheck(ScenarioID)

    /// 1セッションの問題数。実戦チェックだけ短くする。
    var sessionQuestionCount: Int {
        switch self {
        case .practicalCheck: PracticalCheckPolicy.current.questionCount
        default: LearningSessionPlanner.defaultQuestionCount
        }
    }

    var practicalCheckScenarioID: ScenarioID? {
        guard case let .practicalCheck(scenarioID) = self else { return nil }
        return scenarioID
    }
}

/// 出題優先度の係数。運用設定として持ち、コードへ埋め込まない。
struct SelectionWeights: Codable, Equatable, Sendable {
    static let current = SelectionWeights(
        version: "selection-2026-08-v1",
        dueForReview: 100,
        weakness: 60,
        unseen: 40,
        scenarioNeed: 30,
        mastered: -80,
        jitter: 20
    )

    let version: String
    let dueForReview: Double
    let weakness: Double
    let unseen: Double
    let scenarioNeed: Double
    let mastered: Double
    /// 同点の問題が毎回同じ順で出ないようにする幅。
    let jitter: Double
}

/// 教材プールから、入口に応じた出題順と選択肢順のセッションを組み立てる。
enum LearningSessionPlanner {
    static let defaultQuestionCount = 20

    static func makePlan(
        from pack: LearningContentPack,
        origin: LearningSessionOrigin = .recommended,
        mastery: [QuestionID: QuestionMastery] = [:],
        at date: Date = Date(),
        weights: SelectionWeights = .current,
        questionCount: Int = defaultQuestionCount,
        using generator: inout some RandomNumberGenerator
    ) -> LearningSessionPlan {
        let selected = selectQuestions(
            from: pack,
            origin: origin,
            mastery: mastery,
            at: date,
            weights: weights,
            questionCount: questionCount,
            using: &generator
        )

        let entries = selected.map { question in
            LearningSessionPlan.Entry(
                questionID: question.id,
                choiceIDs: question.choices.map(\.id).shuffled(using: &generator)
            )
        }

        return LearningSessionPlan(entries: entries)
    }

    private static func selectQuestions(
        from pack: LearningContentPack,
        origin: LearningSessionOrigin,
        mastery: [QuestionID: QuestionMastery],
        at date: Date,
        weights: SelectionWeights,
        questionCount: Int,
        using generator: inout some RandomNumberGenerator
    ) -> [LearningQuestion] {
        let preferred = candidates(in: pack, origin: origin, mastery: mastery, at: date)
        let ranked = rank(preferred, mastery: mastery, origin: origin, at: date, weights: weights, using: &generator)

        guard ranked.count < questionCount else {
            return Array(ranked.prefix(questionCount))
        }

        // 実戦チェックはそのカテゴリの力を測るため、他カテゴリの教材で補わない。
        if case .practicalCheck = origin {
            return ranked
        }

        // 入口ごとの候補が足りない場合も、同じ教材プールから補って20問を組む。
        let selectedIDs = Set(ranked.map(\.id))
        let remaining = pack.deliverableQuestions.filter { selectedIDs.contains($0.id) == false }
        let fill = rank(remaining, mastery: mastery, origin: origin, at: date, weights: weights, using: &generator)
        return Array((ranked + fill).prefix(questionCount))
    }

    private static func candidates(
        in pack: LearningContentPack,
        origin: LearningSessionOrigin,
        mastery: [QuestionID: QuestionMastery],
        at date: Date
    ) -> [LearningQuestion] {
        switch origin {
        case .recommended:
            pack.deliverableQuestions
        case let .level(level):
            pack.deliverableQuestions(at: level)
        case .review:
            pack.deliverableQuestions.filter { question in
                switch mastery[question.id]?.state(at: date) {
                case .dueForReview, .relearning, .learning: true
                default: false
                }
            }
        case let .scenario(scenarioID), let .practicalCheck(scenarioID):
            pack.deliverableQuestions.filter { $0.scenarioIDs.contains(scenarioID) }
        }
    }

    private static func rank(
        _ questions: [LearningQuestion],
        mastery: [QuestionID: QuestionMastery],
        origin: LearningSessionOrigin,
        at date: Date,
        weights: SelectionWeights,
        using generator: inout some RandomNumberGenerator
    ) -> [LearningQuestion] {
        questions
            .map { question in
                (
                    question,
                    priority(
                        for: question,
                        mastery: mastery[question.id],
                        origin: origin,
                        at: date,
                        weights: weights
                    ) + Double.random(in: 0...weights.jitter, using: &generator)
                )
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    /// 復習期限、弱点度、未出題補正、シナリオ必要度から優先度を出す。
    private static func priority(
        for question: LearningQuestion,
        mastery: QuestionMastery?,
        origin: LearningSessionOrigin,
        at date: Date,
        weights: SelectionWeights
    ) -> Double {
        guard let mastery else { return weights.unseen + scenarioBonus(question, origin: origin, weights: weights) }

        var score = 0.0
        switch mastery.state(at: date) {
        case .unseen:
            score += weights.unseen
        case .dueForReview, .relearning:
            score += weights.dueForReview
        case .learning:
            score += weights.weakness
        case .provisional:
            score += weights.weakness / 2
        case .mastered:
            score += weights.mastered
        }

        score += Double(mastery.incorrectStreak) * weights.weakness / 2
        return score + scenarioBonus(question, origin: origin, weights: weights)
    }

    private static func scenarioBonus(
        _ question: LearningQuestion,
        origin: LearningSessionOrigin,
        weights: SelectionWeights
    ) -> Double {
        switch origin {
        case let .scenario(scenarioID), let .practicalCheck(scenarioID):
            return question.scenarioIDs.contains(scenarioID) ? weights.scenarioNeed : 0
        default:
            return 0
        }
    }
}

enum LearningSessionPhase: Equatable, Sendable {
    case answering
    case midpoint
    case finalResult
}

struct LearningSessionState: Equatable, Sendable {
    static let checkpointQuestionCount = 10

    let contentVersion: String
    /// 出題順・選択肢順を適用済みの問題。画面に見えるのはこの並びである。
    let questions: [LearningQuestion]
    private(set) var phase: LearningSessionPhase = .answering
    private(set) var currentIndex = 0
    private(set) var selectedChoiceID: ChoiceID?
    private(set) var submittedChoiceID: ChoiceID?
    /// 回答順を保った回答イベント。1問につき最大1件だけ保持し、再送で重複を作らない。
    private(set) var answers: [AnsweredQuestion] = []
    private(set) var audioPlayCount = 0

    private let plan: LearningSessionPlan

    /// 教材の原稿順そのままのセッション。計画が教材と食い違わないため失敗しない。
    init(contentPack: LearningContentPack) {
        contentVersion = contentPack.version
        questions = contentPack.deliverableQuestions
        plan = LearningSessionPlan(
            entries: contentPack.deliverableQuestions.map { question in
                LearningSessionPlan.Entry(
                    questionID: question.id,
                    choiceIDs: question.choices.map(\.id)
                )
            }
        )
    }

    init(contentPack: LearningContentPack, plan: LearningSessionPlan) throws {
        contentVersion = contentPack.version
        self.plan = plan

        questions = try plan.entries.map { entry in
            guard let question = contentPack.question(with: entry.questionID) else {
                throw LearningSessionRestoreFailure.questionSetMismatch
            }
            guard let choiceIDs = entry.choiceIDs else {
                return question
            }
            guard let reordered = question.reordering(choiceIDs: choiceIDs) else {
                throw LearningSessionRestoreFailure.unknownAnswerReference
            }
            return reordered
        }
    }

    var currentQuestion: LearningQuestion? {
        guard questions.indices.contains(currentIndex) else { return nil }
        return questions[currentIndex]
    }

    var answeredCount: Int {
        answers.count
    }

    var correctCount: Int {
        answers.count(where: { $0.isCorrect })
    }

    var accuracy: Double {
        guard answeredCount > 0 else { return 0 }
        return Double(correctCount) / Double(answeredCount)
    }

    var isSubmittedAnswerCorrect: Bool {
        guard let question = currentQuestion, let submittedChoiceID else { return false }
        return submittedChoiceID == question.correctChoiceID
    }

    /// 中間結果までの区間で正解した数。総合結果でも中間区間の実績を再現できるようにする。
    var correctCountUpToCheckpoint: Int {
        answers.prefix(Self.checkpointQuestionCount).count(where: { $0.isCorrect })
    }

    func answeredChoiceID(for questionID: QuestionID) -> ChoiceID? {
        answers.first { $0.questionID == questionID }?.choiceID
    }

    mutating func select(_ choiceID: ChoiceID) {
        guard phase == .answering,
              submittedChoiceID == nil,
              currentQuestion?.choices.contains(where: { $0.id == choiceID }) == true else {
            return
        }
        selectedChoiceID = choiceID
    }

    /// 回答を確定する。確定済み・未選択・同一問題の二重回答は無視し、`false` を返す。
    @discardableResult
    mutating func submit(at date: Date) -> Bool {
        guard phase == .answering,
              submittedChoiceID == nil,
              let question = currentQuestion,
              let selectedChoiceID,
              answeredChoiceID(for: question.id) == nil else {
            return false
        }

        submittedChoiceID = selectedChoiceID
        answers.append(
            AnsweredQuestion(
                questionID: question.id,
                choiceID: selectedChoiceID,
                isCorrect: selectedChoiceID == question.correctChoiceID,
                answeredAt: date,
                audioPlayCount: audioPlayCount
            )
        )
        return true
    }

    mutating func registerAudioPlayback() {
        guard phase == .answering else { return }
        audioPlayCount += 1
    }

    mutating func advance() {
        guard phase == .answering, submittedChoiceID != nil else { return }

        if answeredCount >= questions.count {
            phase = .finalResult
            return
        }

        currentIndex = answeredCount
        selectedChoiceID = nil
        submittedChoiceID = nil
        audioPlayCount = 0

        if answeredCount == Self.checkpointQuestionCount {
            phase = .midpoint
        }
    }

    mutating func continueAfterMidpoint() {
        guard phase == .midpoint else { return }
        phase = .answering
    }

    mutating func restart() {
        phase = .answering
        currentIndex = 0
        selectedChoiceID = nil
        submittedChoiceID = nil
        answers = []
        audioPlayCount = 0
    }
}

// MARK: - 保存と復帰

extension LearningSessionState {
    func snapshot(sessionID: UUID, startedAt: Date, updatedAt: Date) -> LearningSessionSnapshot {
        LearningSessionSnapshot(
            sessionID: sessionID,
            contentVersion: contentVersion,
            plan: plan,
            answers: answers,
            phase: LearningSessionSnapshot.Phase(phase),
            startedAt: startedAt,
            updatedAt: updatedAt
        )
    }

    /// 保存データを現行教材へ復帰する。
    ///
    /// 未確定の選択は復帰させない。回答直後に保存された確定回答だけを引き継ぐことで、
    /// 途中離脱後の再開が同じ問題を二重に回答しない状態から始まるようにする。
    static func restored(
        from snapshot: LearningSessionSnapshot,
        contentPack: LearningContentPack
    ) throws -> LearningSessionState {
        guard LearningSessionSnapshot.supportedSchemaVersions.contains(snapshot.schemaVersion) else {
            throw LearningSessionRestoreFailure.unsupportedSchemaVersion(snapshot.schemaVersion)
        }
        guard snapshot.contentVersion == contentPack.version else {
            throw LearningSessionRestoreFailure.contentVersionMismatch(
                expected: contentPack.version,
                found: snapshot.contentVersion
            )
        }

        var state = try LearningSessionState(contentPack: contentPack, plan: snapshot.plan)

        guard snapshot.answers.count <= state.questions.count else {
            throw LearningSessionRestoreFailure.questionSetMismatch
        }

        var seenQuestionIDs: Set<QuestionID> = []
        for answer in snapshot.answers {
            guard let question = state.questions.first(where: { $0.id == answer.questionID }),
                  question.choices.contains(where: { $0.id == answer.choiceID }) else {
                throw LearningSessionRestoreFailure.unknownAnswerReference
            }
            guard seenQuestionIDs.insert(answer.questionID).inserted else {
                throw LearningSessionRestoreFailure.duplicatedAnswer(answer.questionID)
            }
        }

        state.answers = snapshot.answers
        state.phase = snapshot.phase.domainPhase
        state.currentIndex = min(snapshot.answers.count, max(state.questions.count - 1, 0))
        return state
    }
}

private extension LearningSessionSnapshot.Phase {
    init(_ phase: LearningSessionPhase) {
        switch phase {
        case .answering: self = .answering
        case .midpoint: self = .midpoint
        case .finalResult: self = .finalResult
        }
    }

    var domainPhase: LearningSessionPhase {
        switch self {
        case .answering: .answering
        case .midpoint: .midpoint
        case .finalResult: .finalResult
        }
    }
}

// MARK: - プレビューとテスト用

extension LearningSessionState {
    /// 決定的な並びのセッション。プレビュー・UIテストで使う。
    static var demo: LearningSessionState {
        var generator = SeededRandomNumberGenerator(seed: 20_260_821)
        let pack = DemoLearningContent.pack
        let plan = LearningSessionPlanner.makePlan(from: pack, using: &generator)
        return (try? LearningSessionState(contentPack: pack, plan: plan))
            ?? LearningSessionState(contentPack: pack)
    }

    static func demo(answeringCorrectly count: Int, at date: Date = Date(timeIntervalSince1970: 0)) -> LearningSessionState {
        var session = demo
        for _ in 0..<count {
            guard let question = session.currentQuestion else { break }
            session.select(question.correctChoiceID)
            session.submit(at: date)
            session.advance()
            if session.phase == .midpoint {
                session.continueAfterMidpoint()
            }
        }
        return session
    }

    /// 誤答を確定した直後の状態。解説ポップアップの画面確認に使う。
    static var demoAnsweredIncorrectly: LearningSessionState {
        var session = demo
        guard let question = session.currentQuestion,
              let wrongChoice = question.choices.first(where: { $0.id != question.correctChoiceID }) else {
            return session
        }
        session.select(wrongChoice.id)
        session.submit(at: Date(timeIntervalSince1970: 0))
        return session
    }

    static var demoMidpoint: LearningSessionState {
        var session = demo(answeringCorrectly: checkpointQuestionCount)
        session.phase = .midpoint
        return session
    }

    static var demoFinalResult: LearningSessionState {
        demo(answeringCorrectly: LearningSessionPlanner.defaultQuestionCount)
    }
}
