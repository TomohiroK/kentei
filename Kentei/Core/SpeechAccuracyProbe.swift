import AVFoundation
import Foundation
import Speech

/// 端末内音声認識の精度を測る診断。
///
/// 教材の文を合成音声で読み上げ、それを認識して元の文と比べる。
/// 合成音声は人の発話より聞き取りやすいため、ここで出る誤り率は**下限**であり、
/// 実際の学習者の発話ではこれより悪くなる。「合成音声ですら落とす」ことの検出に使う。
enum SpeechAccuracyProbe {
    struct Sample: Sendable {
        let expected: String
        let recognized: String?
        let failure: String?

        var wordErrorRate: Double? {
            guard let recognized else { return nil }
            return SpeechAccuracyProbe.wordErrorRate(expected: expected, recognized: recognized)
        }
    }

    struct Report: Sendable {
        let samples: [Sample]
        let usedOnDeviceRecognition: Bool

        var measuredSamples: [Sample] {
            samples.filter { $0.recognized != nil }
        }

        /// 全文をまとめた単語誤り率。
        var overallWordErrorRate: Double? {
            let rates = measuredSamples.compactMap(\.wordErrorRate)
            guard rates.isEmpty == false else { return nil }
            return rates.reduce(0, +) / Double(rates.count)
        }
    }

    static func run(
        sentences: [String],
        localeIdentifier: String = "id-ID",
        requiresOnDeviceRecognition: Bool = true
    ) async -> Report {
        guard await requestAuthorization() else {
            return Report(
                samples: sentences.map { Sample(expected: $0, recognized: nil, failure: "認証が得られていない") },
                usedOnDeviceRecognition: requiresOnDeviceRecognition
            )
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
              recognizer.isAvailable else {
            return Report(
                samples: sentences.map { Sample(expected: $0, recognized: nil, failure: "認識器を使えない") },
                usedOnDeviceRecognition: requiresOnDeviceRecognition
            )
        }

        var samples: [Sample] = []
        for sentence in sentences {
            samples.append(
                await measure(
                    sentence: sentence,
                    recognizer: recognizer,
                    localeIdentifier: localeIdentifier,
                    requiresOnDeviceRecognition: requiresOnDeviceRecognition
                )
            )
        }

        return Report(samples: samples, usedOnDeviceRecognition: requiresOnDeviceRecognition)
    }

    // MARK: - 1文の計測

    private static func measure(
        sentence: String,
        recognizer: SFSpeechRecognizer,
        localeIdentifier: String,
        requiresOnDeviceRecognition: Bool
    ) async -> Sample {
        do {
            let audioURL = try await synthesize(sentence, localeIdentifier: localeIdentifier)
            defer { try? FileManager.default.removeItem(at: audioURL) }

            let request = SFSpeechURLRecognitionRequest(url: audioURL)
            request.requiresOnDeviceRecognition = requiresOnDeviceRecognition
            request.shouldReportPartialResults = false

            let recognized = try await recognize(request: request, using: recognizer)
            return Sample(expected: sentence, recognized: recognized, failure: nil)
        } catch {
            return Sample(expected: sentence, recognized: nil, failure: String(describing: error))
        }
    }

    struct ProbeTimeout: Error {}

    private static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private static func recognize(
        request: SFSpeechURLRecognitionRequest,
        using recognizer: SFSpeechRecognizer
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            // 認識結果は一度だけ返す。継続の二重呼び出しを避けるため状態を持つ。
            let hasResumed = ResumeGuard()
            // 応答が返らないまま止まらないよう期限を設ける。
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                if hasResumed.claim() {
                    continuation.resume(throwing: ProbeTimeout())
                }
            }
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    if hasResumed.claim() {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let result, result.isFinal else { return }
                if hasResumed.claim() {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }

    /// 合成音声をファイルへ書き出す。
    private static func synthesize(_ text: String, localeIdentifier: String) async throws -> URL {
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: localeIdentifier)

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "probe-\(UUID().uuidString).caf", directoryHint: .notDirectory)

        return try await withCheckedThrowingContinuation { continuation in
            let writer = AudioFileWriter(url: url)
            DispatchQueue.global().asyncAfter(deadline: .now() + 20) {
                writer.failIfUnfinished(continuation: continuation, error: ProbeTimeout())
            }
            synthesizer.write(utterance) { buffer in
                guard let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }
                if pcmBuffer.frameLength == 0 {
                    // 空バッファが終端の合図。
                    writer.finish(continuation: continuation)
                    return
                }
                writer.append(pcmBuffer, continuation: continuation)
            }
        }
    }

    // MARK: - 単語誤り率

    static func wordErrorRate(expected: String, recognized: String) -> Double {
        let expectedWords = normalize(expected)
        let recognizedWords = normalize(recognized)
        guard expectedWords.isEmpty == false else { return recognizedWords.isEmpty ? 0 : 1 }

        return Double(editDistance(expectedWords, recognizedWords)) / Double(expectedWords.count)
    }

    private static func normalize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.isEmpty == false }
    }

    private static func editDistance(_ lhs: [String], _ rhs: [String]) -> Int {
        var previous = Array(0...rhs.count)
        var current = [Int](repeating: 0, count: rhs.count + 1)

        for (i, left) in lhs.enumerated() {
            current[0] = i + 1
            for (j, right) in rhs.enumerated() {
                let substitution = previous[j] + (left == right ? 0 : 1)
                current[j + 1] = min(substitution, previous[j + 1] + 1, current[j] + 1)
            }
            previous = current
        }
        return previous[rhs.count]
    }
}

/// 継続を一度だけ再開させるための小さな門番。
private final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false

    func claim() -> Bool {
        lock.withLock {
            guard hasResumed == false else { return false }
            hasResumed = true
            return true
        }
    }
}

/// 合成音声のバッファをファイルへ書き出す入れ物。
private final class AudioFileWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL
    private var file: AVAudioFile?
    private var hasFinished = false

    init(url: URL) {
        self.url = url
    }

    func append(_ buffer: AVAudioPCMBuffer, continuation: CheckedContinuation<URL, any Error>) {
        lock.withLock {
            guard hasFinished == false else { return }
            do {
                if file == nil {
                    file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
                }
                try file?.write(from: buffer)
            } catch {
                hasFinished = true
                continuation.resume(throwing: error)
            }
        }
    }

    func failIfUnfinished(continuation: CheckedContinuation<URL, any Error>, error: any Error) {
        lock.withLock {
            guard hasFinished == false else { return }
            hasFinished = true
            file = nil
            continuation.resume(throwing: error)
        }
    }

    func finish(continuation: CheckedContinuation<URL, any Error>) {
        lock.withLock {
            guard hasFinished == false else { return }
            hasFinished = true
            file = nil
            continuation.resume(returning: url)
        }
    }
}
