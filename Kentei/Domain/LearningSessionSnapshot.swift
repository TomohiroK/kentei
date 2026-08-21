import Foundation

/// 学習セッションの保存形式。
///
/// 保存形式・キー・列挙値は互換性契約である。フィールドを変更するときは
/// `currentSchemaVersion` を上げ、旧バージョンの読込テストと移行を同じ変更で追加する。
struct LearningSessionSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    /// 保存形式のバージョン。読込時に対応可否を判定する。
    let schemaVersion: Int
    let sessionID: UUID
    /// 教材パックの版。版が変わった保存データは復帰させず破棄する。
    let contentVersion: String
    /// 出題順の契約。復帰時に現行教材と一致することを検証する。
    let questionIDs: [QuestionID]
    let answers: [AnsweredQuestion]
    let phase: Phase
    let startedAt: Date
    let updatedAt: Date

    enum Phase: String, Codable, Sendable {
        case answering
        case midpoint
        case finalResult
    }

    init(
        schemaVersion: Int = LearningSessionSnapshot.currentSchemaVersion,
        sessionID: UUID,
        contentVersion: String,
        questionIDs: [QuestionID],
        answers: [AnsweredQuestion],
        phase: Phase,
        startedAt: Date,
        updatedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.contentVersion = contentVersion
        self.questionIDs = questionIDs
        self.answers = answers
        self.phase = phase
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }
}

/// 1問分の回答イベント。同じ `questionID` を二重に持たないことで再送を冪等にする。
struct AnsweredQuestion: Codable, Equatable, Sendable {
    let questionID: QuestionID
    let choiceID: ChoiceID
    let isCorrect: Bool
    let answeredAt: Date
    let audioPlayCount: Int
}

/// 保存データを現行教材へ復帰できない理由。復帰失敗は破棄理由を必ず区別する。
enum LearningSessionRestoreFailure: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case contentVersionMismatch(expected: String, found: String)
    case questionSetMismatch
    case unknownAnswerReference
    case duplicatedAnswer(QuestionID)
}
