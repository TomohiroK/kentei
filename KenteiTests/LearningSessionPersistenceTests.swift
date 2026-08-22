import XCTest
@testable import Kentei

final class LearningSessionPersistenceTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "kentei-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
        try super.tearDownWithError()
    }

    private var storeURL: URL {
        temporaryDirectory.appending(path: "session.json", directoryHint: .notDirectory)
    }

    // MARK: - 往復

    func testSaveAndLoadRoundTripPreservesSnapshot() async throws {
        let store = FileLearningSessionStore(fileURL: storeURL)
        let snapshot = Self.makeSnapshot(answeredCount: 3)

        try await store.save(snapshot)
        let loaded = try await store.load()

        XCTAssertEqual(loaded, snapshot)
    }

    func testLoadReturnsNilWhenNothingSaved() async throws {
        let store = FileLearningSessionStore(fileURL: storeURL)

        let loaded = try await store.load()

        XCTAssertNil(loaded)
    }

    func testClearRemovesSavedSession() async throws {
        let store = FileLearningSessionStore(fileURL: storeURL)
        try await store.save(Self.makeSnapshot(answeredCount: 1))

        try await store.clear()

        let loaded = try await store.load()
        XCTAssertNil(loaded)
    }

    func testCorruptedFileIsReportedAsCorrupted() async throws {
        try Data("これはJSONではない".utf8).write(to: storeURL)
        let store = FileLearningSessionStore(fileURL: storeURL)

        do {
            _ = try await store.load()
            XCTFail("破損データが読めてはいけない")
        } catch let error as LearningSessionStoreError {
            XCTAssertEqual(error, .corruptedData)
        }
    }

    // MARK: - 保存形式の互換性契約

    func testSchemaVersionOneMigratesToCanonicalChoiceOrder() throws {
        let pack = DemoLearningContent.pack
        let firstQuestion = try XCTUnwrap(pack.questions.first)
        let questionIDList = pack.questions.prefix(3).map { "\"\($0.id.rawValue)\"" }.joined(separator: ", ")

        // v1 は出題順だけを保存し、選択肢順を持たない。
        let json = """
        {
          "answers": [
            {
              "answeredAt": "2023-11-14T22:13:20Z",
              "audioPlayCount": 2,
              "choiceID": "\(firstQuestion.correctChoiceID.rawValue)",
              "isCorrect": true,
              "questionID": "\(firstQuestion.id.rawValue)"
            }
          ],
          "contentVersion": "\(pack.version)",
          "phase": "answering",
          "questionIDs": [\(questionIDList)],
          "schemaVersion": 1,
          "sessionID": "00000000-0000-0000-0000-0000000000AA",
          "startedAt": "2023-11-14T22:13:20Z",
          "updatedAt": "2023-11-14T22:13:20Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(LearningSessionSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.plan.entries.count, 3)
        XCTAssertNil(snapshot.plan.entries[0].choiceIDs, "v1は選択肢順を持たない")

        let state = try LearningSessionState.restored(from: snapshot, contentPack: pack)

        XCTAssertEqual(state.answeredCount, 1)
        XCTAssertEqual(state.questions.count, 3)
        XCTAssertEqual(
            state.questions[0].choices.map(\.id),
            firstQuestion.choices.map(\.id),
            "選択肢順が無い保存データは教材の原稿順で復帰する"
        )
    }

    func testCurrentSchemaVersionRoundTripsThroughJSON() throws {
        let snapshot = Self.makeSnapshot(answeredCount: 2)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(
            LearningSessionSnapshot.self,
            from: try encoder.encode(snapshot)
        )

        XCTAssertEqual(restored, snapshot)
        XCTAssertEqual(restored.schemaVersion, 2)
        XCTAssertNotNil(restored.plan.entries.first?.choiceIDs, "v2は選択肢順を保存する")
    }

    // MARK: - 復帰

    func testRestoreResumesFromLastCompletedQuestion() throws {
        let snapshot = Self.makeSnapshot(answeredCount: 4)

        let state = try LearningSessionState.restored(from: snapshot, contentPack: DemoLearningContent.pack)

        XCTAssertEqual(state.answeredCount, 4)
        XCTAssertEqual(state.currentIndex, 4, "最後の完了問題の次から再開する")
        XCTAssertNil(state.submittedChoiceID, "未確定の状態を引き継がない")
        XCTAssertNil(state.selectedChoiceID)
        XCTAssertEqual(state.phase, .answering)
    }

    func testRestoreRejectsUnsupportedSchemaVersion() throws {
        let base = Self.makeSnapshot(answeredCount: 1)
        let snapshot = LearningSessionSnapshot(
            schemaVersion: LearningSessionSnapshot.currentSchemaVersion + 1,
            sessionID: base.sessionID,
            contentVersion: base.contentVersion,
            plan: base.plan,
            answers: base.answers,
            phase: base.phase,
            startedAt: base.startedAt,
            updatedAt: base.updatedAt
        )

        XCTAssertThrowsError(
            try LearningSessionState.restored(from: snapshot, contentPack: DemoLearningContent.pack)
        ) { error in
            XCTAssertEqual(
                error as? LearningSessionRestoreFailure,
                .unsupportedSchemaVersion(LearningSessionSnapshot.currentSchemaVersion + 1)
            )
        }
    }

    func testRestoreRejectsDifferentContentVersion() throws {
        let base = Self.makeSnapshot(answeredCount: 1)
        let snapshot = LearningSessionSnapshot(
            sessionID: base.sessionID,
            contentVersion: "another-pack",
            plan: base.plan,
            answers: base.answers,
            phase: base.phase,
            startedAt: base.startedAt,
            updatedAt: base.updatedAt
        )

        XCTAssertThrowsError(
            try LearningSessionState.restored(from: snapshot, contentPack: DemoLearningContent.pack)
        ) { error in
            XCTAssertEqual(
                error as? LearningSessionRestoreFailure,
                .contentVersionMismatch(expected: DemoLearningContent.version, found: "another-pack")
            )
        }
    }

    func testRestoreRejectsPlanReferencingUnknownQuestion() throws {
        let base = Self.makeSnapshot(answeredCount: 1)
        let brokenPlan = LearningSessionPlan(
            entries: [LearningSessionPlan.Entry(questionID: QuestionID(rawValue: "missing"), choiceIDs: nil)]
        )
        let snapshot = LearningSessionSnapshot(
            sessionID: base.sessionID,
            contentVersion: base.contentVersion,
            plan: brokenPlan,
            answers: [],
            phase: base.phase,
            startedAt: base.startedAt,
            updatedAt: base.updatedAt
        )

        XCTAssertThrowsError(
            try LearningSessionState.restored(from: snapshot, contentPack: DemoLearningContent.pack)
        ) { error in
            XCTAssertEqual(error as? LearningSessionRestoreFailure, .questionSetMismatch)
        }
    }

    func testRestorePreservesShuffledChoiceOrder() throws {
        let snapshot = Self.makeSnapshot(answeredCount: 2, seed: 77)

        let state = try LearningSessionState.restored(from: snapshot, contentPack: DemoLearningContent.pack)

        XCTAssertEqual(state.questions.map(\.id), snapshot.plan.questionIDs, "出題順を保って復帰する")
        for (index, entry) in snapshot.plan.entries.enumerated() {
            XCTAssertEqual(
                state.questions[index].choices.map(\.id),
                entry.choiceIDs,
                "選択肢の並びも復帰する"
            )
        }
    }

    func testRestoreRejectsDuplicatedAnswerForSameQuestion() throws {
        let base = Self.makeSnapshot(answeredCount: 1)
        let duplicated = base.answers + base.answers
        let snapshot = LearningSessionSnapshot(
            sessionID: base.sessionID,
            contentVersion: base.contentVersion,
            plan: base.plan,
            answers: duplicated,
            phase: base.phase,
            startedAt: base.startedAt,
            updatedAt: base.updatedAt
        )

        XCTAssertThrowsError(
            try LearningSessionState.restored(from: snapshot, contentPack: DemoLearningContent.pack)
        ) { error in
            XCTAssertEqual(
                error as? LearningSessionRestoreFailure,
                .duplicatedAnswer(base.plan.questionIDs[0])
            )
        }
    }

    func testRestoreRejectsAnswerReferencingUnknownChoice() throws {
        let base = Self.makeSnapshot(answeredCount: 1)
        let brokenAnswer = AnsweredQuestion(
            questionID: base.answers[0].questionID,
            choiceID: ChoiceID(rawValue: "does-not-exist"),
            isCorrect: true,
            answeredAt: base.answers[0].answeredAt,
            audioPlayCount: 0
        )
        let snapshot = LearningSessionSnapshot(
            sessionID: base.sessionID,
            contentVersion: base.contentVersion,
            plan: base.plan,
            answers: [brokenAnswer],
            phase: base.phase,
            startedAt: base.startedAt,
            updatedAt: base.updatedAt
        )

        XCTAssertThrowsError(
            try LearningSessionState.restored(from: snapshot, contentPack: DemoLearningContent.pack)
        ) { error in
            XCTAssertEqual(error as? LearningSessionRestoreFailure, .unknownAnswerReference)
        }
    }

    // MARK: - Helpers

    private static func makeSnapshot(answeredCount: Int, seed: UInt64 = 3) -> LearningSessionSnapshot {
        let pack = DemoLearningContent.pack
        let plan = TestSession.makePlan(seed: seed, pack: pack)
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let answers = plan.entries.prefix(answeredCount).compactMap { entry -> AnsweredQuestion? in
            guard let question = pack.question(with: entry.questionID) else { return nil }
            return AnsweredQuestion(
                questionID: question.id,
                choiceID: question.correctChoiceID,
                isCorrect: true,
                answeredAt: date,
                audioPlayCount: 1
            )
        }

        return LearningSessionSnapshot(
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!,
            contentVersion: pack.version,
            plan: plan,
            answers: Array(answers),
            phase: .answering,
            startedAt: date,
            updatedAt: date
        )
    }
}
