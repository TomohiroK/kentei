import XCTest

@MainActor
final class OralPracticeUITests: XCTestCase {
    func testWrittenInterviewPlaysQuestionAndShowsJapaneseOnlyOnRequest() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipOnboarding", "-showOralTask", "interview-written-b", "-interfaceLanguage", "ja"]
        app.launch()
        let play = app.buttons["interview.playQuestion"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["interview.hintText"].exists)
        XCTAssertFalse(app.buttons["oral.start"].exists)
        app.buttons["interview.hint"].tap()
        XCTAssertTrue(app.staticTexts["interview.hintText"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["interview.hintText"].label.contains("報告書"))
        app.buttons["interview.hintClose"].tap()
        XCTAssertFalse(app.staticTexts["interview.hintText"].exists)
        play.tap()
        XCTAssertTrue(app.buttons["interview.stopQuestion"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["質問を聞き終わりました。回答してください。"].waitForExistence(timeout: 60))
        XCTAssertFalse(app.staticTexts["interview.hintText"].exists)
        app.swipeUp()
        let editor = app.textViews["oral.transcript"]
        editor.tap()
        editor.typeText("Saya akan menghubungi atasan.")
        app.swipeUp()
        app.switches["oral.confirm"].tap()
        app.buttons["oral.submit"].tap()
        XCTAssertTrue(app.staticTexts["回答を端末に保存しました。"].waitForExistence(timeout: 5))
        app.buttons["oral.delete"].tap()
    }

    func testVoiceInterviewRequiresQuestionAndHidesHintOnRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipOnboarding", "-showOralTask", "interview-a", "-interfaceLanguage", "id"]
        app.launch()
        XCTAssertTrue(app.buttons["interview.playQuestion"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["interview.hintText"].exists)
        app.buttons["interview.hint"].tap()
        XCTAssertTrue(app.staticTexts["interview.hintText"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["interview.hintText"].label.contains("在宅勤務"))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["interview.playQuestion"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["interview.hintText"].exists)
        app.buttons["interview.playQuestion"].tap()
        XCTAssertTrue(app.staticTexts["Pertanyaan selesai. Silakan menjawab."].waitForExistence(timeout: 60))
        app.swipeUp()
        XCTAssertTrue(app.buttons["oral.start"].isEnabled)
        XCTAssertFalse(app.textViews["oral.transcript"].exists)
    }

    func testTranscriptCanBeSavedRestoredAndDeletedWithoutNetwork() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipOnboarding", "-showOralTask", "speaking-a", "-interfaceLanguage", "ja"]
        app.launch()
        let editor = app.textViews["oral.transcript"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText("Saya setuju dengan perubahan ini.")
        app.swipeUp()
        let confirmation = app.switches["oral.confirm"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.tap()
        let submit = app.buttons["oral.submit"]
        XCTAssertTrue(submit.isEnabled)
        submit.tap()
        XCTAssertTrue(app.staticTexts["テキストを端末に保存しました。音声は削除済みです。"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["-skipOnboarding", "-showOralTask", "speaking-a", "-interfaceLanguage", "id"]
        app.launch()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, "Saya setuju dengan perubahan ini.")
        app.swipeUp()
        app.buttons["oral.delete"].tap()
        XCTAssertEqual(editor.value as? String, "")
    }
}

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

    // MARK: - 実戦チェック

    func testPracticalCheckRunsAsAShortScenarioSession() {
        app.launchArguments = [
            "-resetLearningData", "-skipOnboarding", "-showAtlas", "-showScenarioDetail", "hospital"
        ]
        app.launch()

        let start = app.buttons["atlas.startPracticalCheck"]
        XCTAssertTrue(start.waitForExistence(timeout: 8), "C級カテゴリに実戦チェックがある")
        start.tap()

        XCTAssertTrue(app.buttons["session.playAudio"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["1 / 5"].exists,
            "実戦チェックは5問で行う"
        )

        answerQuestions(count: 5)

        XCTAssertTrue(
            app.buttons["result.finish"].waitForExistence(timeout: 5),
            "5問で結果まで到達する"
        )
    }

    // MARK: - 多言語

    func testCoreFlowWorksInIndonesian() {
        app.launchArguments = ["-resetLearningData", "-skipOnboarding", "-interfaceLanguage", "id"]
        app.launch()

        // 文言は変わっても、主要フローは同じ操作で完了できる。
        XCTAssertTrue(
            app.staticTexts["Selamat pagi"].waitForExistence(timeout: 8),
            "インドネシア語表示になる"
        )

        startLesson()
        answerCurrentQuestion(advancing: false)

        XCTAssertTrue(
            app.buttons["session.feedbackNext"].waitForExistence(timeout: 5),
            "インドネシア語でも解説まで進める"
        )

        app.buttons["session.feedbackNext"].tap()
        XCTAssertTrue(app.buttons["session.playAudio"].waitForExistence(timeout: 5))
    }

    func testAtlasWorksInIndonesian() {
        app.launchArguments = [
            "-resetLearningData", "-skipOnboarding", "-showAtlas", "-interfaceLanguage", "id"
        ]
        app.launch()

        let card = app.buttons["atlas.scenario.warung"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        card.tap()

        XCTAssertTrue(
            app.buttons["atlas.startScenario"].waitForExistence(timeout: 5),
            "インドネシア語でも生活図鑑から学習を始められる"
        )
    }

    // MARK: - データ削除

    func testDeletingLearningDataRemovesResume() {
        launchFreshSession()
        startLesson()
        answerQuestions(count: 2)

        app.terminate()
        app.launchArguments = ["-skipOnboarding", "-showTab", "settings"]
        app.launch()

        let deleteButton = app.buttons["settings.deleteData"]
        // 設定は縦に長いため、必要なら下までたどる。
        scrollUntilVisible(deleteButton)
        XCTAssertTrue(deleteButton.exists, "設定に学習データの削除がある")
        deleteButton.tap()

        // 確認ダイアログは同じ識別子の要素を複数返すことがあるため先頭を使う。
        let confirm = app.buttons.matching(identifier: "settings.deleteData.confirm").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "削除前に確認する")
        confirm.tap()

        app.tabBars.buttons.element(boundBy: 0).tap()

        XCTAssertTrue(app.buttons["home.startLesson"].waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.buttons["home.resumeLesson"].exists,
            "削除後は続きからの導線が残らない"
        )
    }

    // MARK: - 生活図鑑

    func testSelectingScenarioOpensDetailAndStartsLearning() {
        app.launchArguments = ["-resetLearningData", "-skipOnboarding", "-showAtlas"]
        app.launch()

        let card = app.buttons["atlas.scenario.warung"]
        XCTAssertTrue(card.waitForExistence(timeout: 8), "生活図鑑にカテゴリが並ぶ")

        card.tap()

        let start = app.buttons["atlas.startScenario"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "カテゴリを選ぶと詳細が開く")

        // 解放判定に使った設定版を画面に示し、根拠を再現できるようにしている。
        let versionLabel = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "unlock-")
        ).firstMatch
        XCTAssertTrue(versionLabel.exists, "解放条件の設定版を示す")

        start.tap()

        XCTAssertTrue(
            app.buttons["session.playAudio"].waitForExistence(timeout: 5),
            "その場面の学習が始まる"
        )
    }

    func testReviewEntryStartsASession() {
        app.launchArguments = ["-resetLearningData", "-skipOnboarding"]
        app.launch()

        XCTAssertTrue(app.buttons["home.startLesson"].waitForExistence(timeout: 8))
        app.tabBars.buttons.element(boundBy: 1).tap()

        let review = app.buttons["learn.review"]
        XCTAssertTrue(review.waitForExistence(timeout: 5), "学習入口に復習がある")
        review.tap()

        XCTAssertTrue(
            app.buttons["session.playAudio"].waitForExistence(timeout: 5),
            "復習からも同じ教材で学習が始まる"
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

    /// 画面外の要素までスクロールして探す。
    private func scrollUntilVisible(_ element: XCUIElement, attempts: Int = 8) {
        for _ in 0..<attempts {
            if element.exists, element.isHittable {
                return
            }
            app.swipeUp()
        }
    }

    private func selectFirstOption() {
        let option = app.buttons.matching(identifier: "onboarding.option").firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), "選択肢が表示される")
        option.tap()
    }
}
