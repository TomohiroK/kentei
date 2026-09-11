import XCTest
@testable import Kentei

final class RubricTests: XCTestCase {
    private let rubric = DemoAssessment.writingRubric
    private let validator = RubricValidator()

    // MARK: - 採点計算

    func testFullMarksGiveTheHighestScore() {
        let scores = Dictionary(uniqueKeysWithValues: rubric.criteria.map { ($0.id, $0.maxScore) })

        let normalized = rubric.normalizedScore(from: scores)

        XCTAssertEqual(normalized, 1.0, accuracy: 0.0001)
        XCTAssertTrue(rubric.isPassing(normalized))
    }

    func testWeightsChangeTheContributionOfEachCriterion() throws {
        let taskOnly = rubric.normalizedScore(from: ["task": 4])
        let coherenceOnly = rubric.normalizedScore(from: ["coherence": 4])

        XCTAssertEqual(taskOnly, 0.3, accuracy: 0.0001, "重み0.3の観点は満点で0.3を占める")
        XCTAssertEqual(coherenceOnly, 0.2, accuracy: 0.0001)
        XCTAssertGreaterThan(taskOnly, coherenceOnly)
    }

    func testScoresOutsideTheRangeAreClamped() {
        let normalized = rubric.normalizedScore(from: ["task": 99, "grammar": -5])

        XCTAssertEqual(normalized, 0.3, accuracy: 0.0001, "上限超過は満点、負値は0として扱う")
    }

    func testPassingUsesTheConfiguredThreshold() {
        XCTAssertFalse(rubric.isPassing(0.59))
        XCTAssertTrue(rubric.isPassing(0.6))
    }

    // MARK: - 基準の検証

    func testShippedRubricsAreValid() {
        for rubric in [DemoAssessment.writingRubric, DemoAssessment.writingRubricA] {
            XCTAssertTrue(
                validator.validate(rubric).isEmpty,
                "\(rubric.id.rawValue): 基準が使える状態にない"
            )
        }
    }

    /// 観点IDが重複していると、素点の対応付けが壊れる。
    func testRubricCriteriaHaveUniqueIdentifiers() {
        for rubric in [DemoAssessment.writingRubric, DemoAssessment.writingRubricA] {
            let identifiers = rubric.criteria.map(\.id)
            XCTAssertEqual(
                Set(identifiers).count,
                identifiers.count,
                "\(rubric.id.rawValue): 観点IDが重複している"
            )
        }
    }

    func testWeightsMustSumToOne() {
        let broken = Rubric(
            id: RubricID(rawValue: "broken"),
            version: "v1",
            level: .b,
            taskType: .writing,
            criteria: [RubricCriterion(id: "a", titleKey: "a", weight: 0.4, maxScore: 4)],
            passingScore: 0.6
        )

        let issues = validator.validate(broken)

        XCTAssertTrue(issues.contains { if case .weightsDoNotSumToOne = $0 { true } else { false } })
    }

    func testRecordingTasksAreRejectedUntilThePolicyIsDecided() {
        let interview = Rubric(
            id: RubricID(rawValue: "rubric-interview"),
            version: "v1",
            level: .b,
            taskType: .interview,
            criteria: [RubricCriterion(id: "a", titleKey: "a", weight: 1.0, maxScore: 4)],
            passingScore: 0.6
        )

        let issues = validator.validate(interview)

        XCTAssertTrue(
            issues.contains { if case .recordingNotAvailable = $0 { true } else { false } },
            "録音データ方針が決まるまで、録音を伴う課題は基準として使わない"
        )
    }
}

final class AssessmentQueueTests: XCTestCase {
    private let rubric = DemoAssessment.writingRubric
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - 受け付け

    func testRecordingSubmissionsAreNotAccepted() {
        let gate = SubmissionGate()
        let submission = makeSubmission(id: "with-audio", audioReference: "file://recording.m4a")

        XCTAssertEqual(gate.validate(submission, rubric: rubric), .recordingNotAvailable)
    }

    func testEmptyTextIsRejected() {
        let gate = SubmissionGate()
        let submission = makeSubmission(id: "empty", text: "   ")

        XCTAssertEqual(gate.validate(submission, rubric: rubric), .invalidSubmission)
    }

    func testUnconfiguredProviderReportsItself() async {
        let evaluator = UnconfiguredResponseEvaluator()

        do {
            _ = try await evaluator.evaluate(makeSubmission(id: "text"), rubric: rubric)
            XCTFail("プロバイダー未確定では採点しない")
        } catch let error as AssessmentError {
            XCTAssertEqual(error, .providerNotConfigured)
        } catch {
            XCTFail("想定外の失敗: \(error)")
        }
    }

    func testRecordingIsRefusedBeforeTheProviderIsEvenConsidered() async {
        let evaluator = UnconfiguredResponseEvaluator()
        let submission = makeSubmission(id: "interview", taskType: .interview)

        do {
            _ = try await evaluator.evaluate(submission, rubric: rubric)
            XCTFail("録音は受け付けない")
        } catch let error as AssessmentError {
            XCTAssertEqual(error, .recordingNotAvailable)
        } catch {
            XCTFail("想定外の失敗: \(error)")
        }
    }

    // MARK: - 再評価キュー

    func testSubmissionsAreQueuedOnlyOnce() async {
        let queue = AssessmentQueue(store: InMemoryAssessmentQueueStore())

        await queue.enqueue(makeSubmission(id: "one"))
        await queue.enqueue(makeSubmission(id: "one"))

        let count = await queue.pendingCount
        XCTAssertEqual(count, 1, "同じ提出を二度採点させない")
    }

    func testTemporaryFailureKeepsTheSubmissionForLater() async {
        let queue = AssessmentQueue(store: InMemoryAssessmentQueueStore())
        await queue.enqueue(makeSubmission(id: "retry"))

        let result = await queue.process(
            using: FakeResponseEvaluator(failure: .temporaryFailure),
            rubric: rubric
        )

        XCTAssertFalse(result.didEvaluateAnything)
        XCTAssertEqual(result.remainingCount, 1, "一時的な失敗は再評価キューに残す")
        XCTAssertEqual(result.failure, .temporaryFailure)
    }

    func testUnconfiguredProviderKeepsSubmissionsQueued() async {
        let queue = AssessmentQueue(store: InMemoryAssessmentQueueStore())
        await queue.enqueue(makeSubmission(id: "waiting"))

        let result = await queue.process(using: UnconfiguredResponseEvaluator(), rubric: rubric)

        XCTAssertEqual(result.remainingCount, 1, "プロバイダーが決まるまで提出を保持する")
        XCTAssertEqual(result.failure, .providerNotConfigured)
    }

    func testPermanentlyRejectedSubmissionsLeaveTheQueue() async {
        let queue = AssessmentQueue(store: InMemoryAssessmentQueueStore())
        await queue.enqueue(makeSubmission(id: "recorded", taskType: .interview))

        let result = await queue.process(using: FakeResponseEvaluator(), rubric: rubric)

        XCTAssertEqual(result.remainingCount, 0)
        XCTAssertEqual(result.rejected.count, 1, "再試行しても通らない提出は理由を付けて外す")
    }

    func testSuccessfulEvaluationMovesToResults() async {
        let queue = AssessmentQueue(store: InMemoryAssessmentQueueStore())
        await queue.enqueue(makeSubmission(id: "scored"))

        let result = await queue.process(
            using: FakeResponseEvaluator(scores: ["task": 4, "grammar": 4, "vocabulary": 3, "coherence": 3]),
            rubric: rubric
        )

        XCTAssertTrue(result.didEvaluateAnything)
        XCTAssertEqual(result.remainingCount, 0)

        let stored = await queue.result(for: AssessmentID(rawValue: "scored"))
        XCTAssertEqual(stored?.rubricVersion, rubric.version, "採点根拠としてルーブリック版を残す")
        XCTAssertEqual(stored?.modelVersion, "fake-model-v1", "モデル版も残す")
    }

    // MARK: - 人間レビュー

    func testHumanReviewFinalizesTheResult() async {
        let queue = AssessmentQueue(store: InMemoryAssessmentQueueStore())
        await queue.enqueue(makeSubmission(id: "reviewed"))
        await queue.process(
            using: FakeResponseEvaluator(scores: ["task": 4, "grammar": 4, "vocabulary": 4, "coherence": 4]),
            rubric: rubric
        )

        let beforeReview = await queue.result(for: AssessmentID(rawValue: "reviewed"))
        XCTAssertEqual(beforeReview?.humanReview, .notRequested)
        XCTAssertFalse(beforeReview?.isFinalized ?? true, "AIの採点だけでは最終結果にしない")

        let reviewed = await queue.applyHumanReview(.confirmed, to: AssessmentID(rawValue: "reviewed"))

        XCTAssertEqual(reviewed?.humanReview, .confirmed)
        XCTAssertTrue(reviewed?.isFinalized ?? false)
    }

    // MARK: - Helpers

    private func makeSubmission(
        id: String,
        taskType: AssessmentTaskType = .writing,
        text: String? = "Saya tinggal di Jakarta.",
        audioReference: String? = nil
    ) -> AssessmentSubmission {
        AssessmentSubmission(
            id: AssessmentID(rawValue: id),
            taskType: taskType,
            level: .b,
            rubricID: rubric.id,
            text: text,
            audioReference: audioReference,
            submittedAt: date
        )
    }
}

final class GoldenAnswerRegressionTests: XCTestCase {
    private let rubric = DemoAssessment.writingRubric
    private let suite = DemoAssessment.goldenSuite
    private let runner = GoldenAnswerRegressionRunner()

    /// 全ての基準回答が期待範囲の内側に落ちる素点。端ちょうどに載せない。
    static let wellBehavedScores: [String: [String: Int]] = [
        // B級（重み 0.3/0.3/0.2/0.2、合格 0.6）
        "golden-rich": ["task": 4, "grammar": 4, "vocabulary": 4, "coherence": 3],
        // 実測範囲に余裕を持たせた 0.80〜1.0 の内側（0.90）に落とす。
        "golden-strong": ["task": 4, "grammar": 4, "vocabulary": 3, "coherence": 3],
        // 範囲 0.70〜1.0 の内側（0.75）に落とす。
        "golden-adequate": ["task": 3, "grammar": 3, "vocabulary": 3, "coherence": 3],
        "golden-grammar-broken": ["task": 2, "grammar": 1, "vocabulary": 2, "coherence": 2],
        "golden-padding-repetition": ["task": 1, "grammar": 2, "vocabulary": 1, "coherence": 1],
        "golden-injection": ["task": 0, "grammar": 1, "vocabulary": 0, "coherence": 0],
        "golden-weak": ["task": 0, "grammar": 1, "vocabulary": 0, "coherence": 0],
        "golden-wrong-language": ["task": 0, "grammar": 1, "vocabulary": 0, "coherence": 0],
        // A級（重み 0.2/0.3/0.2/0.15/0.15、合格 0.7）
        "a-strong": ["task": 4, "argument": 4, "grammar": 3, "vocabulary": 4, "register": 4],
        "a-adequate": ["task": 3, "argument": 3, "grammar": 3, "vocabulary": 3, "register": 4],
        "a-no-argument": ["task": 2, "argument": 0, "grammar": 3, "vocabulary": 2, "register": 3],
        "a-colloquial": ["task": 2, "argument": 2, "grammar": 2, "vocabulary": 2, "register": 0],
        "a-weak": ["task": 1, "argument": 1, "grammar": 2, "vocabulary": 1, "register": 2],
        "a-injection": ["task": 0, "argument": 0, "grammar": 0, "vocabulary": 0, "register": 0],
        "a-wrong-language": ["task": 0, "argument": 0, "grammar": 1, "vocabulary": 0, "register": 0]
    ]

    static func wellBehavedEvaluator() -> ScriptedResponseEvaluator {
        ScriptedResponseEvaluator(scoresBySubmissionID: wellBehavedScores)
    }

    static var suites: [(GoldenAnswerSuite, Rubric)] {
        [
            (DemoAssessment.goldenSuite, DemoAssessment.writingRubric),
            (DemoAssessment.goldenSuiteA, DemoAssessment.writingRubricA)
        ]
    }


    func testSuiteMatchesTheRubricVersion() {
        for (suite, rubric) in Self.suites {
            XCTAssertEqual(suite.rubricID, rubric.id)
            XCTAssertEqual(
                suite.rubricVersion,
                rubric.version,
                "\(suite.version): 基準回答はルーブリックの版に対応づける"
            )
            XCTAssertFalse(suite.answers.isEmpty)
        }
    }

    /// 期待範囲が合格ラインをまたいでいないことを、機械的に確かめる。
    ///
    /// またいだ範囲は「点数は範囲内なのに合否だけ外れる」状態を生み、
    /// 回帰なのかモデルの揺れなのか区別できなくなる。
    func testExpectedRangesDoNotStraddleThePassingLine() {
        for (suite, rubric) in Self.suites {
            for golden in suite.answers {
                XCTAssertLessThanOrEqual(
                    golden.expectedMinimumScore,
                    golden.expectedMaximumScore,
                    "\(golden.id): 範囲の上下が逆"
                )
                if golden.expectedPassed {
                    XCTAssertGreaterThanOrEqual(
                        golden.expectedMinimumScore,
                        rubric.passingScore,
                        "\(golden.id): 合格を期待するなら下限を合格ライン以上にする"
                    )
                } else {
                    XCTAssertLessThan(
                        golden.expectedMaximumScore,
                        rubric.passingScore,
                        "\(golden.id): 不合格を期待するなら上限を合格ライン未満にする"
                    )
                }
            }
        }
    }

    /// 設問を伴わない基準回答は、実際の採点条件と違う条件で測ったことになる。
    func testEveryGoldenAnswerCarriesThePrompt() {
        for (suite, _) in Self.suites {
            for golden in suite.answers {
                XCTAssertNotNil(golden.submission.prompt, "\(golden.id): 設問がない")
                XCTAssertFalse(golden.submission.prompt?.isEmpty ?? true)
            }
        }
    }

    func testSuitesCoverDistinctFailureModes() {
        for (suite, _) in Self.suites {
            let identifiers = Set(suite.answers.map(\.id))
            XCTAssertEqual(identifiers.count, suite.answers.count, "\(suite.version): IDが重複")
            XCTAssertTrue(
                suite.answers.contains { $0.expectedPassed },
                "\(suite.version): 合格側の基準がない"
            )
            XCTAssertTrue(
                suite.answers.contains { $0.expectedPassed == false },
                "\(suite.version): 不合格側の基準がない"
            )
            XCTAssertTrue(
                identifiers.contains { $0.contains("injection") },
                "\(suite.version): 注入への追従を検出する基準がない"
            )
        }
    }

    /// A級固有の失敗（主張がない、話し言葉）を検出できる構成になっているか。
    func testAdvancedSuiteProbesArgumentAndRegister() {
        let identifiers = Set(DemoAssessment.goldenSuiteA.answers.map(\.id))

        XCTAssertTrue(identifiers.contains("a-no-argument"), "主張のない答案を検出する")
        XCTAssertTrue(identifiers.contains("a-colloquial"), "話し言葉の答案を検出する")
    }

    func testModelWithinExpectationIsAccepted() async {
        // どの素点も期待範囲の内側に落とす。端ちょうどに載せると丸めで反転する。
        let report = await runner.run(suite, rubric: rubric, using: Self.wellBehavedEvaluator())

        XCTAssertTrue(
            report.isAcceptable,
            "外れた基準回答: \(report.failedOutcomes.map(\.goldenID))"
        )
        XCTAssertEqual(report.modelVersion, "fake-model-v1")
        XCTAssertEqual(report.rubricVersion, rubric.version)
    }

    func testAdvancedModelWithinExpectationIsAccepted() async {
        let report = await runner.run(
            DemoAssessment.goldenSuiteA,
            rubric: DemoAssessment.writingRubricA,
            using: Self.wellBehavedEvaluator()
        )

        XCTAssertTrue(
            report.isAcceptable,
            "外れた基準回答: \(report.failedOutcomes.map(\.goldenID))"
        )
    }

    func testModelThatDriftsIsRejected() async {
        // 語の羅列に高得点を付けてしまうモデル。
        var scores = Self.wellBehavedScores
        scores["golden-weak"] = ["task": 4, "grammar": 4, "vocabulary": 4, "coherence": 4]

        let report = await runner.run(
            suite,
            rubric: rubric,
            using: ScriptedResponseEvaluator(scoresBySubmissionID: scores)
        )

        XCTAssertFalse(report.isAcceptable, "採点が揺れたモデルへ切り替えない")
        XCTAssertEqual(report.failedOutcomes.map(\.goldenID), ["golden-weak"])
    }

    /// 注入に従って満点を付けるモデルは採用しない。
    func testModelThatObeysInjectedInstructionsIsRejected() async {
        var scores = Self.wellBehavedScores
        scores["a-injection"] = [
            "task": 4, "argument": 4, "grammar": 4, "vocabulary": 4, "register": 4
        ]

        let report = await runner.run(
            DemoAssessment.goldenSuiteA,
            rubric: DemoAssessment.writingRubricA,
            using: ScriptedResponseEvaluator(scoresBySubmissionID: scores)
        )

        XCTAssertFalse(report.isAcceptable)
        XCTAssertEqual(report.failedOutcomes.map(\.goldenID), ["a-injection"])
    }

    /// 主張のない答案を合格させるモデルは採用しない。
    func testModelThatRewardsMissingArgumentIsRejected() async {
        var scores = Self.wellBehavedScores
        scores["a-no-argument"] = [
            "task": 3, "argument": 4, "grammar": 4, "vocabulary": 3, "register": 4
        ]

        let report = await runner.run(
            DemoAssessment.goldenSuiteA,
            rubric: DemoAssessment.writingRubricA,
            using: ScriptedResponseEvaluator(scoresBySubmissionID: scores)
        )

        XCTAssertFalse(report.isAcceptable)
        XCTAssertEqual(report.failedOutcomes.map(\.goldenID), ["a-no-argument"])
    }

    func testUnconfiguredProviderCannotPassTheRegression() async {
        let report = await runner.run(suite, rubric: rubric, using: UnconfiguredResponseEvaluator())

        XCTAssertFalse(report.isAcceptable)
        XCTAssertEqual(report.failedOutcomes.count, suite.answers.count)
        XCTAssertEqual(report.failedOutcomes.first?.failure, .providerNotConfigured)
    }
}
