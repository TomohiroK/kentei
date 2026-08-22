import XCTest
@testable import Kentei

final class MasteryTests: XCTestCase {
    private let evaluator = MasteryEvaluator()
    private let settings = MasteryScoringSettings.current
    private let firstQuestionID = QuestionID(rawValue: "demo-question-1")
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - 状態遷移

    func testSingleCorrectAnswerDoesNotReachMastered() {
        let record = evaluator.updated(nil, with: answer(correct: true))

        XCTAssertNotEqual(record.state, .mastered, "1回の正解では習得済みにしない")
        XCTAssertEqual(record.state, .provisional)
        XCTAssertEqual(record.correctStreak, 1)
    }

    func testConsecutiveCorrectAnswersReachMastered() {
        var record = evaluator.updated(nil, with: answer(correct: true))
        record = evaluator.updated(record, with: answer(correct: true, offset: 60))

        XCTAssertEqual(record.state, .mastered)
        XCTAssertEqual(record.correctStreak, settings.requiredCorrectStreak)
        XCTAssertNotNil(record.nextReviewAt, "習得したら次の復習期限を持つ")
    }

    func testIncorrectAnswerAfterMasteryMovesToRelearning() {
        var record = evaluator.updated(nil, with: answer(correct: true))
        record = evaluator.updated(record, with: answer(correct: true, offset: 60))
        record = evaluator.updated(record, with: answer(correct: false, offset: 120))

        XCTAssertEqual(record.state, .relearning)
        XCTAssertEqual(record.correctStreak, 0)
        XCTAssertNil(record.nextReviewAt)
    }

    func testMasteredBecomesDueForReviewAfterInterval() {
        var record = evaluator.updated(nil, with: answer(correct: true))
        record = evaluator.updated(record, with: answer(correct: true, offset: 60))

        let beforeDue = baseDate.addingTimeInterval(60 * 60 * 24)
        let afterDue = baseDate.addingTimeInterval(60 * 60 * 24 * Double(settings.reviewIntervalDays + 1))

        XCTAssertEqual(record.state(at: beforeDue), .mastered)
        XCTAssertEqual(record.state(at: afterDue), .dueForReview, "期限を過ぎたら復習対象にする")
        XCTAssertFalse(record.isMastered(at: afterDue))
    }

    // MARK: - 習得点

    func testManyReplaysDoNotEarnTheReplayBonus() {
        let few = evaluator.updated(nil, with: answer(correct: true, audioPlayCount: 1))
        let many = evaluator.updated(nil, with: answer(correct: true, audioPlayCount: settings.manyReplaysThreshold))

        XCTAssertGreaterThan(few.masteryScore, many.masteryScore, "何度も聞き直した正解は加点を抑える")
    }

    func testRepeatedMistakeIsPenalizedMoreThanASingleMistake() {
        let first = evaluator.updated(nil, with: answer(correct: false))
        let second = evaluator.updated(first, with: answer(correct: false, offset: 60))

        let singleDelta = first.masteryScore
        let repeatedDelta = second.masteryScore - first.masteryScore

        XCTAssertLessThan(repeatedDelta, singleDelta, "同じ誤りを繰り返したら弱点として強く扱う")
        XCTAssertEqual(second.incorrectStreak, 2)
    }

    func testEvaluationRecordsSettingsVersion() {
        let record = evaluator.updated(nil, with: answer(correct: true))

        XCTAssertEqual(
            record.evaluatedWithSettingsVersion,
            settings.version,
            "係数を変えても過去の判定根拠を説明できるようにする"
        )
    }

    // MARK: - Helpers

    private func answer(
        correct: Bool,
        audioPlayCount: Int = 1,
        offset: TimeInterval = 0
    ) -> AnsweredQuestion {
        AnsweredQuestion(
            questionID: firstQuestionID,
            choiceID: ChoiceID(rawValue: "demo-question-1-choice-1"),
            isCorrect: correct,
            answeredAt: baseDate.addingTimeInterval(offset),
            audioPlayCount: audioPlayCount
        )
    }
}
