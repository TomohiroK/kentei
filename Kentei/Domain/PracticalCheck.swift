import Foundation

/// 実戦チェックの合格条件。閾値は教材検証で調整できるよう設定値として持つ。
struct PracticalCheckPolicy: Codable, Equatable, Sendable {
    static let current = PracticalCheckPolicy(
        version: "practical-2026-08-v1",
        questionCount: 5,
        requiredAccuracy: 0.8
    )

    let version: String
    let questionCount: Int
    /// 合格に必要な正答率。
    let requiredAccuracy: Double
}

/// 実戦チェックの結果。合否と根拠（正答数・使用した設定版）を残す。
struct PracticalCheckResult: Codable, Equatable, Sendable {
    let scenarioID: ScenarioID
    let correctCount: Int
    let questionCount: Int
    let evaluatedAt: Date
    /// 合格した時刻。不合格なら nil。
    let passedAt: Date?
    let policyVersion: String

    var accuracy: Double {
        guard questionCount > 0 else { return 0 }
        return Double(correctCount) / Double(questionCount)
    }

    var isPassed: Bool {
        passedAt != nil
    }
}

/// 実戦チェックの採点。副作用を持たず、同じ入力からは同じ結果になる。
struct PracticalCheckEvaluator: Sendable {
    let policy: PracticalCheckPolicy

    init(policy: PracticalCheckPolicy = .current) {
        self.policy = policy
    }

    func evaluate(
        scenarioID: ScenarioID,
        answers: [AnsweredQuestion],
        at date: Date
    ) -> PracticalCheckResult {
        let correctCount = answers.count(where: \.isCorrect)
        let accuracy = answers.isEmpty ? 0 : Double(correctCount) / Double(answers.count)

        return PracticalCheckResult(
            scenarioID: scenarioID,
            correctCount: correctCount,
            questionCount: answers.count,
            evaluatedAt: date,
            passedAt: accuracy >= policy.requiredAccuracy ? date : nil,
            policyVersion: policy.version
        )
    }
}
