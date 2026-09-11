import Foundation
import Speech

/// 端末の音声認識能力。
///
/// 録音した音声を端末の外へ出さずに文字起こしできるかは、
/// プライバシー設計と送信先の選定を左右するため、実測して扱う。
struct SpeechRecognitionCapability: Equatable, Sendable {
    let localeIdentifier: String
    let isSupported: Bool
    let isAvailable: Bool
    /// 端末内だけで認識できるか。false の場合、認識のために音声が端末外へ送られる。
    let supportsOnDeviceRecognition: Bool

    static func current(for localeIdentifier: String) -> SpeechRecognitionCapability {
        let locale = Locale(identifier: localeIdentifier)
        let isSupported = SFSpeechRecognizer.supportedLocales()
            .contains { $0.identifier == locale.identifier }

        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            return SpeechRecognitionCapability(
                localeIdentifier: localeIdentifier,
                isSupported: isSupported,
                isAvailable: false,
                supportsOnDeviceRecognition: false
            )
        }

        return SpeechRecognitionCapability(
            localeIdentifier: localeIdentifier,
            isSupported: isSupported,
            isAvailable: recognizer.isAvailable,
            supportsOnDeviceRecognition: recognizer.supportsOnDeviceRecognition
        )
    }

    var summary: String {
        "\(localeIdentifier): supported=\(isSupported) available=\(isAvailable) onDevice=\(supportsOnDeviceRecognition)"
    }
}
