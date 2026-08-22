import Foundation

/// 教材パックの取得口。
///
/// 配信元（同梱・API・ダウンロード）を差し替えられるようにするための境界。
/// 実サービスとの接続方式は未確定のため、ここではプロトコルだけを定義し、
/// 特定サービスのSDKを持ち込まない。
protocol ContentPackProviding: Sendable {
    func loadPack() async throws -> LearningContentPack
}

/// アプリに同梱した教材を返す実装。
struct BundledContentPackProvider: ContentPackProviding {
    let pack: LearningContentPack

    init(pack: LearningContentPack = DemoLearningContent.pack) {
        self.pack = pack
    }

    func loadPack() async throws -> LearningContentPack {
        pack
    }
}

enum ContentPackActivationError: Error, Equatable {
    /// 自動検査で拒否した。現在の有効版があればそれを保持する。
    case rejected([ContentIssue])
    /// 有効版が無く、代わりに使える教材も無い。
    case noUsablePack([ContentIssue])
}

/// 教材パックの適用。
///
/// 検証を通った版だけを有効にする。検証に落ちた版は適用せず、現在の有効版を保持する。
/// 公開済みの版を上書きせず、新しい版として切り替える。
struct ContentPackActivator: Sendable {
    let validator: ContentPackValidator

    init(validator: ContentPackValidator = ContentPackValidator()) {
        self.validator = validator
    }

    struct Activation: Equatable, Sendable {
        let pack: LearningContentPack
        /// 適用した版で見つかった不備。空でなければ適用していない。
        let rejectedIssues: [ContentIssue]
        let didSwitchVersion: Bool
    }

    func activate(
        candidate: LearningContentPack,
        current: LearningContentPack?
    ) -> Result<Activation, ContentPackActivationError> {
        let issues = validator.validate(candidate)

        guard issues.isEmpty else {
            guard let current else {
                return .failure(.noUsablePack(issues))
            }
            // 検証失敗時は現在の有効版を保持する。
            return .success(Activation(pack: current, rejectedIssues: issues, didSwitchVersion: false))
        }

        return .success(
            Activation(
                pack: candidate,
                rejectedIssues: [],
                didSwitchVersion: current?.version != candidate.version
            )
        )
    }
}
