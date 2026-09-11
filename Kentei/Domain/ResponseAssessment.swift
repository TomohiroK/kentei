import Foundation

struct AssessmentID: Hashable, Codable, Sendable, RawRepresentable {
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

/// 採点に出す提出物。
///
/// `id` は冪等キーであり、同じ提出を二度採点させないために使う。
/// 音声は端末内に限定し、提出は確認済みテキストのみ（`audioReference` は常に nil）。
struct AssessmentSubmission: Codable, Equatable, Sendable {
    let id: AssessmentID
    let taskType: AssessmentTaskType
    let level: CertificationLevel
    let rubricID: RubricID
    /// 学習者が読んだ設問。
    ///
    /// 「課題への対応」の観点は設問がないと採点できない。資料を示す課題では
    /// 資料そのものが設問に含まれるため、本文と別に送る。
    let prompt: String?
    let text: String?
    /// 旧保存形式との互換用。音声の外部送信を許可しないため常に nil。
    let audioReference: String?
    let submittedAt: Date

    init(
        id: AssessmentID,
        taskType: AssessmentTaskType,
        level: CertificationLevel,
        rubricID: RubricID,
        prompt: String? = nil,
        text: String?,
        audioReference: String? = nil,
        submittedAt: Date
    ) {
        self.id = id
        self.taskType = taskType
        self.level = level
        self.rubricID = rubricID
        self.prompt = prompt
        self.text = text
        self.audioReference = audioReference
        self.submittedAt = submittedAt
    }
}

/// 観点ごとの採点。
struct CriterionScore: Codable, Equatable, Sendable {
    let criterionID: String
    let score: Int
    /// 学習者へ返す短い指摘。無い場合もある。
    let commentKey: String?
}

/// 人間レビューの状態。AIの採点をそのまま最終結果にしない経路を残す。
enum HumanReviewState: String, Codable, Equatable, Sendable {
    case notRequested
    case requested
    case confirmed
    case overridden
}

/// 採点結果。
///
/// 使用したモデル版とルーブリック版を必ず持つ。係数やモデルを変えても
/// 過去の採点根拠を説明できるようにする。
struct AssessmentResult: Codable, Equatable, Sendable {
    let submissionID: AssessmentID
    let scores: [CriterionScore]
    /// 全体の講評。観点別の短評とは別に、次に何をすればよいかを伝える。
    let overallComment: String?
    let normalizedScore: Double
    let isPassed: Bool
    let modelVersion: String
    let rubricVersion: String
    let evaluatedAt: Date
    let humanReview: HumanReviewState

    func withHumanReview(_ state: HumanReviewState) -> AssessmentResult {
        AssessmentResult(
            submissionID: submissionID,
            scores: scores,
            overallComment: overallComment,
            normalizedScore: normalizedScore,
            isPassed: isPassed,
            modelVersion: modelVersion,
            rubricVersion: rubricVersion,
            evaluatedAt: evaluatedAt,
            humanReview: state
        )
    }

    /// 人間が確定または上書きした結果か。学習者へ最終結果として出せるかの判断に使う。
    var isFinalized: Bool {
        humanReview == .confirmed || humanReview == .overridden
    }
}

enum AssessmentError: Error, Equatable, Sendable {
    /// 評価プロバイダーが未確定。決定するまで採点しない。
    case providerNotConfigured
    /// 音声参照を含む提出、または専用基準のない発話課題。
    case recordingNotAvailable
    /// 一時的な失敗。再評価キューへ戻す。
    case temporaryFailure
    /// 提出内容が空など、再試行しても通らない。
    case invalidSubmission
    case rubricMismatch
}

/// AI評価の呼び出し口。
///
/// 音声認識・AIモデルの提供者は決定ゲートのため、ここではプロトコルだけを定義し、
/// プロバイダーのSDKをクライアントへ追加しない。
protocol ResponseEvaluating: Sendable {
    func evaluate(_ submission: AssessmentSubmission, rubric: Rubric) async throws -> AssessmentResult
}

/// プロバイダーが決まるまでの既定実装。採点せず、提出を保持させる。
struct UnconfiguredResponseEvaluator: ResponseEvaluating {
    func evaluate(_ submission: AssessmentSubmission, rubric: Rubric) async throws -> AssessmentResult {
        // 音声参照と未登録の発話基準は、プロバイダー未設定より先に拒否する。
        if submission.audioReference != nil || (submission.taskType.requiresRecording && !OralTask.all.contains(where: { $0.rubric == rubric })) {
            throw AssessmentError.recordingNotAvailable
        }
        throw AssessmentError.providerNotConfigured
    }
}

/// 提出の受け付け可否を、外部サービスに問い合わせる前に判断する。
struct SubmissionGate: Sendable {
    func validate(_ submission: AssessmentSubmission, rubric: Rubric) -> AssessmentError? {
        if submission.audioReference != nil || (submission.taskType.requiresRecording && !OralTask.all.contains(where: { $0.rubric == rubric })) {
            return .recordingNotAvailable
        }
        if submission.rubricID != rubric.id || submission.taskType != rubric.taskType || submission.level != rubric.level {
            return .rubricMismatch
        }
        if (submission.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .invalidSubmission
        }
        return nil
    }
}
