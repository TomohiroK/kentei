import SwiftUI

@main
struct KenteiApp: App {
    init() {
        Self.reportSpeechCapabilityIfRequested()
        Self.reportSpeechAccuracyIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(KenteiTheme.brandPrimary)
        }
    }

    /// `-reportSpeechAccuracy` で、端末内音声認識の誤り率を測って出力する。
    /// 接辞や受動を含む文をどれだけ取りこぼすかを、実データで判断するために使う。
    private static func reportSpeechAccuracyIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-reportSpeechAccuracy") else { return }

        // 接辞・受動を含むC級の文を中心に測る。
        let sentences = [
            "Selamat pagi.",
            "Silakan didaftarkan dulu di loket pendaftaran.",
            "Obatnya harus diminum setelah makan.",
            "Kontraknya diperpanjang otomatis kalau tidak dibatalkan.",
            "Laporannya dikumpulkan paling lambat hari Jumat.",
            "Perpanjangan visanya diurus di kantor imigrasi."
        ]

        Task {
            let report = await SpeechAccuracyProbe.run(sentences: sentences)
            print("[accuracy] 端末内認識=\(report.usedOnDeviceRecognition) 計測できた文=\(report.measuredSamples.count)/\(report.samples.count)")
            fflush(stdout)
            for sample in report.samples {
                if let recognized = sample.recognized, let rate = sample.wordErrorRate {
                    print("[accuracy] WER=\(String(format: "%.2f", rate)) 期待=\(sample.expected) 認識=\(recognized)")
                } else {
                    print("[accuracy] 失敗=\(sample.failure ?? "不明") 期待=\(sample.expected)")
                }
            }
            if let overall = report.overallWordErrorRate {
                print("[accuracy] 全体WER=\(String(format: "%.3f", overall))")
            }
            print("[accuracy] 計測終了")
            fflush(stdout)
        }
    }

    /// `-reportSpeechCapability` で、この端末の音声認識能力を出力する。
    /// 録音を端末外へ出さずに文字起こしできるかを実機で確認するために使う。
    private static func reportSpeechCapabilityIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-reportSpeechCapability") else { return }

        for localeIdentifier in ["id-ID", "ja-JP", "en-US"] {
            print("[speech] \(SpeechRecognitionCapability.current(for: localeIdentifier).summary)")
        }
    }
}

