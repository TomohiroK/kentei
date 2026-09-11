import XCTest
@testable import Kentei

@MainActor
final class WritingTaskTests: XCTestCase {
    private let rubric = DemoAssessment.writingRubric

    private var task: WritingTask {
        DemoWritingTasks.all[0]
    }

    // MARK: - 課題データ

    func testEveryTaskPointsAtAnExistingRubric() {
        // 級ごとに使う基準が決まっている。取り違えると、結果に記録した版と
        // 実際に採点した基準が食い違う。
        let rubricsByLevel: [CertificationLevel: Rubric] = [
            .b: DemoAssessment.writingRubric,
            .a: DemoAssessment.writingRubricA
        ]

        for task in DemoWritingTasks.all {
            guard let expected = rubricsByLevel[task.level] else {
                XCTFail("\(task.id): \(task.level.rawValue)級の基準が用意されていない")
                continue
            }
            XCTAssertEqual(task.rubricID, expected.id, "\(task.id): 級に対応した基準を使う")
            XCTAssertEqual(expected.level, task.level, "\(task.id): 基準の級が課題と一致する")
            XCTAssertEqual(task.taskType, .writing)
            XCTAssertFalse(task.taskType.requiresRecording, "録音を伴う課題は提供しない")
            XCTAssertGreaterThan(task.minimumCharacters, 0)
        }
    }

    /// A級はB級より長い記述を求める。同じ字数なら級を分ける意味がない。
    func testAdvancedTasksDemandLongerWriting() {
        let b = DemoWritingTasks.tasks(for: .b).map(\.minimumCharacters).max() ?? 0
        let a = DemoWritingTasks.tasks(for: .a).map(\.minimumCharacters).min() ?? 0

        XCTAssertGreaterThan(a, b, "A級の下限字数はB級より大きい")
    }

    func testAdvancedRubricIsStricter() {
        XCTAssertGreaterThan(
            DemoAssessment.writingRubricA.passingScore,
            DemoAssessment.writingRubric.passingScore,
            "A級の合格線はB級より高い"
        )
    }

    // MARK: - 提出の可否

    func testShortTextCannotBeSubmitted() {
        let model = makeModel(evaluator: FakeResponseEvaluator())

        model.text = "Saya."

        XCTAssertLessThan(model.characterCount, task.minimumCharacters)
        XCTAssertFalse(model.canSubmit, "字数が足りない提出は送らない")
    }

    func testLongEnoughTextCanBeSubmitted() {
        let model = makeModel(evaluator: FakeResponseEvaluator())

        model.text = String(repeating: "Saya tinggal di Jakarta. ", count: 5)

        XCTAssertTrue(model.canSubmit)
    }

    // MARK: - 採点

    func testSuccessfulAssessmentIsShown() async {
        let model = makeModel(
            evaluator: FakeResponseEvaluator(scores: ["task": 4, "grammar": 4, "vocabulary": 3, "coherence": 3])
        )
        model.text = String(repeating: "Saya tinggal di Jakarta. ", count: 5)

        await model.submit()

        guard case let .scored(result) = model.state else {
            return XCTFail("採点結果が表示されない")
        }
        XCTAssertTrue(result.isPassed)
        XCTAssertEqual(result.rubricVersion, rubric.version, "根拠として基準の版を持つ")
        XCTAssertEqual(result.scores.count, rubric.criteria.count)
    }

    func testTemporaryFailureKeepsTheSubmissionForRetry() async {
        let queue = AssessmentQueue(store: InMemoryAssessmentQueueStore())
        let model = makeModel(evaluator: FakeResponseEvaluator(failure: .temporaryFailure), queue: queue)
        model.text = String(repeating: "Saya tinggal di Jakarta. ", count: 5)

        await model.submit()

        XCTAssertEqual(model.state, .failed(.temporaryFailure))
        let pending = await queue.pendingCount
        XCTAssertEqual(pending, 1, "送れなかった提出は捨てない")
    }

    func testUnconfiguredProviderIsReportedAndQueued() async {
        let queue = AssessmentQueue(store: InMemoryAssessmentQueueStore())
        let model = makeModel(evaluator: UnconfiguredResponseEvaluator(), queue: queue)
        model.text = String(repeating: "Saya tinggal di Jakarta. ", count: 5)

        await model.submit()

        XCTAssertEqual(model.state, .failed(.providerNotConfigured))
        let pending = await queue.pendingCount
        XCTAssertEqual(pending, 1)
    }

    // MARK: - 中継の応答の解釈

    func testServerErrorsMapToRetryableAndPermanentFailures() {
        func error(_ code: String, _ status: Int) -> AssessmentError {
            RelayResponseEvaluator.error(for: status, data: Data("{\"code\":\"\(code)\"}".utf8))
        }

        XCTAssertEqual(error("recording_not_available", 400), .recordingNotAvailable)
        XCTAssertEqual(error("rubric_version_mismatch", 409), .rubricMismatch)
        XCTAssertEqual(error("empty_text", 400), .invalidSubmission)
        XCTAssertEqual(error("unauthorized", 401), .providerNotConfigured)
        XCTAssertEqual(error("client_token_not_configured", 503), .providerNotConfigured)
        XCTAssertEqual(
            RelayResponseEvaluator.error(for: 500, data: Data()),
            .temporaryFailure,
            "サーバー側の不調は再送できる失敗として扱う"
        )
    }

    func testRelayRefusesToSendWithoutAToken() async {
        let evaluator = RelayResponseEvaluator(credentialStore: InMemoryAssessmentCredentialStore())
        let submission = AssessmentSubmission(
            id: AssessmentID(rawValue: "s1"),
            taskType: .writing,
            level: .b,
            rubricID: rubric.id,
            text: "Saya tinggal di Jakarta.",
            submittedAt: Date(timeIntervalSince1970: 0)
        )

        do {
            _ = try await evaluator.evaluate(submission, rubric: rubric)
            XCTFail("トークンなしで送ってはいけない")
        } catch let error as AssessmentError {
            XCTAssertEqual(error, .providerNotConfigured)
        } catch {
            XCTFail("想定外の失敗: \(error)")
        }
    }

    func testRelayRefusesRecordingBeforeSending() async {
        let evaluator = RelayResponseEvaluator(
            credentialStore: InMemoryAssessmentCredentialStore(token: "token")
        )
        let submission = AssessmentSubmission(
            id: AssessmentID(rawValue: "s2"),
            taskType: .interview,
            level: .b,
            rubricID: rubric.id,
            text: "abc",
            audioReference: "file://x.m4a",
            submittedAt: Date(timeIntervalSince1970: 0)
        )

        do {
            _ = try await evaluator.evaluate(submission, rubric: rubric)
            XCTFail("録音は送ってはいけない")
        } catch let error as AssessmentError {
            XCTAssertEqual(error, .recordingNotAvailable)
        } catch {
            XCTFail("想定外の失敗: \(error)")
        }
    }

    // MARK: - 資格情報の保管

    func testCredentialStoreKeepsAndClearsTheToken() {
        let store = InMemoryAssessmentCredentialStore()

        XCTAssertNil(store.loadToken())

        store.save(token: "abc")
        XCTAssertEqual(store.loadToken(), "abc")

        store.save(token: "")
        XCTAssertNil(store.loadToken(), "空の入力はトークンとして保存しない")
    }

    // MARK: - Helpers

    private func makeModel(
        evaluator: any ResponseEvaluating,
        queue: AssessmentQueue? = nil
    ) -> WritingTaskModel {
        WritingTaskModel(
            task: task,
            rubric: rubric,
            evaluator: evaluator,
            queue: queue,
            clock: FixedClock(),
            identifierGenerator: FixedIdentifierGenerator()
        )
    }
}

final class AssessmentAvailabilityTests: XCTestCase {
    /// 保存した直後に画面へ反映される必要がある。
    /// 計算プロパティで Keychain を直接読むと、再起動するまで変わらない。
    @MainActor
    func testSavingTheTokenTakesEffectImmediately() {
        let credentialStore = InMemoryAssessmentCredentialStore()
        let model = AppModel(
            store: DisabledLearningSessionStore(),
            credentialStore: credentialStore
        )

        XCTAssertFalse(model.isAssessmentAvailable, "未設定なら採点は使えない")

        model.saveAssessmentToken("token-abc")

        XCTAssertTrue(model.isAssessmentAvailable, "保存したら再起動を待たずに使える")
    }

    @MainActor
    func testAvailabilityReflectsAlreadyStoredToken() {
        let credentialStore = InMemoryAssessmentCredentialStore()
        credentialStore.save(token: "token-stored")

        let model = AppModel(
            store: DisabledLearningSessionStore(),
            credentialStore: credentialStore
        )

        XCTAssertTrue(model.isAssessmentAvailable, "保存済みなら起動時から使える")
    }

    /// 空文字は「設定した」ことにしない。
    @MainActor
    func testBlankTokenDoesNotEnableAssessment() {
        let credentialStore = InMemoryAssessmentCredentialStore()
        let model = AppModel(
            store: DisabledLearningSessionStore(),
            credentialStore: credentialStore
        )

        model.saveAssessmentToken("   ")

        XCTAssertFalse(model.isAssessmentAvailable, "空白だけのトークンでは使えるようにしない")
    }
}

final class ModelAnswerTests: XCTestCase {
    /// アプリ本体の文言カタログから引く。テスト標的には入っていない。
    private func localized(_ key: String) -> String {
        Bundle(for: AppModel.self).localizedString(forKey: key, value: "", table: nil)
    }

    func testEveryTaskHasAModelAnswer() {
        for task in DemoWritingTasks.all {
            XCTAssertFalse(task.modelAnswerKey.isEmpty, "\(task.id): 模範回答がない")
            XCTAssertFalse(task.modelAnswerNotesKey.isEmpty, "\(task.id): 評価理由の説明がない")
        }
    }

    /// 模範回答は、その課題が課す最低文字数を自分でも満たす。
    /// 満たさない模範回答を見せると、要求と手本が食い違う。
    func testModelAnswerMeetsItsOwnRequirement() {
        for task in DemoWritingTasks.all {
            let answer = localized(task.modelAnswerKey)
            XCTAssertFalse(answer.isEmpty, "\(task.id): 模範回答の文言が引けない")
            XCTAssertGreaterThanOrEqual(
                answer.count,
                task.minimumCharacters,
                "\(task.id): 模範回答が最低文字数(\(task.minimumCharacters))に届いていない"
            )
        }
    }

    /// 模範回答はインドネシア語で書く。解答言語と手本が食い違ってはならない。
    func testModelAnswersAreWrittenInIndonesian() {
        for task in DemoWritingTasks.all {
            let answer = localized(task.modelAnswerKey)
            let containsJapanese = answer.unicodeScalars.contains { scalar in
                (0x3040...0x30FF).contains(scalar.value) || (0x4E00...0x9FFF).contains(scalar.value)
            }
            XCTAssertFalse(containsJapanese, "\(task.id): 模範回答に日本語が混ざっている")
        }
    }

    /// 説明は採点で使う観点と対応づける。観点名が出てこない説明は、
    /// 良し悪しの根拠を学習者が採点結果と結びつけられない。
    func testNotesReferToTheRubricCriteria() {
        let rubrics = [DemoAssessment.writingRubric, DemoAssessment.writingRubricA]
        for task in DemoWritingTasks.all {
            guard let rubric = rubrics.first(where: { $0.id == task.rubricID }) else {
                XCTFail("\(task.id): 対応する基準がない")
                continue
            }
            let notes = localized(task.modelAnswerNotesKey)
            XCTAssertFalse(notes.isEmpty, "\(task.id): 説明の文言が引けない")

            let lineCount = notes.split(separator: "\n").count
            XCTAssertEqual(
                lineCount,
                rubric.criteria.count,
                "\(task.id): 説明は観点と同じ数の行にする（観点\(rubric.criteria.count)個）"
            )
        }
    }

    func testModelAnswerKeysAreUnique() {
        let keys = DemoWritingTasks.all.map(\.modelAnswerKey)
        XCTAssertEqual(Set(keys).count, keys.count, "課題ごとに別の模範回答を用意する")
    }
}

final class WritingRubricSelectionTests: XCTestCase {
    /// 課題に対応する基準で採点する。
    ///
    /// 級ごとに観点も重みも合格線も違う。B級の基準でA級の答案を採点すると、
    /// 論の展開も文体も評価されないまま点数だけが出る。
    @MainActor
    func testEachTaskIsScoredWithItsOwnRubric() {
        let model = AppModel(store: DisabledLearningSessionStore())

        for task in DemoWritingTasks.all {
            let taskModel = model.makeWritingTaskModel(task: task)
            XCTAssertEqual(
                taskModel.rubric.id,
                task.rubricID,
                "\(task.id): 課題と違う基準で採点しようとしている"
            )
            XCTAssertEqual(taskModel.rubric.level, task.level, "\(task.id): 級が一致しない")
        }
    }

    @MainActor
    func testAdvancedTasksUseDistinctRubrics() {
        let model = AppModel(store: DisabledLearningSessionStore())
        let b = DemoWritingTasks.tasks(for: .b).map { model.makeWritingTaskModel(task: $0).rubric.id }
        let a = DemoWritingTasks.tasks(for: .a).map { model.makeWritingTaskModel(task: $0).rubric.id }

        XCTAssertFalse(b.isEmpty)
        XCTAssertFalse(a.isEmpty)
        XCTAssertTrue(Set(b).isDisjoint(with: Set(a)), "B級とA級で同じ基準を使っている")
    }

    func testEveryTaskRubricExists() {
        for task in DemoWritingTasks.all {
            XCTAssertNotNil(
                DemoAssessment.rubric(with: task.rubricID),
                "\(task.id): 参照している基準が存在しない"
            )
        }
    }
}
