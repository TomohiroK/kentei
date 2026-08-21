import Foundation

/// 再生速度。E級のみ 0.8 倍を許容し、記録上の基準は常に標準速度とする。
enum PlaybackRate: Double, CaseIterable, Codable, Sendable {
    case slow = 0.8
    case standard = 1.0

    var displayText: String {
        switch self {
        case .slow: "0.8×"
        case .standard: "1.0×"
        }
    }
}

/// 1問分の音声再生要求。
///
/// 教材が実音声アセットを持つまでは `text` を読み上げる。実音声が入ったら
/// `assetName` を追加して同じプロトコルの別実装へ差し替える。
struct QuestionAudioRequest: Equatable, Sendable {
    let questionID: QuestionID
    let text: String
    /// 会話形式の問題で話者を切り替えるための指定。単独発話は 0。
    let speakerIndex: Int
    let rate: PlaybackRate

    init(questionID: QuestionID, text: String, speakerIndex: Int = 0, rate: PlaybackRate) {
        self.questionID = questionID
        self.text = text
        self.speakerIndex = speakerIndex
        self.rate = rate
    }
}

enum QuestionAudioError: Error, Equatable {
    /// 端末にインドネシア語の音声が用意されていない。
    case voiceUnavailable
    /// 電話・Siri・音声経路変更などで再生が中断された。
    case interrupted
    case sessionUnavailable
}

@MainActor
protocol QuestionAudioPlaying: AnyObject {
    /// 発話が1区切り進むたびに呼ばれる。キャラクターの口の動きを音声へ同期させるために使う。
    var onSpeechMark: (() -> Void)? { get set }

    /// 再生が完了するまで待つ。キャンセル時は中断として扱い、例外を投げずに戻る。
    func play(_ request: QuestionAudioRequest) async throws
    /// 次問の音声を用意する。合成音声では何もしないが、実音声アセットでは先読みに使う。
    func prepare(_ request: QuestionAudioRequest)
    func stop()
}
