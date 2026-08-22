import XCTest
@testable import Kentei

final class LifeAtlasTests: XCTestCase {
    private let pack = DemoLearningContent.pack
    private let evaluator = LifeAtlasEvaluator()
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - 教材との紐付け

    func testEveryScenarioHasQuestionsFromTheSharedPack() throws {
        for scenario in DemoLifeAtlas.scenarios {
            let questionIDs = scenario.questionIDs(in: pack)
            XCTAssertFalse(
                questionIDs.isEmpty,
                "\(scenario.id.rawValue): 級別入口と同じ教材から出題できる"
            )
        }
    }

    func testEveryActionRequiresExistingQuestions() {
        let known = Set(pack.questions.map(\.id))

        for scenario in DemoLifeAtlas.scenarios {
            for action in scenario.actions {
                XCTAssertFalse(action.requiredQuestionIDs.isEmpty, action.id.rawValue)
                for questionID in action.requiredQuestionIDs {
                    XCTAssertTrue(
                        known.contains(questionID),
                        "\(action.id.rawValue): 実在しない問題を解放条件にしない"
                    )
                }
            }
        }
    }

    func testActionQuestionsBelongToTheSameScenario() {
        for scenario in DemoLifeAtlas.scenarios {
            for action in scenario.actions {
                for questionID in action.requiredQuestionIDs {
                    let question = pack.question(with: questionID)
                    XCTAssertEqual(
                        question?.scenarioIDs.contains(scenario.id),
                        true,
                        "\(action.id.rawValue): 行動の必要問題は同じカテゴリに属する"
                    )
                }
            }
        }
    }

    // MARK: - 解放判定

    func testActionStaysLockedUntilRequiredRatioIsReached() throws {
        let scenario = try XCTUnwrap(DemoLifeAtlas.scenario(with: .warung))
        let action = try XCTUnwrap(scenario.actions.first)

        let status = evaluator.unlockStatus(for: action, mastery: [:], at: date)

        XCTAssertFalse(status.isUnlocked)
        XCTAssertEqual(status.masteredCount, 0)
        XCTAssertEqual(status.remainingCount, action.requiredQuestionIDs.count, "残り件数でロック理由を示す")
    }

    func testActionUnlocksWhenRequiredQuestionsAreMastered() throws {
        let scenario = try XCTUnwrap(DemoLifeAtlas.scenario(with: .warung))
        let action = try XCTUnwrap(scenario.actions.first)
        let mastery = masteredRecords(for: action.requiredQuestionIDs)

        let status = evaluator.unlockStatus(for: action, mastery: mastery, at: date)

        XCTAssertTrue(status.isUnlocked)
        XCTAssertEqual(status.remainingCount, 0)
    }

    func testUnlockStatusCarriesTheVersionsUsedForTheDecision() throws {
        let scenario = try XCTUnwrap(DemoLifeAtlas.scenario(with: .grab))
        let action = try XCTUnwrap(scenario.actions.first)

        let status = evaluator.unlockStatus(for: action, mastery: [:], at: date)

        XCTAssertEqual(status.policyVersion, UnlockPolicy.current.version, "解放根拠を再現できるよう設定版を記録する")
        XCTAssertEqual(status.atlasVersion, DemoLifeAtlas.version)
    }

    func testExpiredMasteryDoesNotKeepAnActionUnlocked() throws {
        let scenario = try XCTUnwrap(DemoLifeAtlas.scenario(with: .convenience))
        let action = try XCTUnwrap(scenario.actions.first)
        let mastery = masteredRecords(for: action.requiredQuestionIDs)

        let expired = date.addingTimeInterval(60 * 60 * 24 * 30)
        let status = evaluator.unlockStatus(for: action, mastery: mastery, at: expired)

        XCTAssertFalse(status.isUnlocked, "復習期限を過ぎた習得で解放を維持しない")
    }

    // MARK: - 達成率

    func testAchievementReflectsUnlockedActions() throws {
        let scenario = try XCTUnwrap(DemoLifeAtlas.scenario(with: .airport))
        let firstAction = try XCTUnwrap(scenario.actions.first)
        let mastery = masteredRecords(for: firstAction.requiredQuestionIDs)

        let progress = evaluator.progress(for: scenario, pack: pack, mastery: mastery, at: date)

        XCTAssertEqual(progress.unlockedActionCount, 1)
        XCTAssertEqual(
            progress.achievement,
            1.0 / Double(scenario.actions.count),
            accuracy: 0.0001
        )
        XCTAssertGreaterThan(progress.questionCount, 0)
    }

    func testDueForReviewQuestionsAreListedPerScenario() throws {
        let scenario = try XCTUnwrap(DemoLifeAtlas.scenario(with: .airport))
        let questionIDs = scenario.questionIDs(in: pack)
        let mastery = masteredRecords(for: Array(questionIDs.prefix(2)))

        let expired = date.addingTimeInterval(60 * 60 * 24 * 30)
        let progress = evaluator.progress(for: scenario, pack: pack, mastery: mastery, at: expired)

        XCTAssertEqual(progress.dueForReviewQuestionIDs.count, 2)
        XCTAssertEqual(progress.masteredQuestionCount, 0, "期限切れは習得済みに数えない")
    }

    // MARK: - Helpers

    private func masteredRecords(for questionIDs: [QuestionID]) -> [QuestionID: QuestionMastery] {
        let evaluator = MasteryEvaluator()
        var records: [QuestionID: QuestionMastery] = [:]

        for questionID in questionIDs {
            var record: QuestionMastery?
            for index in 0..<2 {
                record = evaluator.updated(
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
