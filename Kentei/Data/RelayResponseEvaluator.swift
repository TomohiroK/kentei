import Foundation

/// 採点中継サーバー経由で採点する実装。
///
/// APIキーは端末に置かず、サーバーが保持する。送るのはテキストだけで、
/// 録音は送信前に自前で弾く。
struct RelayResponseEvaluator: ResponseEvaluating {
    /// 既定の送信先。秘密ではないためコードに持つ。
    static let defaultEndpoint = URL(string: "https://kentei-assessment.vercel.app/api/assess")!

    let endpoint: URL
    let credentialStore: any AssessmentCredentialStoring
    let session: URLSession
    let gate: SubmissionGate

    init(
        endpoint: URL = RelayResponseEvaluator.defaultEndpoint,
        credentialStore: any AssessmentCredentialStoring,
        session: URLSession = .shared,
        gate: SubmissionGate = SubmissionGate()
    ) {
        self.endpoint = endpoint
        self.credentialStore = credentialStore
        self.session = session
        self.gate = gate
    }

    func evaluate(_ submission: AssessmentSubmission, rubric: Rubric) async throws -> AssessmentResult {
        // 送る前に弾けるものは弾く。無駄な送信と課金を避ける。
        if let failure = gate.validate(submission, rubric: rubric) {
            throw failure
        }
        guard let token = credentialStore.loadToken() else {
            throw AssessmentError.providerNotConfigured
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "x-kentei-client")
        request.timeoutInterval = 60
        // 基準の版は採点に使う基準そのものから取る。取り違えると版ずれで弾かれる。
        request.httpBody = try JSONEncoder.relay.encode(
            RelayRequestBody(submission: submission, rubricVersion: rubric.version)
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // 通信できない場合は再評価キューへ戻す。
            throw AssessmentError.temporaryFailure
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AssessmentError.temporaryFailure
        }
        guard httpResponse.statusCode == 200 else {
            throw Self.error(for: httpResponse.statusCode, data: data)
        }

        let body: RelayResponseBody
        do {
            body = try JSONDecoder.relay.decode(RelayResponseBody.self, from: data)
        } catch {
            throw AssessmentError.temporaryFailure
        }

        return body.result(for: submission)
    }

    /// サーバーの応答を、再試行できるものとできないものへ分ける。
    static func error(for statusCode: Int, data: Data) -> AssessmentError {
        let code = (try? JSONDecoder().decode(RelayErrorBody.self, from: data))?.code

        switch code {
        case "recording_not_available": return .recordingNotAvailable
        case "rubric_version_mismatch", "task_type_mismatch", "rubric_not_found": return .rubricMismatch
        case "empty_text", "text_too_long", "invalid_submission": return .invalidSubmission
        default: break
        }

        switch statusCode {
        case 401, 403, 503: return .providerNotConfigured
        case 400, 409, 413: return .invalidSubmission
        default: return .temporaryFailure
        }
    }
}

// MARK: - 通信の形

private struct RelayRequestBody: Encodable {
    let submissionId: String
    let taskType: String
    let level: String
    let rubricId: String
    let rubricVersion: String
    let prompt: String?
    let text: String?

    init(submission: AssessmentSubmission, rubricVersion: String) {
        submissionId = submission.id.rawValue
        taskType = submission.taskType.rawValue
        level = submission.level.rawValue
        rubricId = submission.rubricID.rawValue
        self.rubricVersion = rubricVersion
        prompt = submission.prompt
        text = submission.text
    }
}

private struct RelayErrorBody: Decodable {
    let code: String
}

private struct RelayResponseBody: Decodable {
    struct Score: Decodable {
        let criterionId: String
        let score: Int
        let comment: String
    }

    let scores: [Score]
    let overallComment: String
    let normalizedScore: Double
    let isPassed: Bool
    let modelVersion: String
    let rubricVersion: String
    let evaluatedAt: Date

    func result(for submission: AssessmentSubmission) -> AssessmentResult {
        AssessmentResult(
            submissionID: submission.id,
            scores: scores.map {
                CriterionScore(criterionID: $0.criterionId, score: $0.score, commentKey: $0.comment)
            },
            overallComment: overallComment,
            normalizedScore: normalizedScore,
            isPassed: isPassed,
            modelVersion: modelVersion,
            rubricVersion: rubricVersion,
            evaluatedAt: evaluatedAt,
            humanReview: .notRequested
        )
    }
}

private extension JSONEncoder {
    static var relay: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var relay: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
