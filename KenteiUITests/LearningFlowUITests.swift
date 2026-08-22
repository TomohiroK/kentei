import XCTest

/// Phase 1 の完了条件を、実際の操作で確認する。
///
/// 単体テストでは追えない画面遷移（回答→解説→区切り→総合結果、離脱と復帰）を対象にする。
final class LearningFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - 20問の通し

    func testCompletingTwentyQuestionsReachesFinalResult() {
        launchFreshSession()
        startLesson()

        answerQuestions(count: LearningSessionUI.checkpointQuestionCount)

        XCTAssertTrue(
            app.buttons["midpoint.continue"].waitForExistence(timeout: 5),
            "10問終えたら中間結果へ進む"
        )

        app.buttons["midpoint.continue"].tap()
        answerQuestions(count: LearningSessionUI.checkpointQuestionCount)

        XCTAssertTrue(
            app.buttons["result.finish"].waitForExistence(timeout: 5),
            "20問終えたら総合結果へ進む"
        )
    }

    // MARK: - 区切りで次の問題が始まらない

    func testMidpointDoesNotStartNextQuestion() {
        launchFreshSession()
        startLesson()

        answerQuestions(count: LearningSessionUI.checkpointQuestionCount)

        XCTAssertTrue(app.buttons["midpoint.continue"].waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.buttons["session.playAudio"].exists,
            "中間結果では次の問題の音声操作を出さない"
        )
        XCTAssertFalse(
            app.buttons["session.submitAnswer"].exists,
            "中間結果では次の問題を読み込まない"
        )
    }

    // MARK: - 回答前に問題文を出さない

    func testQuestionTextIsHiddenUntilAnswered() {
        launchFreshSession()
        startLesson()

        XCTAssertTrue(app.buttons["session.playAudio"].waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.otherElements["session.transcriptValue"].exists,
            "回答前に問題文を露出しない"
        )
        XCTAssertFalse(app.staticTexts["session.transcriptValue"].exists)

        answerCurrentQuestion(advancing: false)

        XCTAssertTrue(
            transcriptElement.waitForExistence(timeout: 5),
            "回答後に聞こえていた文を示す"
        )
    }

    // MARK: - 解説のポップアップ

    func testExplanationAppearsAsPopupAfterAnswering() {
        launchFreshSession()
        startLesson()

        answerCurrentQuestion(advancing: false)

        XCTAssertTrue(
            app.buttons["session.feedbackNext"].waitForExistence(timeout: 5),
            "回答直後に解説を前面へ出す"
        )
        XCTAssertTrue(transcriptElement.exists)

        app.buttons["session.feedbackNext"].tap()

        XCTAssertTrue(
            app.buttons["session.playAudio"].waitForExistence(timeout: 5),
            "解説から次の問題へ進む"
        )
    }

    // MARK: - 離脱と復帰

    func testLeavingMidSessionResumesFromNextQuestion() {
        launchFreshSession()
        startLesson()

        let answeredCount = 3
        answerQuestions(count: answeredCount)

        // 学習の途中でアプリを終了する。
        app.terminate()

        app.launchArguments = ["-skipOnboarding"]
        app.launch()

        let resumeButton = app.buttons["home.resumeLesson"]
        XCTAssertTrue(resumeButton.waitForExistence(timeout: 8), "続きからの導線が出る")

        resumeButton.tap()

        XCTAssertTrue(app.buttons["session.playAudio"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["\(answeredCount + 1) / \(LearningSessionUI.sessionQuestionCount)"].exists,
            "最後に回答した問題の次から再開する"
        )
    }

    // MARK: - 初回導入

    func testOnboardingLeadsIntoFirstSession() {
        app.launchArguments = ["-resetLearningData"]
        app.launch()

        let next = app.buttons["onboarding.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 8), "初回起動は導入から始まる")

        next.tap()                                   // 目的の説明 → 言語
        next.tap()                                   // 言語 → 学習目的

        selectFirstOption()
        next.tap()                                   // 学習目的 → 目標級と経験

        selectFirstOption()
        next.tap()                                   // 目標級と経験 → 音声確認

        XCTAssertTrue(
            app.buttons["onboarding.playSample"].waitForExistence(timeout: 5),
            "最後の手順で音声の聞こえを確認する"
        )
    }

    // MARK: - 補助

    private enum LearningSessionUI {
        static let checkpointQuestionCount = 10
        static let sessionQuestionCount = 20
    }

    private var transcriptElement: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "session.transcriptValue").firstMatch
    }

    private func launchFreshSession() {
        app.launchArguments = ["-resetLearningData", "-skipOnboarding"]
        app.launch()
    }

    private func startLesson() {
        let start = app.buttons["home.startLesson"]
        XCTAssertTrue(start.waitForExistence(timeout: 8), "ホームから学習を始められる")
        start.tap()
        XCTAssertTrue(app.buttons["session.playAudio"].waitForExistence(timeout: 5))
    }

    private func answerQuestions(count: Int) {
        for _ in 0..<count {
            answerCurrentQuestion(advancing: true)
        }
    }

    private func answerCurrentQuestion(advancing: Bool) {
        let firstChoice = app.buttons["session.choice.0"]
        XCTAssertTrue(firstChoice.waitForExistence(timeout: 5), "選択肢が表示される")
        firstChoice.tap()

        let submit = app.buttons["session.submitAnswer"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        submit.tap()

        guard advancing else { return }

        let next = app.buttons["session.feedbackNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 5), "解説から次へ進める")
        next.tap()
    }

    private func selectFirstOption() {
        let option = app.buttons.matching(identifier: "onboarding.option").firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), "選択肢が表示される")
        option.tap()
    }
}
