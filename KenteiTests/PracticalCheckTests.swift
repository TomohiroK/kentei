import XCTest
@testable import Kentei

final class PracticalCheckTests: XCTestCase {
    private let pack = DemoLearningContent.pack
    private let evaluator = PracticalCheckEvaluator()
    private let atlasEvaluator = LifeAtlasEvaluator()
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - 採点

    func testPassingRequiresTheConfiguredAccuracy() {
        let result = evaluator.evaluate(
            scenarioID: .hospital,
            answers: answers(correct: 4, incorrect: 1),
            at: date
        )

        XCTAssertTrue(result.isPassed, "5問中4問正解は8割で合格")
        XCTAssertEqual(result.correctCount, 4)
        XCTAssertEqual(result.questionCount, 5)
        XCTAssertEqual(result.passedAt, date)
    }

    func testFailingBelowTheThreshold() {
        let result = evaluator.evaluate(
            scenarioID: .hospital,
            answers: answers(correct: 3, incorrect: 2),
            at: date
        )

        XCTAssertFalse(result.isPassed)
        XCTAssertNil(result.passedAt)
        XCTAssertEqual(result.accuracy, 0.6, accuracy: 0.0001)
    }

    func testResultRecordsThePolicyVersion() {
        let result = evaluator.evaluate(scenarioID: .bank, answers: answers(correct: 5, incorrect: 0), at: date)

        XCTAssertEqual(
            result.policyVersion,
            PracticalCheckPolicy.current.version,
            "合否の根拠を後から再現できるようにする"
        )
    }

    // MARK: - 行動解放

    func testActionRequiringPracticalCheckStaysLockedWithoutIt() throws {
        let scenario = try XCTUnwrap(DemoLifeAtlas.scenario(with: .hospital))
        let action = try XCTUnwrap(scenario.actions.last)
        XCTAssertTrue(action.requiresPracticalCheck, "各C級カテゴリの最後の行動は実戦チェックが要る")

        let status = atlasEvaluator.unlockStatus(
            for: action,
            mastery: masteredRecords(for: action.requiredQuestionIDs),
            practicalCheck: nil,
            at: date
        )

        XCTAssertFalse(status.isUnlocked, "問題を習得しただけでは解放しない")
        XCTAssertTrue(status.awaitsPracticalCheck, "残っているのは実戦チェックだと示す")
        XCTAssertEqual(status.remainingCount, 0)
    }

    func testPassingPracticalCheckUnlocksTheAction() throws {
        let scenario = try XCTUnwrap(DemoLifeAtlas.scenario(with: .hospital))
        let action = try XCTUnwrap(scenario.actions.last)
        let passed = evaluator.evaluate(scenarioID: .hospital, answers: answers(correct: 5, incorrect: 0), at: date)

        let status = atlasEvaluator.unlockStatus(
            for: action,
            mastery: masteredRecords(for: action.requiredQuestionIDs),
            practicalCheck: passed,
            at: date
        )

        XCTAssertTrue(status.isUnlocked)
        XCTAssertTrue(status.hasPassedPracticalCheck)
        XCTAssertFalse(status.awaitsPracticalCheck)
    }

    func testFailedPracticalCheckDoesNotUnlock() throws {
        let scenario = try XCTUnwrap(DemoLifeAtlas.scenario(with: .police))
        let action = try XCTUnwrap(scenario.actions.last)
        let failed = evaluator.evaluate(scenarioID: .police, answers: answers(correct: 2, incorrect: 3), at: date)

        let status = atlasEvaluator.unlockStatus(
            for: action,
            mastery: masteredRecords(for: action.requiredQuestionIDs),
            practicalCheck: failed,
            at: date
        )

        XCTAssertFalse(status.isUnlocked)
    }

    func testScenarioProgressCarriesTheLatestCheck() throws {
        let scenario = try XCTUnwrap(DemoLifeAtlas.scenario(with: .bank))
        let passed = evaluator.evaluate(scenarioID: .bank, answers: answers(correct: 5, incorrect: 0), at: date)

        let progress = atlasEvaluator.progress(
            for: scenario,
            pack: pack,
            mastery: [:],
            practicalCheck: passed,
            at: date
        )

        XCTAssertTrue(progress.requiresPracticalCheck)
        XCTAssertEqual(progress.practicalCheck, passed)
    }

    // MARK: - セッション

    func testPracticalCheckSessionIsShortAndScenarioOnly() {
        var generator = SeededRandomNumberGenerator(seed: 41)
        let plan = LearningSessionPlanner.makePlan(
            from: pack,
            origin: .practicalCheck(.pharmacy),
            at: date,
            questionCount: LearningSessionOrigin.practicalCheck(.pharmacy).sessionQuestionCount,
            using: &generator
        )

        XCTAssertEqual(plan.entries.count, PracticalCheckPolicy.current.questionCount)

        let scenarioIDs = plan.questionIDs.compactMap { pack.question(with: $0)?.scenarioIDs }
        for ids in scenarioIDs {
            XCTAssertTrue(ids.contains(.pharmacy), "実戦チェックはそのカテゴリの教材で行う")
        }
    }

    // MARK: - 保存形式の移行

    func testSchemaVersionOneMasteryRecordsAreStillReadable() throws {
        let json = """
        {
          "records": [
            {
              "correctStreak": 2,
              "evaluatedWithSettingsVersion": "mastery-2026-08-v1",
              "incorrectStreak": 0,
              "lastAnsweredAt": "2026-08-01T00:00:00Z",
              "masteryScore": 22,
              "nextReviewAt": "2026-08-08T00:00:00Z",
              "questionID": "demo-question-1",
              "state": "mastered"
            }
          ],
          "schemaVersion": 1,
          "settingsVersion": "mastery-2026-08-v1"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = try decoder.decode(MasteryRecords.self, from: Data(json.utf8))

        XCTAssertEqual(records.schemaVersion, 1)
        XCTAssertEqual(records.records.count, 1)
        XCTAssertTrue(records.practicalChecks.isEmpty, "v1は実戦チェック未実施として読む")
        XCTAssertTrue(MasteryRecords.supportedSchemaVersions.contains(1))
    }

    func testLatestPracticalCheckWins() {
        let older = PracticalCheckResult(
            scenarioID: .bank,
            correctCount: 2,
            questionCount: 5,
            evaluatedAt: date,
            passedAt: nil,
            policyVersion: PracticalCheckPolicy.current.version
        )
        let newer = PracticalCheckResult(
            scenarioID: .bank,
            correctCount: 5,
            questionCount: 5,
            evaluatedAt: date.addingTimeInterval(600),
            passedAt: date.addingTimeInterval(600),
            policyVersion: PracticalCheckPolicy.current.version
        )

        let records = MasteryRecords(records: [], practicalChecks: [older, newer])

        XCTAssertEqual(records.latestPracticalChecks[.bank], newer, "同じカテゴリは直近の結果を使う")
    }

    // MARK: - Helpers

    private func answers(correct: Int, incorrect: Int) -> [AnsweredQuestion] {
        var result: [AnsweredQuestion] = []
        for index in 0..<(correct + incorrect) {
            result.append(
                AnsweredQuestion(
                    questionID: QuestionID(rawValue: "demo-question-\(61 + index)"),
                    choiceID: ChoiceID(rawValue: "demo-question-\(61 + index)-choice-1"),
                    isCorrect: index < correct,
                    answeredAt: date,
                    audioPlayCount: 1
                )
            )
        }
        return result
    }

    private func masteredRecords(for questionIDs: [QuestionID]) -> [QuestionID: QuestionMastery] {
        let masteryEvaluator = MasteryEvaluator()
        var records: [QuestionID: QuestionMastery] = [:]

        for questionID in questionIDs {
            var record: QuestionMastery?
            for index in 0..<2 {
                record = masteryEvaluator.updated(
                    record,
                    with: AnsweredQuestion(
                        questionID: questionID,
                        choiceID: ChoiceID(rawValue: "\(questionID.rawValue)-choice-1"),
                        isCorrect: true,
                        answeredAt: date.addingTimeInterval(TimeInterval(index * 60)),
                        audioPlayCount: 1
                    )
                )
            }
            records[questionID] = record
        }
        return records
    }
}
