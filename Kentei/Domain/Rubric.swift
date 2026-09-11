import Foundation

/// AI評価の対象となる課題の種類。
///
/// B級以上で扱う。発話課題は登録済みの専用基準と確認済みテキストだけを受け付ける。
enum AssessmentTaskType: String, Codable, CaseIterable, Sendable {
    case writing
    case summarization
    case interview
    case rolePlay = "role_play"
    case speaking

    /// 録音（音声入力）を必要とするか。
    var requiresRecording: Bool {
        switch self {
        case .writing, .summarization: false
        case .interview, .rolePlay, .speaking: true
        }
    }
}

struct RubricID: Hashable, Codable, Sendable, RawRepresentable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// 採点観点。重みの合計は1.0にする。
struct RubricCriterion: Codable, Equatable, Sendable {
    let id: String
    /// 表示名の文言キー。観点名は文言カタログで管理する。
    let titleKey: String
    let weight: Double
    let maxScore: Int
}

/// 採点基準。
///
/// 版を持ち、採点結果に必ず記録する。基準を変えたら版を上げ、
/// 基準回答の回帰試験を通してから使う。
struct Rubric: Codable, Equatable, Sendable {
    let id: RubricID
    let version: String
    let level: CertificationLevel
    let taskType: AssessmentTaskType
    let criteria: [RubricCriterion]
    /// 合格に必要な正規化スコア（0.0〜1.0）。
    let passingScore: Double

    /// 観点ごとの素点から、0.0〜1.0の正規化スコアを出す。
    func normalizedScore(from scores: [String: Int]) -> Double {
        criteria.reduce(0.0) { total, criterion in
            guard criterion.maxScore > 0, let score = scores[criterion.id] else { return total }
            let clamped = min(max(score, 0), criterion.maxScore)
            return total + Double(clamped) / Double(criterion.maxScore) * criterion.weight
        }
    }

    func isPassing(_ normalizedScore: Double) -> Bool {
        normalizedScore >= passingScore
    }
}

/// ルーブリックの不備。基準として使う前に拒否する。
enum RubricIssue: Equatable, Sendable {
    case noCriteria(RubricID)
    case weightsDoNotSumToOne(RubricID, Double)
    case nonPositiveMaxScore(RubricID, criterionID: String)
    case duplicatedCriterionID(RubricID, criterionID: String)
    case invalidPassingScore(RubricID, Double)
    case recordingNotAvailable(RubricID, AssessmentTaskType)
}

struct RubricValidator: Sendable {
    /// 重み合計の許容誤差。小数の丸めを吸収する。
    private let weightTolerance = 0.0001

    func validate(_ rubric: Rubric) -> [RubricIssue] {
        var issues: [RubricIssue] = []

        if rubric.criteria.isEmpty {
            issues.append(.noCriteria(rubric.id))
        }

        let weightSum = rubric.criteria.reduce(0.0) { $0 + $1.weight }
        if rubric.criteria.isEmpty == false, abs(weightSum - 1.0) > weightTolerance {
            issues.append(.weightsDoNotSumToOne(rubric.id, weightSum))
        }

        var seenIDs: Set<String> = []
        for criterion in rubric.criteria {
            if criterion.maxScore <= 0 {
                issues.append(.nonPositiveMaxScore(rubric.id, criterionID: criterion.id))
            }
            if seenIDs.insert(criterion.id).inserted == false {
                issues.append(.duplicatedCriterionID(rubric.id, criterionID: criterion.id))
            }
        }

        if rubric.passingScore <= 0 || rubric.passingScore > 1 {
            issues.append(.invalidPassingScore(rubric.id, rubric.passingScore))
        }

        // Only registered transcript rubrics are accepted; audio never reaches scoring.
        if rubric.taskType.requiresRecording && !OralTask.all.contains(where: { $0.rubric == rubric }) {
            issues.append(.recordingNotAvailable(rubric.id, rubric.taskType))
        }

        return issues
    }
}
