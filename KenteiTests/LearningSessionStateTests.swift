import XCTest
@testable import Kentei

final class LearningSessionStateTests: XCTestCase {
    func testSubmitRecordsAnswerOnlyOnce() throws {
        var session = LearningSessionState.demo
        let question = try XCTUnwrap(session.currentQuestion)

        session.select(question.correctChoiceID)

        XCTAssertTrue(session.submit())
        XCTAssertFalse(session.submit())
        XCTAssertEqual(session.answeredCount, 1)
        XCTAssertEqual(session.correctCount, 1)
    }

    func testTenthAnswerMovesToMidpoint() throws {
        var session = LearningSessionState.demo

        try answerCorrectly(count: LearningSessionState.checkpointQuestionCount, session: &session)

        XCTAssertEqual(session.phase, .midpoint)
        XCTAssertEqual(session.answeredCount, 10)
        XCTAssertEqual(session.currentIndex, 10)
    }

    func testTwentyAnswersMoveToFinalResult() throws {
        var session = LearningSessionState.demo

        try answerCorrectly(count: LearningSessionState.checkpointQuestionCount, session: &session)
        session.continueAfterMidpoint()
        try answerCorrectly(count: 10, session: &session)

        XCTAssertEqual(session.phase, .finalResult)
        XCTAssertEqual(session.answeredCount, 20)
        XCTAssertEqual(session.correctCount, 20)
        XCTAssertEqual(session.accuracy, 1)
    }

    func testCannotAdvanceBeforeSubmitting() {
        var session = LearningSessionState.demo

        session.advance()

        XCTAssertEqual(session.currentIndex, 0)
        XCTAssertEqual(session.phase, .answering)
    }

    private func answerCorrectly(
        count: Int,
        session: inout LearningSessionState
    ) throws {
        for _ in 0..<count {
            let question = try XCTUnwrap(session.currentQuestion)
            session.select(question.correctChoiceID)
            XCTAssertTrue(session.submit())
            session.advance()
        }
    }
}

