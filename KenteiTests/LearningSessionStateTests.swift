import XCTest
@testable import Kentei

final class LearningSessionStateTests: XCTestCase {
    private static let answeredAt = Date(timeIntervalSince1970: 1_700_000_000)

    func testSubmitRecordsAnswerOnlyOnce() throws {
        var session = LearningSessionState.demo
        let question = try XCTUnwrap(session.currentQuestion)

        session.select(question.correctChoiceID)

        XCTAssertTrue(session.submit(at: Self.answeredAt))
        XCTAssertFalse(session.submit(at: Self.answeredAt))
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

    // MARK: - 教材の作り

    func testCorrectAnswerPositionIsNotBiased() throws {
        let questions = DemoLearningContent.pack.questions

        let positions = try questions.map { question in
            try XCTUnwrap(question.choices.firstIndex { $0.id == question.correctChoiceID })
        }

        XCTAssertEqual(
            Set(positions).count,
            4,
            "正解が特定の位置に偏ると、聞き取らずに当てられてしまう"
        )
        for position in 0..<4 {
            XCTAssertGreaterThanOrEqual(
                positions.count(where: { $0 == position }),
                2,
                "位置 \(position) の正解が少なすぎる"
            )
        }
    }

    func testEveryDemoQuestionIsDistinct() {
        let questions = DemoLearningContent.pack.questions

        XCTAssertEqual(questions.count, 20)
        XCTAssertEqual(Set(questions.map(\.id)).count, questions.count, "問題IDが重複しない")
        XCTAssertEqual(
            Set(questions.map(\.transcript)).count,
            questions.count,
            "1セッション内で同じ音声を繰り返さない"
        )
    }

    func testEveryDemoQuestionHasFourDistinctChoicesIncludingTheCorrectOne() {
        for question in DemoLearningContent.pack.questions {
            XCTAssertEqual(question.choices.count, 4, "\(question.id.rawValue)")
            XCTAssertEqual(
                Set(question.choices.map(\.id)).count,
                question.choices.count,
                "\(question.id.rawValue): 選択肢IDが重複しない"
            )
            XCTAssertEqual(
                Set(question.choices.map(\.text)).count,
                question.choices.count,
                "\(question.id.rawValue): 同じ文言の選択肢を出さない"
            )
            XCTAssertTrue(
                question.choices.contains { $0.id == question.correctChoiceID },
                "\(question.id.rawValue): 正解が選択肢に含まれる"
            )
            XCTAssertFalse(question.explanation.isEmpty, "\(question.id.rawValue): 解説が必要")
        }
    }

    private func answerCorrectly(
        count: Int,
        session: inout LearningSessionState
    ) throws {
        for _ in 0..<count {
            let question = try XCTUnwrap(session.currentQuestion)
            session.select(question.correctChoiceID)
            XCTAssertTrue(session.submit(at: Self.answeredAt))
            session.advance()
        }
    }
}

