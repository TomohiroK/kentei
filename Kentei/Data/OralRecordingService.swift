import AVFoundation
import Foundation
import Speech

/// All temporary audio lives in one app-owned directory, separate from lesson assets.
struct OralAudioFiles {
    let directory: URL
    init(directory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("OralPracticeAudio", isDirectory: true)) {
        self.directory = directory
    }
    func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        try clear()
    }
    func clear() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

@MainActor
final class OralRecordingService: OralRecording {
    private let files: OralAudioFiles
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var recordingURL: URL?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var continuation: CheckedContinuation<String, any Error>?
    private var timeout: Task<Void, Never>?
    private var recognitionID = UUID()
    private static let recognitionTimeout: Duration = .seconds(45)

    init(files: OralAudioFiles = OralAudioFiles()) { self.files = files }

    func prepare() throws {
        do { try files.prepare() } catch { throw OralFailure.cleanup }
    }

    func start() async throws {
        guard recorder == nil else { return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "id-ID")),
              recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else {
            throw OralFailure.unavailable
        }
        let microphone = await AVAudioApplication.requestRecordPermission()
        try Task.checkCancellation()
        guard microphone else { throw OralFailure.permission }
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status.rawValue)
            }
        }
        try Task.checkCancellation()
        if speech == SFSpeechRecognizerAuthorizationStatus.restricted.rawValue { throw OralFailure.restricted }
        guard speech == SFSpeechRecognizerAuthorizationStatus.authorized.rawValue else { throw OralFailure.permission }
        try discard()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let url = files.directory.appendingPathComponent(UUID().uuidString + ".m4a")
            recordingURL = url
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ])
            self.recorder = recorder
            guard recorder.record() else { throw OralFailure.recording }
        } catch {
            try discard()
            throw OralFailure.recording
        }
    }

    func stop() throws {
        player?.stop()
        player = nil
        recorder?.stop()
        recorder = nil
        do { try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        catch { throw OralFailure.recording }
    }

    func transcribe() async throws -> String {
        guard let url = recordingURL,
              let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "id-ID")),
              recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else {
            throw OralFailure.unavailable
        }
        try Task.checkCancellation()
        let identifier = UUID()
        recognitionID = identifier
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let request = SFSpeechURLRecognitionRequest(url: url)
                request.requiresOnDeviceRecognition = true
                request.shouldReportPartialResults = false
                recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    let text = result?.isFinal == true ? result?.bestTranscription.formattedString : nil
                    let failed = error != nil
                    Task { @MainActor [weak self] in
                        guard self?.recognitionID == identifier else { return }
                        if let text { self?.finish(.success(text)) }
                        else if failed { self?.finish(.failure(OralFailure.recognition)) }
                    }
                }
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: Self.recognitionTimeout) } catch { return }
                    guard self?.recognitionID == identifier else { return }
                    self?.finish(.failure(OralFailure.recognition))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.recognitionID == identifier else { return }
                self?.finish(.failure(CancellationError()))
            }
        }
    }

    private func finish(_ result: Result<String, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        continuation.resume(with: result)
    }

    func play() throws {
        guard let url = recordingURL else { throw OralFailure.recording }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            guard player?.play() == true else { throw OralFailure.recording }
        } catch { throw OralFailure.recording }
    }

    func discard() throws {
        finish(.failure(CancellationError()))
        player?.stop()
        player = nil
        recorder?.stop()
        recorder = nil
        // Even if deactivation fails, delete audio first.
        do { try files.clear() } catch { throw OralFailure.cleanup }
        recordingURL = nil
        do { try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        catch { throw OralFailure.recording }
    }
}

@MainActor
final class FileOralDraftStore: OralDraftStoring {
    private let directory: URL
    init(directory: URL) { self.directory = directory }
    static func live() throws -> FileOralDraftStore {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        return FileOralDraftStore(directory: base.appendingPathComponent("OralPracticeDrafts", isDirectory: true))
    }
    private func url(_ id: String) throws -> URL {
        guard OralTask.all.contains(where: { $0.id == id }) else { throw OralFailure.storage }
        return directory.appendingPathComponent(id + ".json")
    }
    func load(taskID: String) throws -> OralDraft? {
        let path = try url(taskID)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        return try JSONDecoder().decode(OralDraft.self, from: Data(contentsOf: path))
    }
    func save(_ draft: OralDraft, taskID: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(draft).write(to: url(taskID), options: [.atomic, .completeFileProtection])
    }
    func delete(taskID: String) throws {
        let path = try url(taskID)
        if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
    }

    func deleteAll() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: file)
        }
    }
}
