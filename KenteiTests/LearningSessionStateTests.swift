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

    func testContentPackHasEnoughDistinctQuestions() {
        let questions = DemoLearningContent.pack.questions

        XCTAssertGreaterThanOrEqual(
            questions.count,
            LearningSessionPlanner.defaultQuestionCount * 2,
            "毎回同じ20問にならないよう、出題数の倍以上の教材を持つ"
        )
        XCTAssertEqual(Set(questions.map(\.id)).count, questions.count, "問題IDが重複しない")
        XCTAssertEqual(
            Set(questions.map(\.transcript)).count,
            questions.count,
            "同じ音声の問題を重複して持たない"
        )
    }

    func testContentPackIncludesConversationQuestions() {
        let conversations = DemoLearningContent.pack.questions.filter(\.isConversation)

        XCTAssertGreaterThanOrEqual(conversations.count, 5, "会話形式の問題を用意する")
        for question in conversations {
            XCTAssertEqual(
                Set(question.utterances.map(\.speakerIndex)).count,
                2,
                "\(question.id.rawValue): 会話は2話者で構成する"
            )
        }
    }

    func testEveryQuestionHasFourDistinctChoicesIncludingTheCorrectOne() {
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
            XCTAssertFalse(question.utterances.isEmpty, "\(question.id.rawValue): 音声原稿が必要")
        }
    }

    // MARK: - 出題と選択肢のランダム化

    func testPlanSelectsRequestedNumberOfQuestionsWithoutDuplication() {
        let plan = TestSession.makePlan(seed: 42)

        XCTAssertEqual(plan.entries.count, LearningSessionPlanner.defaultQuestionCount)
        XCTAssertEqual(
            Set(plan.questionIDs).count,
            plan.entries.count,
            "1セッション内に同じ問題を二度出さない"
        )
    }

    func testDifferentSessionsGetDifferentQuestionAndChoiceOrder() throws {
        let first = try TestSession.makeState(seed: 1)
        let second = try TestSession.makeState(seed: 2)

        XCTAssertNotEqual(
            first.questions.map(\.id),
            second.questions.map(\.id),
            "セッションごとに出題順が変わる"
        )

        let firstChoiceOrders = Dictionary(
            uniqueKeysWithValues: first.questions.map { ($0.id, $0.choices.map(\.id)) }
        )
        let changedChoiceOrders = second.questions.filter { question in
            guard let previous = firstChoiceOrders[question.id] else { return false }
            return previous != question.choices.map(\.id)
        }
        XCTAssertFalse(changedChoiceOrders.isEmpty, "選択肢の並びもセッションごとに変わる")
    }

    func testSameSeedReproducesSameSession() throws {
        let first = try TestSession.makeState(seed: 99)
        let second = try TestSession.makeState(seed: 99)

        XCTAssertEqual(first.questions.map(\.id), second.questions.map(\.id))
        XCTAssertEqual(
            first.questions.map { $0.choices.map(\.id) },
            second.questions.map { $0.choices.map(\.id) }
        )
    }

    func testCorrectAnswerIsNotAlwaysInTheSamePosition() throws {
        let session = try TestSession.makeState(seed: 2026)

        let positions = try session.questions.map { question in
            try XCTUnwrap(question.choices.firstIndex { $0.id == question.correctChoiceID })
        }

        XCTAssertGreaterThanOrEqual(
            Set(positions).count,
            3,
            "正解の位置が偏ると、聞き取らずに当てられてしまう"
        )
    }

    func testShuffledChoicesKeepTheCorrectAnswerAvailable() throws {
        let session = try TestSession.makeState(seed: 5)

        for question in session.questions {
            XCTAssertTrue(
                question.choices.contains { $0.id == question.correctChoiceID },
                "\(question.id.rawValue): 並び替え後も正解が選べる"
            )
            XCTAssertEqual(question.choices.count, 4)
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

