import XCTest
@testable import Kentei

final class SessionPlanningTests: XCTestCase {
    private let pack = DemoLearningContent.pack
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - 入口ごとの出題

    func testScenarioEntryPrefersQuestionsFromThatScenario() throws {
        var generator = SeededRandomNumberGenerator(seed: 11)
        let plan = LearningSessionPlanner.makePlan(
            from: pack,
            origin: .scenario(.warung),
            at: date,
            using: &generator
        )

        let scenarioQuestionIDs = Set(
            pack.questions.filter { $0.scenarioIDs.contains(.warung) }.map(\.id)
        )
        let leading = plan.questionIDs.prefix(scenarioQuestionIDs.count)

        XCTAssertEqual(
            Set(leading),
            scenarioQuestionIDs,
            "生活図鑑の入口では、そのカテゴリの教材を先に出す"
        )
    }

    func testScenarioEntryStillBuildsAFullSessionFromTheSharedPack() throws {
        var generator = SeededRandomNumberGenerator(seed: 12)
        let plan = LearningSessionPlanner.makePlan(
            from: pack,
            origin: .scenario(.warung),
            at: date,
            using: &generator
        )

        XCTAssertEqual(
            plan.entries.count,
            LearningSessionPlanner.defaultQuestionCount,
            "カテゴリの教材が20問に満たなくても、同じプールから補って1セッションを組む"
        )
        XCTAssertEqual(Set(plan.questionIDs).count, plan.entries.count, "同じ問題を二度出さない")
    }

    func testReviewEntryPrefersQuestionsThatNeedRelearning() throws {
        let weakIDs = pack.questions.prefix(4).map(\.id)
        var mastery: [QuestionID: QuestionMastery] = [:]
        let evaluator = MasteryEvaluator()

        // 誤答した問題を弱点として記録する。
        for questionID in weakIDs {
            mastery[questionID] = evaluator.updated(
                nil,
                with: AnsweredQuestion(
                    questionID: questionID,
                    choiceID: ChoiceID(rawValue: "\(questionID.rawValue)-choice-2"),
                    isCorrect: false,
                    answeredAt: date,
                    audioPlayCount: 1
                )
            )
        }

        var generator = SeededRandomNumberGenerator(seed: 13)
        let plan = LearningSessionPlanner.makePlan(
            from: pack,
            origin: .review,
            mastery: mastery,
            at: date,
            using: &generator
        )

        XCTAssertEqual(
            Set(plan.questionIDs.prefix(weakIDs.count)),
            Set(weakIDs),
            "復習では間違えた問題を先に出す"
        )
    }

    func testMasteredQuestionsAreDeprioritised() throws {
        let evaluator = MasteryEvaluator()
        var mastery: [QuestionID: QuestionMastery] = [:]

        let masteredIDs = pack.questions.prefix(20).map(\.id)
        for questionID in masteredIDs {
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
            mastery[questionID] = record
        }

        var generator = SeededRandomNumberGenerator(seed: 14)
        let plan = LearningSessionPlanner.makePlan(
            from: pack,
            origin: .recommended,
            mastery: mastery,
            at: date,
            using: &generator
        )

        let masteredInSession = plan.questionIDs.filter { masteredIDs.contains($0) }
        XCTAssertLessThan(
            masteredInSession.count,
            plan.entries.count / 2,
            "習得済みばかりを出し直さない"
        )
    }
}

final class MasteryStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "kentei-mastery-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try super.tearDownWithError()
    }

    private var fileURL: URL {
        directory.appending(path: "mastery.json", directoryHint: .notDirectory)
    }

    func testRecordsRoundTrip() async throws {
        let store = FileMasteryStore(fileURL: fileURL)
        let records = MasteryRecords(records: [
            QuestionMastery(
                questionID: QuestionID(rawValue: "demo-question-1"),
                state: .mastered,
                masteryScore: 22,
                correctStreak: 2,
                incorrectStreak: 0,
                lastAnsweredAt: Date(timeIntervalSince1970: 1_700_000_000),
                nextReviewAt: Date(timeIntervalSince1970: 1_700_600_000)
            )
        ])

        try await store.save(records)
        let loaded = try await store.load()

        XCTAssertEqual(loaded, records)
        XCTAssertEqual(loaded?.byQuestionID.count, 1)
    }

    func testCorruptedFileIsReported() async throws {
        try Data("これはJSONではない".utf8).write(to: fileURL)
        let store = FileMasteryStore(fileURL: fileURL)

        do {
            _ = try await store.load()
            XCTFail("破損データが読めてはいけない")
        } catch let error as LearningSessionStoreError {
            XCTAssertEqual(error, .corruptedData)
        }
    }

    func testUnsupportedSchemaVersionIsDiscarded() async throws {
        let json = """
        {
          "records": [],
          "schemaVersion": \(MasteryRecords.currentSchemaVersion + 1),
          "settingsVersion": "mastery-future"
        }
        """
        try Data(json.utf8).write(to: fileURL)
        let store = FileMasteryStore(fileURL: fileURL)

        let loaded = try await store.load()

        XCTAssertNil(loaded, "対応外の版は誤った解放判定を避けるため捨てる")
    }
}
