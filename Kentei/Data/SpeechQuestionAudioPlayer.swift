import AVFoundation
import Foundation

/// 端末内の音声合成でインドネシア語を読み上げる暫定実装。
///
/// 教材の正式音声（2話者の録音）が確定するまでの代替であり、合成音声を
/// 基準記録として扱わない。実音声アセットが入ったら `QuestionAudioPlaying` の
/// 別実装へ差し替える。
@MainActor
final class SpeechQuestionAudioPlayer: NSObject, QuestionAudioPlaying {
    var onSpeechMark: (() -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private let audioSession: AVAudioSession
    private var activeContinuation: CheckedContinuation<Void, any Error>?
    private let interruptionObserver = NotificationObserverToken()

    /// 話者を切り替えるための音声候補。端末に存在するものだけを使う。
    private static let voiceIdentifiers = ["id-ID"]

    init(audioSession: AVAudioSession = .sharedInstance()) {
        self.audioSession = audioSession
        super.init()
        synthesizer.delegate = self
        observeInterruptions()
    }

    func play(_ request: QuestionAudioRequest) async throws {
        stop()

        guard let voice = Self.voice(for: request.speakerIndex) else {
            throw QuestionAudioError.voiceUnavailable
        }

        do {
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true)
        } catch {
            throw QuestionAudioError.sessionUnavailable
        }

        let utterance = AVSpeechUtterance(string: request.text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(request.rate.rawValue)
        utterance.postUtteranceDelay = 0

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                activeContinuation = continuation
                synthesizer.speak(utterance)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.stop()
            }
        }
    }

    func prepare(_ request: QuestionAudioRequest) {
        // 合成音声は事前生成を必要としない。実音声アセット実装での先読み用の口だけ用意する。
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        finishActiveUtterance(with: nil)
    }

    private func observeInterruptions() {
        interruptionObserver.token = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] notification in
            guard let rawValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: rawValue),
                  type == .began else {
                return
            }
            MainActor.assumeIsolated {
                self?.handleInterruption()
            }
        }
    }

    private func handleInterruption() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        finishActiveUtterance(with: QuestionAudioError.interrupted)
    }

    private func finishActiveUtterance(with error: (any Error)?) {
        guard let continuation = activeContinuation else { return }
        activeContinuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    private static func voice(for speakerIndex: Int) -> AVSpeechSynthesisVoice? {
        let available = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("id") }
            .sorted { $0.identifier < $1.identifier }

        if available.isEmpty {
            return voiceIdentifiers.lazy.compactMap(AVSpeechSynthesisVoice.init(language:)).first
        }
        return available[speakerIndex % available.count]
    }
}

extension SpeechQuestionAudioPlayer: AVSpeechSynthesizerDelegate {
    /// 語を話し始めるたびに通知が来る。これをキャラクターの口の動きの拍として使う。
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.onSpeechMark?()
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.finishActiveUtterance(with: nil)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.finishActiveUtterance(with: nil)
        }
    }
}

/// 監視トークンの寿命だけを持つ入れ物。
///
/// `@MainActor` の型では nonisolated な `deinit` からトークンへ触れないため、
/// 解除だけを担う非分離の小さな型に切り出す。トークンは生成時と破棄時にしか触らない。
private final class NotificationObserverToken: @unchecked Sendable {
    var token: (any NSObjectProtocol)?

    deinit {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
