import XCTest
@testable import Kentei

@MainActor
final class OralPracticeTests: XCTestCase {
    func testTopicPassesAfterThreeAnswersAndFailsImmediatelyAtAnyRound() async throws {
        for mode in ["interview-b", "interview-written-a"] {
            for rawScores in [[3, 3, 3], [2], [3, 2], [3, 3, 2]] {
                let task = try XCTUnwrap(OralTask.all.first { $0.id == mode })
                let store = OralMemoryStore()
                let question = InterviewTestPlayer()
                let model = OralTaskModel(task: task, recorder: OralTestRecorder(), store: store,
                    evaluator: InterviewSequenceEvaluator(rawScores: rawScores), sendingEnabled: true, questionPlayer: question)
                model.prepare()
                for index in rawScores.indices {
                    XCTAssertEqual(model.questionIndex, index)
                    XCTAssertFalse(model.hasHeardQuestion)
                    question.request = nil
                    model.playQuestion()
                    try await waitUntil { question.request != nil }
                    XCTAssertEqual(question.request?.text, task.questionText(language: "id", turn: index))
                    question.complete()
                    try await waitUntil { model.hasHeardQuestion }
                    if task.answerMode == .voice {
                        model.start(); try await waitUntil { model.state == .recording }
                        model.stop(); try await waitUntil { model.state == .review }
                    }
                    model.edit("Jawaban contoh nomor \(index).")
                    model.confirmed = true
                    await model.submit()
                    XCTAssertEqual(model.completedTurns.count, index + 1)
                    if index < rawScores.count - 1 {
                        XCTAssertEqual(model.topicOutcome, .followUp)
                        model.advanceInterview()
                        XCTAssertTrue(model.text.isEmpty)
                        XCTAssertFalse(model.confirmed)
                    }
                }
                let expected: OralTaskModel.TopicOutcome = rawScores.last == 3 ? .passed : .failed
                XCTAssertEqual(model.topicOutcome, expected)
                let saved = model.draft
                model.advanceInterview(); model.start(); model.edit("Do not overwrite result")
                XCTAssertEqual(model.draft, saved)
                let restored = OralTaskModel(task: task, recorder: OralTestRecorder(), store: store,
                    evaluator: OralTestEvaluator(), questionPlayer: InterviewTestPlayer())
                restored.prepare()
                XCTAssertEqual(restored.topicOutcome, expected)
                XCTAssertEqual(restored.completedTurns.count, rawScores.count)
            }
        }
    }

    func testAssessmentFailureIsPendingAndRetryRetainsSubmissionID() async throws {
        let task = try XCTUnwrap(OralTask.all.first { $0.id == "interview-written-b" })
        let store = OralMemoryStore()
        let question = InterviewTestPlayer()
        let evaluator = InterviewSequenceEvaluator(rawScores: [3], failsInitially: true)
        let model = OralTaskModel(task: task, recorder: OralTestRecorder(), store: store,
            evaluator: evaluator, sendingEnabled: true, questionPlayer: question)
        model.prepare(); model.playQuestion()
        try await waitUntil { question.request != nil }
        question.complete(); try await waitUntil { model.hasHeardQuestion }
        model.edit("Saya akan menjelaskan alasannya."); model.confirmed = true
        await model.submit()
        XCTAssertNil(model.topicOutcome)
        XCTAssertTrue(model.completedTurns.isEmpty)
        XCTAssertEqual(model.failure, .assessment)
        XCTAssertTrue(model.canSubmit)
        let identifier = model.draft.submission?.id
        await model.submit()
        XCTAssertEqual(model.draft.submission?.id, identifier)
        XCTAssertEqual(model.topicOutcome, .followUp)
        model.advanceInterview()
        let restored = OralTaskModel(task: task, recorder: OralTestRecorder(), store: store,
            evaluator: evaluator, questionPlayer: InterviewTestPlayer())
        restored.prepare()
        XCTAssertEqual(restored.questionIndex, 1)
        XCTAssertEqual(restored.currentJapaneseHint, task.questionText(language: "ja", turn: 1))
        XCTAssertFalse(restored.hasHeardQuestion)
    }

    func testIncompleteScoresCannotBecomeTopicFailure() async throws {
        let task = try XCTUnwrap(OralTask.all.first { $0.id == "interview-written-b" })
        let question = InterviewTestPlayer()
        let model = OralTaskModel(task: task, recorder: OralTestRecorder(), store: OralMemoryStore(),
            evaluator: InterviewSequenceEvaluator(rawScores: [3], malformed: true), sendingEnabled: true, questionPlayer: question)
        model.prepare(); model.playQuestion()
        try await waitUntil { question.request != nil }
        question.complete(); try await waitUntil { model.hasHeardQuestion }
        model.edit("Jawaban lengkap."); model.confirmed = true
        await model.submit()
        XCTAssertNil(model.topicOutcome)
        XCTAssertEqual(model.failure, .assessment)
        XCTAssertTrue(model.completedTurns.isEmpty)
    }

    func testInterviewWrittenAnswerRequiresCompleteQuestionAndNeverRecords() async throws {
        let task = try XCTUnwrap(OralTask.all.first { $0.id == "interview-written-b" })
        let audio = OralTestRecorder()
        let question = InterviewTestPlayer()
        let store = OralMemoryStore()
        let model = OralTaskModel(task: task, recorder: audio, store: store,
            evaluator: OralTestEvaluator(), questionPlayer: question)
        model.prepare(); model.edit("Blocked"); model.start()
        XCTAssertTrue(model.text.isEmpty)
        XCTAssertEqual(audio.starts, 0)
        model.playQuestion()
        try await waitUntil { question.request != nil }
        XCTAssertFalse(model.canAnswer)
        XCTAssertEqual(question.request?.text, task.questionText(language: "id"))
        XCTAssertNotEqual(question.request?.text, task.questionText(language: "ja"))
        question.complete()
        try await waitUntil { model.hasHeardQuestion }
        model.start(); model.edit("Saya akan memberi tahu atasan dan menawarkan jadwal baru.")
        model.confirmed = true
        await model.submit()
        XCTAssertEqual(audio.starts, 0)
        XCTAssertEqual(model.state, .saved)
        XCTAssertEqual(store.draft?.submission?.prompt, task.questionText(language: "id"))
        XCTAssertNil(store.draft?.submission?.audioReference)
    }

    func testInterviewVoiceAnswerStartsAfterQuestionAndProducesTranscript() async throws {
        let task = try XCTUnwrap(OralTask.all.first { $0.id == "interview-a" })
        let audio = OralTestRecorder()
        let question = InterviewTestPlayer()
        let model = OralTaskModel(task: task, recorder: audio, store: OralMemoryStore(),
            evaluator: OralTestEvaluator(), questionPlayer: question)
        model.prepare(); model.start()
        XCTAssertEqual(audio.starts, 0)
        model.playQuestion()
        try await waitUntil { question.request != nil }
        question.complete()
        try await waitUntil { model.hasHeardQuestion }
        XCTAssertFalse(model.canEditAnswer)
        model.start()
        try await waitUntil { model.state == .recording }
        XCTAssertEqual(audio.starts, 1)
        model.playQuestion()
        XCTAssertEqual(model.state, .recording)
        model.stop()
        try await waitUntil { model.state == .review }
        XCTAssertEqual(model.text, "Saya setuju.")
        XCTAssertTrue(model.canEditAnswer)
        XCTAssertFalse(model.confirmed)
        XCTAssertTrue(model.close())
    }

    func testInterruptedAndFailedQuestionsDoNotUnlockAnswers() async throws {
        let task = try XCTUnwrap(OralTask.all.first { $0.id == "interview-b" })
        let question = InterviewTestPlayer()
        let model = OralTaskModel(task: task, recorder: OralTestRecorder(), store: OralMemoryStore(),
            evaluator: OralTestEvaluator(), questionPlayer: question)
        model.prepare(); model.playQuestion()
        try await waitUntil { question.request != nil }
        model.stopQuestion()
        XCTAssertFalse(model.canAnswer)
        question.request = nil
        model.playQuestion()
        try await waitUntil { question.request != nil }
        question.complete(error: QuestionAudioError.voiceUnavailable)
        try await waitUntil { model.failure != nil }
        XCTAssertEqual(model.failure, .questionAudio)
        XCTAssertFalse(model.canAnswer)
        question.request = nil
        model.playQuestion()
        try await waitUntil { question.request != nil }
        XCTAssertTrue(model.suspend(isBackground: true))
        XCTAssertFalse(model.canAnswer)
    }

    func testInterviewModesKeepIndependentDraftsAndLegacyVoiceID() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = FileOralDraftStore(directory: base)
        let legacy = try JSONDecoder().decode(OralDraft.self, from: Data(#"{"text":"Existing voice draft"}"#.utf8))
        try store.save(legacy, taskID: "interview-b")
        try store.save(OralDraft(text: "Written answer"), taskID: "interview-written-b")
        XCTAssertEqual(try store.load(taskID: "interview-b")?.text, "Existing voice draft")
        XCTAssertEqual(try store.load(taskID: "interview-written-b")?.text, "Written answer")
        for level in [CertificationLevel.b, .a] {
            let modes = OralTask.all.filter { $0.level == level && $0.isInterview }.map(\.answerMode)
            XCTAssertEqual(modes, [.voice, .written])
        }
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for interview state")
    }

    func testRecordingRecognitionAndPlaybackState() async throws {
        let audio = OralTestRecorder()
        let store = OralMemoryStore()
        let started = expectation(description: "Recording started")
        let recognized = expectation(description: "Transcript returned")
        audio.onStart = { started.fulfill() }
        audio.onTranscribe = { recognized.fulfill() }
        let model = OralTaskModel(task: try XCTUnwrap(OralTask.all.first), recorder: audio,
                                 store: store, evaluator: OralTestEvaluator())
        model.prepare(); model.start()
        await fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(model.state, .recording)
        XCTAssertTrue(model.hasRecording)
        XCTAssertFalse(model.canSubmit)
        model.stop()
        await fulfillment(of: [recognized], timeout: 2)
        XCTAssertEqual(model.state, .review)
        XCTAssertEqual(store.draft?.text, "Saya setuju.")
        XCTAssertFalse(model.confirmed)
        model.play()
        XCTAssertEqual(audio.plays, 1)
        XCTAssertTrue(model.close())
        XCTAssertFalse(model.hasRecording)
        XCTAssertEqual(store.draft?.text, "Saya setuju.")
    }

    func testPermissionDialogDoesNotCancelButBackgroundDoes() throws {
        let audio = OralTestRecorder()
        let model = OralTaskModel(task: try XCTUnwrap(OralTask.all.first), recorder: audio,
                                 store: OralMemoryStore(), evaluator: OralTestEvaluator())
        model.prepare(); model.start()
        XCTAssertEqual(model.state, .requestingPermission)
        XCTAssertTrue(model.suspend(isBackground: false))
        XCTAssertEqual(model.state, .requestingPermission)
        XCTAssertEqual(audio.discards, 0)
        XCTAssertTrue(model.suspend(isBackground: true))
        XCTAssertEqual(model.state, .review)
        XCTAssertFalse(model.hasRecording)
        XCTAssertEqual(audio.discards, 1)
    }

    func testConfirmedTranscriptIsSavedBeforeSubmissionAndAudioDeleted() async throws {
        let store = OralMemoryStore()
        let audio = OralTestRecorder()
        let evaluator = OralTestEvaluator()
        let task = try XCTUnwrap(OralTask.all.first)
        let model = OralTaskModel(task: task, recorder: audio, store: store, evaluator: evaluator)
        model.prepare()
        model.edit("Saya ingin memperbaiki komunikasi di kantor.")
        await model.submit()
        XCTAssertNil(store.draft?.submission, "Confirmation is required")
        model.confirmed = true
        await model.submit()
        XCTAssertEqual(model.state, .saved)
        XCTAssertNil(store.draft?.submission?.audioReference)
        XCTAssertEqual(store.draft?.submission?.taskType, task.type)
        XCTAssertEqual(audio.discards, 1)
        let calls = await evaluator.calls
        XCTAssertEqual(calls, 0, "Default retention/calibration gate must prevent network calls")
        let restored = OralTaskModel(task: task, recorder: OralTestRecorder(), store: store, evaluator: evaluator)
        restored.prepare()
        XCTAssertEqual(restored.text, model.text)
        XCTAssertFalse(restored.confirmed)
    }

    func testRetryKeepsIdentifierAndPersistenceFailureBlocksEvaluation() async throws {
        let store = OralMemoryStore()
        let audio = OralTestRecorder()
        let evaluator = OralTestEvaluator()
        let task = try XCTUnwrap(OralTask.all.first)
        let model = OralTaskModel(task: task, recorder: audio, store: store, evaluator: evaluator, sendingEnabled: true)
        model.prepare(); model.edit("Saya setuju dengan usulan ini."); model.confirmed = true
        await model.submit()
        let first = store.draft?.submission?.id
        await model.submit()
        XCTAssertEqual(first, store.draft?.submission?.id)
        let identifiers = await evaluator.identifiers
        XCTAssertEqual(identifiers.count, 2)
        XCTAssertEqual(identifiers.first, identifiers.last)
        store.failSave = true
        await model.submit()
        XCTAssertEqual(model.failure, .storage)
        let calls = await evaluator.calls
        XCTAssertEqual(calls, 2)
    }

    func testCleanupFailureBlocksSendingAndRecording() async throws {
        let store = OralMemoryStore()
        let audio = OralTestRecorder()
        audio.failCleanup = true
        let evaluator = OralTestEvaluator()
        let model = OralTaskModel(task: try XCTUnwrap(OralTask.all.first), recorder: audio,
                                 store: store, evaluator: evaluator, sendingEnabled: true)
        model.prepare(); model.start()
        XCTAssertEqual(audio.starts, 0)
        XCTAssertEqual(model.failure, .cleanup)
        XCTAssertFalse(model.close())
    }

    func testDiscardClearsTextAndResult() throws {
        let store = OralMemoryStore()
        let audio = OralTestRecorder()
        let model = OralTaskModel(task: try XCTUnwrap(OralTask.all.first), recorder: audio,
                                 store: store, evaluator: OralTestEvaluator())
        model.prepare(); model.edit("Contoh jawaban."); model.discard()
        XCTAssertNil(store.draft)
        XCTAssertTrue(model.text.isEmpty)
        XCTAssertEqual(audio.discards, 1)
    }

    func testTemporaryAudioCleanupAndDraftRoundTrip() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let files = OralAudioFiles(directory: base.appendingPathComponent("audio"))
        try files.prepare()
        let audio = files.directory.appendingPathComponent("old.m4a")
        try Data([1, 2, 3]).write(to: audio)
        let store = FileOralDraftStore(directory: base.appendingPathComponent("drafts"))
        let task = try XCTUnwrap(OralTask.all.first)
        let draft = OralDraft(text: "Teks pribadi", submission: nil, result: nil)
        try store.save(draft, taskID: task.id)
        try files.prepare()
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
        XCTAssertEqual(try store.load(taskID: task.id), draft)
        XCTAssertEqual(try files.directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        try store.delete(taskID: task.id)
        XCTAssertNil(try store.load(taskID: task.id))
        for task in OralTask.all { try store.save(draft, taskID: task.id) }
        try store.deleteAll()
        for task in OralTask.all { XCTAssertNil(try store.load(taskID: task.id)) }
        XCTAssertThrowsError(try store.load(taskID: "../outside"))
    }

    func testOralRubricsAcceptOnlyTranscriptAndMatchingLevel() throws {
        for task in OralTask.all {
            XCTAssertTrue(RubricValidator().validate(task.rubric).isEmpty)
            let plain = AssessmentSubmission(id: AssessmentID(rawValue: "test"), taskType: task.type,
                level: task.level, rubricID: task.rubric.id, prompt: "Question", text: "Answer", submittedAt: Date())
            XCTAssertNil(SubmissionGate().validate(plain, rubric: task.rubric))
            let audio = AssessmentSubmission(id: plain.id, taskType: plain.taskType, level: plain.level,
                rubricID: plain.rubricID, text: plain.text, audioReference: "", submittedAt: plain.submittedAt)
            XCTAssertEqual(SubmissionGate().validate(audio, rubric: task.rubric), .recordingNotAvailable)
        }
    }
}

@MainActor
private final class InterviewTestPlayer: QuestionAudioPlaying {
    var onSpeechMark: (() -> Void)?
    var request: QuestionAudioRequest?
    private var continuation: CheckedContinuation<Void, any Error>?
    func prepare(_ request: QuestionAudioRequest) {}
    func play(_ request: QuestionAudioRequest) async throws {
        self.request = request
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func stop() { complete() }
    func complete(error: (any Error)? = nil) {
        let pending = continuation
        continuation = nil
        if let error { pending?.resume(throwing: error) } else { pending?.resume() }
    }
}

@MainActor
private final class OralMemoryStore: OralDraftStoring {
    var draft: OralDraft?
    var failSave = false
    func load(taskID: String) throws -> OralDraft? { draft }
    func save(_ draft: OralDraft, taskID: String) throws {
        if failSave { throw OralFailure.storage }
        self.draft = draft
    }
    func delete(taskID: String) throws { draft = nil }
}

@MainActor
private final class OralTestRecorder: OralRecording {
    var onStart: (() -> Void)?
    var onTranscribe: (() -> Void)?
    var plays = 0
    var discards = 0
    var starts = 0
    var failCleanup = false
    func prepare() throws { if failCleanup { throw OralFailure.cleanup } }
    func start() async throws { starts += 1; onStart?() }
    func stop() throws {}
    func transcribe() async throws -> String { onTranscribe?(); return "Saya setuju." }
    func play() throws { plays += 1 }
    func discard() throws {
        if failCleanup { throw OralFailure.cleanup }
        discards += 1
    }
}

private actor OralTestEvaluator: ResponseEvaluating {
    var identifiers: [AssessmentID] = []
    var calls: Int { identifiers.count }
    func evaluate(_ submission: AssessmentSubmission, rubric: Rubric) async throws -> AssessmentResult {
        identifiers.append(submission.id)
        throw AssessmentError.temporaryFailure
    }
}

private actor InterviewSequenceEvaluator: ResponseEvaluating {
    let rawScores: [Int]
    let failsInitially: Bool
    let malformed: Bool
    private var calls = 0
    init(rawScores: [Int], failsInitially: Bool = false, malformed: Bool = false) {
        self.rawScores = rawScores; self.failsInitially = failsInitially; self.malformed = malformed
    }
    func evaluate(_ submission: AssessmentSubmission, rubric: Rubric) async throws -> AssessmentResult {
        calls += 1
        if failsInitially && calls == 1 { throw AssessmentError.temporaryFailure }
        let index = calls - 1 - (failsInitially ? 1 : 0)
        guard rawScores.indices.contains(index) else { throw AssessmentError.temporaryFailure }
        let scores = rubric.criteria.map { CriterionScore(criterionID: $0.id, score: rawScores[index], commentKey: nil) }
        let normalized = rubric.normalizedScore(from: Dictionary(uniqueKeysWithValues: scores.map { ($0.criterionID, $0.score) }))
        return AssessmentResult(submissionID: submission.id, scores: malformed ? Array(scores.dropLast()) : scores,
            overallComment: nil, normalizedScore: normalized, isPassed: normalized >= rubric.passingScore,
            modelVersion: "test-only", rubricVersion: rubric.version, evaluatedAt: Date(), humanReview: .notRequested)
    }
}

final class AdvancedTaskEntryTests: XCTestCase {
    /// 採点サーバーが未設定でも、書くところまでは試せる必要がある。
    /// 課金による制限は設けていない（将来の予定であり、現時点では自由に使える）。
    func testWritingIsOpenEvenWhenTheAssessmentIsNotConfigured() {
        let entries = AdvancedTaskCatalog.entries(isAssessmentConfigured: false)
            .filter { $0.taskType == .writing }

        XCTAssertFalse(entries.isEmpty)
        XCTAssertTrue(entries.allSatisfy(\.availability.canStart), "未設定でも課題は開ける")
        XCTAssertTrue(
            entries.allSatisfy { $0.noticeKey != nil },
            "採点に設定が要ることは、書き始める前に伝える"
        )
    }

    func testNoticeDisappearsOnceConfigured() {
        let entries = AdvancedTaskCatalog.entries(isAssessmentConfigured: true)
            .filter { $0.taskType == .writing }

        XCTAssertTrue(entries.allSatisfy { $0.noticeKey == nil })
    }

    func testEveryUnavailableEntryExplainsWhy() {
        for configured in [true, false] {
            for entry in AdvancedTaskCatalog.entries(isAssessmentConfigured: configured) {
                if entry.availability.canStart {
                    XCTAssertNil(entry.availability.reasonKey, "\(entry.id): 開始できるのに理由がある")
                } else {
                    XCTAssertNotNil(
                        entry.availability.reasonKey,
                        "\(entry.id): 始められない理由を利用者に推測させない"
                    )
                }
            }
        }
    }

    func testEveryAdvancedLevelOffersWritingTasks() {
        for configured in [true, false] {
            let entries = AdvancedTaskCatalog.entries(isAssessmentConfigured: configured)
            for level in AdvancedTaskCatalog.levels {
                let writing = entries.filter { $0.taskType == .writing && $0.level == level }
                XCTAssertEqual(
                    writing.count,
                    DemoWritingTasks.tasks(for: level).count,
                    "\(level.rawValue)級: 作文課題がすべて入口に出る"
                )
                XCTAssertFalse(writing.isEmpty, "\(level.rawValue)級: 作文が1件もない")
                XCTAssertTrue(writing.allSatisfy(\.availability.canStart))
                XCTAssertTrue(writing.allSatisfy { $0.writingTask != nil }, "開始できる課題は実体を持つ")
            }
        }
    }

    func testRecordingTasksOfferLocalPracticeWithoutServerConfiguration() {
        for configured in [true, false] {
            let recording = AdvancedTaskCatalog.entries(isAssessmentConfigured: configured)
                .filter(\.taskType.requiresRecording)

            XCTAssertFalse(recording.isEmpty, "面接の入口は出す")
            XCTAssertTrue(
                recording.allSatisfy { $0.availability.canStart && $0.oralTask != nil },
                "録音課題はローカルで開始できる"
            )
            XCTAssertTrue(recording.allSatisfy { $0.writingTask == nil })
        }
    }

    func testStartableEntriesAlwaysCarryATask() {
        for configured in [true, false] {
            for entry in AdvancedTaskCatalog.entries(isAssessmentConfigured: configured)
            where entry.availability.canStart {
                XCTAssertTrue(entry.writingTask != nil || entry.oralTask != nil, "\(entry.id): 開始できるのに課題がない")
            }
        }
    }

    func testCoversBothAdvancedLevels() {
        let grouped = AdvancedTaskCatalog.entriesByLevel(isAssessmentConfigured: true)

        XCTAssertEqual(grouped.map(\.level), [.b, .a], "B級・A級の順で並べる")
        XCTAssertTrue(grouped.allSatisfy { $0.entries.isEmpty == false })
    }

    func testAdvancedLevelsHaveNoMultipleChoiceContent() {
        // この2つの級に選択式問題は用意しない。級別入口にも出さない。
        for level in AdvancedTaskCatalog.levels {
            XCTAssertFalse(level.isProvided, "\(level.rawValue): 選択式問題は持たない")
            XCTAssertFalse(CertificationLevel.availableLevels.contains(level))
        }
    }

    func testEntryIdentifiersAreUnique() {
        let identifiers = AdvancedTaskCatalog.entries(isAssessmentConfigured: true).map(\.id)
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
    }
}

final class AssessmentTokenSourceTests: XCTestCase {
    /// 同梱の値があれば端末の値より優先する。どちらが使われたか追えるようにする。
    func testBundledTokenTakesPrecedenceOverTheDeviceToken() {
        let store = LayeredAssessmentCredentialStore(
            bundled: InMemoryAssessmentCredentialStore(token: "bundled"),
            device: InMemoryAssessmentCredentialStore(token: "device")
        )

        XCTAssertEqual(store.loadToken(), "bundled")
        XCTAssertEqual(store.source, .bundled)
    }

    func testFallsBackToTheDeviceToken() {
        let store = LayeredAssessmentCredentialStore(
            bundled: InMemoryAssessmentCredentialStore(),
            device: InMemoryAssessmentCredentialStore(token: "device")
        )

        XCTAssertEqual(store.loadToken(), "device")
        XCTAssertEqual(store.source, .device)
    }

    func testReportsWhenNoTokenIsAvailable() {
        let store = LayeredAssessmentCredentialStore(
            bundled: InMemoryAssessmentCredentialStore(),
            device: InMemoryAssessmentCredentialStore()
        )

        XCTAssertNil(store.loadToken())
        XCTAssertEqual(store.source, .none)
    }

    /// 埋め込みの値はアプリから書き換えない。どちらが使われているか追えなくなる。
    func testSavingNeverOverwritesTheBundledToken() {
        let device = InMemoryAssessmentCredentialStore()
        let store = LayeredAssessmentCredentialStore(
            bundled: InMemoryAssessmentCredentialStore(token: "bundled"),
            device: device
        )

        store.save(token: "written")

        XCTAssertEqual(store.loadToken(), "bundled", "同梱の値が使われ続ける")
        XCTAssertEqual(device.loadToken(), "written", "書き込みは端末側にだけ届く")
    }

    /// 同梱の値が無い環境では plist ごと存在せず、読み取りは nil になる。
    func testBundledStoreReturnsNilWhenTheResourceIsMissing() {
        let store = BundledAssessmentCredentialStore(bundle: Bundle(for: AssessmentTokenSourceTests.self))
        XCTAssertNil(store.loadToken())
    }
}
