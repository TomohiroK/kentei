import Foundation

/// UIの表示言語。日本語とインドネシア語を初回導入で選ぶ。
enum InterfaceLanguage: String, Codable, CaseIterable, Sendable {
    case japanese = "ja"
    case indonesian = "id"

    var localeIdentifier: String {
        rawValue
    }

    /// 端末の設定言語から初期選択を決める。判定できない場合は日本語にする。
    static var systemDefault: InterfaceLanguage {
        let preferred = Locale.preferredLanguages.first ?? "ja"
        return preferred.hasPrefix("id") ? .indonesian : .japanese
    }
}

/// 初回導入で受け取る学習者の前提。出題の重み付けと文言の調整に使う。
struct LearnerProfile: Codable, Equatable, Sendable {
    enum Purpose: String, Codable, CaseIterable, Sendable {
        case certification
        case travel
        case living
        case work
    }

    enum Experience: String, Codable, CaseIterable, Sendable {
        case none
        case beginner
        case conversational
    }

    var interfaceLanguage: InterfaceLanguage
    var purpose: Purpose
    var targetLevel: CertificationLevel
    var experience: Experience
    var completedOnboardingAt: Date

    /// 学習はE級から始める。目標級が上でも、最初のセッションはE級を出す。
    var startingLevel: CertificationLevel {
        .e
    }
}

protocol LearnerProfileStoring: Sendable {
    func load() -> LearnerProfile?
    func save(_ profile: LearnerProfile)
    func clear()
}

/// UserDefaults による保存。学習の進捗とは別の、軽い設定値として扱う。
///
/// `UserDefaults` はスレッドセーフだが `Sendable` を宣言していないため、
/// ここで安全であることを明示する。保持するのは参照のみで、状態は持たない。
struct UserDefaultsLearnerProfileStore: LearnerProfileStoring, @unchecked Sendable {
    static let storageKey = "learner.profile"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> LearnerProfile? {
        guard let data = defaults.data(forKey: Self.storageKey) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // 壊れた設定値で起動を止めない。読めない場合は初回導入からやり直す。
        return try? decoder.decode(LearnerProfile.self, from: data)
    }

    func save(_ profile: LearnerProfile) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(profile) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}

/// UIテストとプレビュー用。保存せず、与えたプロフィールをそのまま返す。
struct StaticLearnerProfileStore: LearnerProfileStoring {
    let profile: LearnerProfile?

    func load() -> LearnerProfile? { profile }
    func save(_ profile: LearnerProfile) {}
    func clear() {}
}

extension LearnerProfile {
    static var preview: LearnerProfile {
        LearnerProfile(
            interfaceLanguage: .japanese,
            purpose: .living,
            targetLevel: .e,
            experience: .beginner,
            completedOnboardingAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
