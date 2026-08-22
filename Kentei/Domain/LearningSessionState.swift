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
}

/// 出題音声の1発話。会話問題では話者を分けて複数持つ。
struct ScriptedUtterance: Equatable, Sendable {
    let speakerIndex: Int
    let text: String
}

struct LearningQuestion: Identifiable, Equatable, Sendable {
    let id: QuestionID
    let utterances: [ScriptedUtterance]
    /// 原稿順の選択肢。学習者に見える順序はセッションごとに決まる。
    let choices: [LearningChoice]
    let correctChoiceID: ChoiceID
    let explanation: String
    let scenarioName: String

    /// 回答後に表示する本文。会話問題は話者ごとに行を分ける。
    var transcript: String {
        utterances.map(\.text).joined(separator: "\n")
    }

    var isConversation: Bool {
        utterances.count > 1
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
            utterances: utterances,
            choices: reordered,
            correctChoiceID: correctChoiceID,
            explanation: explanation,
            scenarioName: scenarioName
        )
    }
}

/// バージョン付きの教材パック。版が変わった保存データは復帰対象にしない。
struct LearningContentPack: Equatable, Sendable {
    let version: String
    let questions: [LearningQuestion]

    func question(with id: QuestionID) -> LearningQuestion? {
        questions.first { $0.id == id }
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

/// 教材プールから、毎回異なる出題順と選択肢順のセッションを組み立てる。
enum LearningSessionPlanner {
    static let defaultQuestionCount = 20

    static func makePlan(
        from pack: LearningContentPack,
        questionCount: Int = defaultQuestionCount,
        using generator: inout some RandomNumberGenerator
    ) -> LearningSessionPlan {
        let selected = pack.questions.shuffled(using: &generator).prefix(questionCount)

        let entries = selected.map { question in
            LearningSessionPlan.Entry(
                questionID: question.id,
                choiceIDs: question.choices.map(\.id).shuffled(using: &generator)
            )
        }

        return LearningSessionPlan(entries: Array(entries))
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
        questions = contentPack.questions
        plan = LearningSessionPlan(
            entries: contentPack.questions.map { question in
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
