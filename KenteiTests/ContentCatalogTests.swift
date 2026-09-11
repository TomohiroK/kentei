import XCTest
@testable import Kentei

final class ContentCatalogTests: XCTestCase {
    private let pack = DemoLearningContent.pack
    private let validator = ContentPackValidator()

    // MARK: - 教材の中身

    func testShippedPackPassesValidation() {
        let issues = validator.validate(pack)

        XCTAssertTrue(issues.isEmpty, "公開する教材は自動検査を通る: \(issues)")
    }

    func testPackProvidesEveryProvidedLevel() {
        let levels = Set(pack.deliverableQuestions.map(\.level))

        XCTAssertEqual(levels, [.e, .d, .c], "提供中の級すべてに教材がある")
        XCTAssertGreaterThanOrEqual(pack.deliverableQuestions(at: .e).count, 20)
        XCTAssertGreaterThanOrEqual(pack.deliverableQuestions(at: .d).count, 20)
        XCTAssertGreaterThanOrEqual(pack.deliverableQuestions(at: .c).count, 20)
    }

    func testCLevelCoversLifeProcedureScenarios() {
        let cQuestions = pack.deliverableQuestions(at: .c)
        let scenarios = Set(cQuestions.flatMap(\.scenarioIDs))

        let expected: Set<ScenarioID> = [
            .hospital, .pharmacy, .bank, .simCard, .delivery,
            .housing, .police, .government, .workplace
        ]
        XCTAssertTrue(expected.isSubset(of: scenarios), "C級は生活手続きの9カテゴリを扱う")
    }

    func testCLevelUsesGrammarAndResponseFormats() {
        let types = Set(pack.deliverableQuestions(at: .c).map(\.questionType))

        XCTAssertTrue(types.contains(.grammarFunctionChoice), "接辞・受動を問う形式を含む")
        XCTAssertTrue(types.contains(.responseChoice), "定型応答を含む")
        XCTAssertTrue(types.contains(.contentMatch))
    }

    func testDLevelUsesContentMatchAndActionDecision() {
        let types = Set(pack.deliverableQuestions(at: .d).map(\.questionType))

        XCTAssertTrue(types.contains(.contentMatch), "D級は内容一致を含む")
        XCTAssertTrue(types.contains(.actionDecision), "D級は行動判断を含む")
    }

    func testEveryDistractorHasAReason() {
        for question in pack.questions {
            for choice in question.choices where choice.isCorrect == false {
                XCTAssertNotNil(
                    choice.distractorReason,
                    "\(question.id.rawValue): 誤答は理由を持つ"
                )
            }
        }
    }

    func testUnprovidedLevelsAreNotExposed() {
        XCTAssertEqual(CertificationLevel.availableLevels, [.e, .d, .c])
        XCTAssertFalse(CertificationLevel.b.isProvided, "AI評価が要るB級以上は提供しない")
        XCTAssertFalse(CertificationLevel.a.isProvided)
    }

    // MARK: - チェックサム

    func testChecksumChangesWhenContentChanges() throws {
        let original = pack.checksum
        let question = try XCTUnwrap(pack.questions.first)
        let edited = LearningQuestion(
            id: question.id,
            level: question.level,
            questionType: question.questionType,
            status: question.status,
            utterances: [ScriptedUtterance(speakerIndex: 0, text: "Selamat siang.")],
            choices: question.choices,
            correctChoiceID: question.correctChoiceID,
            explanation: question.explanation,
            scenarioIDs: question.scenarioIDs
        )

        let changed = LearningContentPack(
            version: pack.version,
            questions: [edited] + pack.questions.dropFirst()
        )

        XCTAssertNotEqual(changed.checksum, original, "内容が変わればチェックサムも変わる")
    }

    func testCorruptedChecksumIsRejected() {
        let broken = BrokenChecksumPack.make(from: pack)

        let issues = validator.validate(broken)

        XCTAssertTrue(
            issues.contains { if case .checksumMismatch = $0 { true } else { false } },
            "破損チェックサムは公開前に拒否する"
        )
    }

    // MARK: - 自動検査が拒否するもの

    func testValidatorRejectsQuestionWithoutCorrectChoice() {
        let question = makeQuestion(
            choices: [
                LearningChoice(id: ChoiceID(rawValue: "c1"), text: "A", isCorrect: false, distractorReason: .semanticNeighbor),
                LearningChoice(id: ChoiceID(rawValue: "c2"), text: "B", isCorrect: false, distractorReason: .semanticNeighbor)
            ],
            correctChoiceID: ChoiceID(rawValue: "c9")
        )

        let issues = validator.validate(LearningContentPack(version: "test", questions: [question]))

        XCTAssertTrue(issues.contains(.missingCorrectChoice(question.id)))
        XCTAssertTrue(issues.contains(.correctChoiceNotInChoices(question.id)))
    }

    func testValidatorRejectsDuplicatedChoiceText() {
        let question = makeQuestion(
            choices: [
                LearningChoice(id: ChoiceID(rawValue: "c1"), text: "同じ", isCorrect: true),
                LearningChoice(id: ChoiceID(rawValue: "c2"), text: "同じ", isCorrect: false, distractorReason: .semanticNeighbor)
            ],
            correctChoiceID: ChoiceID(rawValue: "c1")
        )

        let issues = validator.validate(LearningContentPack(version: "test", questions: [question]))

        XCTAssertTrue(issues.contains(.duplicatedChoiceText(question.id)))
    }

    func testValidatorRejectsDistractorWithoutReason() {
        let question = makeQuestion(
            choices: [
                LearningChoice(id: ChoiceID(rawValue: "c1"), text: "正", isCorrect: true),
                LearningChoice(id: ChoiceID(rawValue: "c2"), text: "誤", isCorrect: false)
            ],
            correctChoiceID: ChoiceID(rawValue: "c1")
        )

        let issues = validator.validate(LearningContentPack(version: "test", questions: [question]))

        XCTAssertTrue(issues.contains(.missingDistractorReason(question.id)))
    }

    func testValidatorRejectsUnprovidedLevelAndUndeliverableType() {
        let question = makeQuestion(
            level: .b,
            questionType: .speaking,
            choices: [
                LearningChoice(id: ChoiceID(rawValue: "c1"), text: "正", isCorrect: true),
                LearningChoice(id: ChoiceID(rawValue: "c2"), text: "誤", isCorrect: false, distractorReason: .similarSound)
            ],
            correctChoiceID: ChoiceID(rawValue: "c1")
        )

        let issues = validator.validate(LearningContentPack(version: "test", questions: [question]))

        XCTAssertTrue(issues.contains(.unavailableLevel(question.id, .b)))
        XCTAssertTrue(issues.contains(.undeliverableQuestionType(question.id, .speaking)))
    }

    // MARK: - 公開状態

    func testOnlyPublishedQuestionsAreDelivered() {
        let published = makeQuestion(id: "published", status: .published)
        let approved = makeQuestion(id: "approved", status: .approved)
        let deprecated = makeQuestion(id: "deprecated", status: .deprecated)
        let testPack = LearningContentPack(
            version: "test",
            questions: [published, approved, deprecated]
        )

        let deliverableIDs = testPack.deliverableQuestions.map(\.id.rawValue)

        XCTAssertEqual(deliverableIDs, ["published"], "承認済み・提供終了は新規セッションに出さない")
        XCTAssertTrue(ContentStatus.deprecated.isReferenceable, "提供終了でも過去回答から参照できる")
        XCTAssertFalse(ContentStatus.approved.isReferenceable)
    }

    func testLevelEntryDeliversOnlyThatLevel() {
        var generator = SeededRandomNumberGenerator(seed: 21)
        let plan = LearningSessionPlanner.makePlan(
            from: pack,
            origin: .level(.d),
            using: &generator
        )

        let levels = plan.questionIDs.compactMap { pack.question(with: $0)?.level }

        XCTAssertEqual(Set(levels), [.d], "級別入口はその級だけを出す")
        XCTAssertEqual(plan.entries.count, LearningSessionPlanner.defaultQuestionCount)
    }

    // MARK: - 教材の適用

    func testValidPackIsActivated() {
        let activator = ContentPackActivator()

        let result = activator.activate(candidate: pack, current: nil)

        guard case let .success(activation) = result else {
            return XCTFail("検証を通る教材は適用する")
        }
        XCTAssertEqual(activation.pack.version, pack.version)
        XCTAssertTrue(activation.rejectedIssues.isEmpty)
        XCTAssertTrue(activation.didSwitchVersion)
    }

    func testInvalidPackKeepsTheCurrentVersion() {
        let activator = ContentPackActivator()
        let broken = LearningContentPack(
            version: "demo-broken",
            questions: [
                makeQuestion(
                    id: "broken",
                    choices: [LearningChoice(id: ChoiceID(rawValue: "c1"), text: "正", isCorrect: true)],
                    correctChoiceID: ChoiceID(rawValue: "c1")
                )
            ]
        )

        let result = activator.activate(candidate: broken, current: pack)

        guard case let .success(activation) = result else {
            return XCTFail("現在の有効版を保持する")
        }
        XCTAssertEqual(activation.pack.version, pack.version, "検証に落ちた版へ切り替えない")
        XCTAssertFalse(activation.rejectedIssues.isEmpty, "拒否した理由を残す")
        XCTAssertFalse(activation.didSwitchVersion)
    }

    func testInvalidPackWithoutCurrentVersionIsReported() {
        let activator = ContentPackActivator()
        let broken = LearningContentPack(
            version: "demo-broken",
            questions: [
                makeQuestion(
                    id: "broken",
                    choices: [LearningChoice(id: ChoiceID(rawValue: "c1"), text: "正", isCorrect: true)],
                    correctChoiceID: ChoiceID(rawValue: "c1")
                )
            ]
        )

        let result = activator.activate(candidate: broken, current: nil)

        guard case let .failure(error) = result else {
            return XCTFail("有効版が無ければ失敗として扱う")
        }
        guard case let .noUsablePack(issues) = error else {
            return XCTFail("不備の一覧を伴う")
        }
        XCTAssertFalse(issues.isEmpty)
    }

    func testBundledProviderReturnsTheShippedPack() async throws {
        let provider = BundledContentPackProvider()

        let loaded = try await provider.loadPack()

        XCTAssertEqual(loaded.version, DemoLearningContent.version)
        XCTAssertEqual(loaded.checksum, DemoLearningContent.pack.checksum)
    }

    // MARK: - Helpers

    private func makeQuestion(
        id: String = "test-question",
        level: CertificationLevel = .e,
        questionType: QuestionType = .audioMeaningChoice,
        status: ContentStatus = .published,
        choices: [LearningChoice] = [
            LearningChoice(id: ChoiceID(rawValue: "c1"), text: "正", isCorrect: true),
            LearningChoice(id: ChoiceID(rawValue: "c2"), text: "誤", isCorrect: false, distractorReason: .semanticNeighbor)
        ],
        correctChoiceID: ChoiceID = ChoiceID(rawValue: "c1")
    ) -> LearningQuestion {
        LearningQuestion(
            id: QuestionID(rawValue: id),
            level: level,
            questionType: questionType,
            status: status,
            utterances: [ScriptedUtterance(speakerIndex: 0, text: "Selamat pagi.")],
            choices: choices,
            correctChoiceID: correctChoiceID,
            explanation: "説明",
            scenarioIDs: [.airport]
        )
    }
}

/// チェックサムだけが内容と食い違うパックを作る。
private enum BrokenChecksumPack {
    static func make(from pack: LearningContentPack) -> LearningContentPack {
        // 版だけを変えずに、内容を1問減らしたパックのチェックサムを付け替える状況を作る。
        let reduced = LearningContentPack(version: pack.version, questions: Array(pack.questions.dropLast()))
        return LearningContentPack(version: pack.version, questions: pack.questions, checksum: reduced.checksum)
    }
}
