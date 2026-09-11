import Foundation

/// 基準回答。採点の揺れを検出するための、期待値付きの提出物。
struct GoldenAnswer: Codable, Equatable, Sendable {
    let id: String
    let submission: AssessmentSubmission
    /// 期待する正規化スコアの範囲。モデル更新でこの範囲を外れたら回帰とみなす。
    let expectedMinimumScore: Double
    let expectedMaximumScore: Double
    let expectedPassed: Bool

    func matches(_ result: AssessmentResult) -> Bool {
        result.normalizedScore >= expectedMinimumScore
            && result.normalizedScore <= expectedMaximumScore
            && result.isPassed == expectedPassed
    }
}

/// 基準回答一式。ルーブリックの版と対応づける。
struct GoldenAnswerSuite: Codable, Equatable, Sendable {
    let version: String
    let rubricID: RubricID
    let rubricVersion: String
    let answers: [GoldenAnswer]
}

struct RegressionOutcome: Equatable, Sendable {
    let goldenID: String
    let actualScore: Double?
    let actualPassed: Bool?
    let failure: AssessmentError?
    let isWithinExpectation: Bool
}

/// 回帰試験の結果。モデル版・ルーブリック版とともに残す。
struct RegressionReport: Equatable, Sendable {
    let suiteVersion: String
    let rubricVersion: String
    let modelVersion: String?
    let outcomes: [RegressionOutcome]

    var failedOutcomes: [RegressionOutcome] {
        outcomes.filter { $0.isWithinExpectation == false }
    }

    /// 全ての基準回答が期待範囲に収まったか。1件でも外れたらモデルを切り替えない。
    var isAcceptable: Bool {
        outcomes.isEmpty == false && failedOutcomes.isEmpty
    }
}

/// モデルやルーブリックを更新するときに走らせる回帰試験。
///
/// 基準回答の採点結果が期待範囲を外れた場合、新しいモデルへ切り替えない。
struct GoldenAnswerRegressionRunner: Sendable {
    let gate: SubmissionGate

    init(gate: SubmissionGate = SubmissionGate()) {
        self.gate = gate
    }

    func run(
        _ suite: GoldenAnswerSuite,
        rubric: Rubric,
        using evaluator: any ResponseEvaluating
    ) async -> RegressionReport {
        var outcomes: [RegressionOutcome] = []
        var modelVersion: String?

        for golden in suite.answers {
            if let gateFailure = gate.validate(golden.submission, rubric: rubric) {
                outcomes.append(
                    RegressionOutcome(
                        goldenID: golden.id,
                        actualScore: nil,
                        actualPassed: nil,
                        failure: gateFailure,
                        isWithinExpectation: false
                    )
                )
                continue
            }

            do {
                let result = try await evaluator.evaluate(golden.submission, rubric: rubric)
                modelVersion = result.modelVersion
                outcomes.append(
                    RegressionOutcome(
                        goldenID: golden.id,
                        actualScore: result.normalizedScore,
                        actualPassed: result.isPassed,
                        failure: nil,
                        isWithinExpectation: golden.matches(result)
                    )
                )
            } catch {
                outcomes.append(
                    RegressionOutcome(
                        goldenID: golden.id,
                        actualScore: nil,
                        actualPassed: nil,
                        failure: error as? AssessmentError ?? .temporaryFailure,
                        isWithinExpectation: false
                    )
                )
            }
        }

        return RegressionReport(
            suiteVersion: suite.version,
            rubricVersion: suite.rubricVersion,
            modelVersion: modelVersion,
            outcomes: outcomes
        )
    }
}
