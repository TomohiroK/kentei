import Foundation

/// 学習設定の保存キー。画面ごとに文字列を書かず、ここだけを正とする。
enum LearningPreferenceKey {
    static let playbackRate = "learning.playbackRate"
    static let autoplay = "learning.autoplay"
    static let haptics = "learning.haptics"
    static let reducedEffects = "learning.reducedEffects"
}
