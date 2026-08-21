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

    func testStoredSchemaVersionOneRemainsReadable() throws {
        let json = """
        {
          "answers": [
            {
              "answeredAt": "2023-11-14T22:13:20Z",
              "audioPlayCount": 2,
              "choiceID": "demo-question-1-choice-1",
              "isCorrect": true,
              "questionID": "demo-question-1"
            }
          ],
          "contentVersion": "\(DemoLearningContent.version)",
          "phase": "answering",
          "questionIDs": ["demo-question-1"],
          "schemaVersion": 1,
          "sessionID": "00000000-0000-0000-0000-0000000000AA",
          "startedAt": "2023-11-14T22:13:20Z",
          "updatedAt": "2023-11-14T22:13:20Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(LearningSessionSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(snapshot.schemaVersion, LearningSessionSnapshot.currentSchemaVersion)
        XCTAssertEqual(snapshot.answers.count, 1)
        XCTAssertEqual(snapshot.answers[0].questionID, QuestionID(rawValue: "demo-question-1"))
        XCTAssertEqual(snapshot.answers[0].audioPlayCount, 2)
        XCTAssertEqual(snapshot.phase, .answering)
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
            questionIDs: base.questionIDs,
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
            questionIDs: base.questionIDs,
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

    func testRestoreRejectsDifferentQuestionOrder() throws {
        let base = Self.makeSnapshot(answeredCount: 1)
        let snapshot = LearningSessionSnapshot(
            sessionID: base.sessionID,
            contentVersion: base.contentVersion,
            questionIDs: base.questionIDs.reversed(),
            answers: base.answers,
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

    func testRestoreRejectsDuplicatedAnswerForSameQuestion() throws {
        let base = Self.makeSnapshot(answeredCount: 1)
        let duplicated = base.answers + base.answers
        let snapshot = LearningSessionSnapshot(
            sessionID: base.sessionID,
            contentVersion: base.contentVersion,
            questionIDs: base.questionIDs,
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
                .duplicatedAnswer(QuestionID(rawValue: "demo-question-1"))
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
            questionIDs: base.questionIDs,
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

    private static func makeSnapshot(answeredCount: Int) -> LearningSessionSnapshot {
        let pack = DemoLearningContent.pack
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let answers = pack.questions.prefix(answeredCount).map { question in
            AnsweredQuestion(
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
            questionIDs: pack.questions.map(\.id),
            answers: Array(answers),
            phase: .answering,
            startedAt: date,
            updatedAt: date
        )
    }
}
