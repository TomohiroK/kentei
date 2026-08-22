import Foundation

/// 学習セッションの保存形式。
///
/// 保存形式・キー・列挙値は互換性契約である。フィールドを変更するときは
/// `currentSchemaVersion` を上げ、旧バージョンの読込テストと移行を同じ変更で追加する。
///
/// - v1: 出題は教材の並び順で固定。`questionIDs` のみを保持した。
/// - v2: 出題順と選択肢順をセッションごとに決めるため `plan` を保持する。
struct LearningSessionSnapshot: Equatable, Sendable {
    static let currentSchemaVersion = 2
    static let supportedSchemaVersions: Set<Int> = [1, 2]

    /// 保存形式のバージョン。読込時に対応可否を判定する。
    let schemaVersion: Int
    let sessionID: UUID
    /// 教材パックの版。版が変わった保存データは復帰させず破棄する。
    let contentVersion: String
    /// 出題順と選択肢順の契約。復帰時に現行教材と突き合わせる。
    let plan: LearningSessionPlan
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
        plan: LearningSessionPlan,
        answers: [AnsweredQuestion],
        phase: Phase,
        startedAt: Date,
        updatedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.contentVersion = contentVersion
        self.plan = plan
        self.answers = answers
        self.phase = phase
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }
}

extension LearningSessionSnapshot: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case sessionID
        case contentVersion
        case plan
        case questionIDs
        case answers
        case phase
        case startedAt
        case updatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        sessionID = try container.decode(UUID.self, forKey: .sessionID)
        contentVersion = try container.decode(String.self, forKey: .contentVersion)
        answers = try container.decode([AnsweredQuestion].self, forKey: .answers)
        phase = try container.decode(Phase.self, forKey: .phase)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)

        if let plan = try container.decodeIfPresent(LearningSessionPlan.self, forKey: .plan) {
            self.plan = plan
        } else {
            // v1からの移行。選択肢順は保存されていないため、教材の原稿順で復帰する。
            let questionIDs = try container.decode([QuestionID].self, forKey: .questionIDs)
            plan = LearningSessionPlan(
                entries: questionIDs.map { LearningSessionPlan.Entry(questionID: $0, choiceIDs: nil) }
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(contentVersion, forKey: .contentVersion)
        try container.encode(plan, forKey: .plan)
        try container.encode(answers, forKey: .answers)
        try container.encode(phase, forKey: .phase)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(updatedAt, forKey: .updatedAt)
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
