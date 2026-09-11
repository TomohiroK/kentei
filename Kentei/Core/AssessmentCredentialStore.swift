import Foundation
import Security

/// 採点中継サーバーの呼び出しトークンの取得元。
///
/// 会員機能ができるまでの暫定であり、会員が使えるかどうかで判定するように
/// なればこの仕組みごと不要になる。
protocol AssessmentCredentialStoring: Sendable {
    func loadToken() -> String?
    func save(token: String)
    func clear()
}

struct KeychainAssessmentCredentialStore: AssessmentCredentialStoring {
    private let service = "com.tomohirok.kentei.assessment"
    private let account = "relay-client-token"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func loadToken() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              token.isEmpty == false else {
            return nil
        }
        return token
    }

    func save(token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            clear()
            return
        }

        // 既存があれば消してから入れる。重複登録を避ける。
        SecItemDelete(baseQuery as CFDictionary)

        var query = baseQuery
        query[kSecValueData as String] = Data(trimmed.utf8)
        // 端末のロック解除後のみ読める。バックアップで他端末へ渡さない。
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

/// テストとプレビュー用。Keychain へ触らない。
final class InMemoryAssessmentCredentialStore: AssessmentCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    init(token: String? = nil) {
        self.token = token
    }

    func loadToken() -> String? {
        lock.withLock { token }
    }

    func save(token: String) {
        lock.withLock { self.token = token.isEmpty ? nil : token }
    }

    func clear() {
        lock.withLock { token = nil }
    }
}

/// アプリに埋め込まれた呼び出しトークン。
///
/// 値はリポジトリに含めない。`Secrets/assessment-token.txt`（追跡対象外）から
/// ビルド時に `AssessmentSecrets.plist` へ書き出したものを読む。
/// ファイルが無い環境では plist ごと存在せず、`nil` を返す。
///
/// 利用者に入力を求めないためにこの形にしている。トークンは開発中の都合であって、
/// 学習者が知る必要のあるものではない。
struct BundledAssessmentCredentialStore: AssessmentCredentialStoring {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func loadToken() -> String? {
        guard let url = bundle.url(forResource: "AssessmentSecrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let token = (values as? [String: Any])?["clientToken"] as? String
        else {
            return nil
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // 埋め込みの値はアプリからは変えられない。
    func save(token: String) {}
    func clear() {}
}

/// 複数の取得元を順に見る保管。
///
/// 埋め込みの値を先に見て、無ければ端末に保存された値を使う。
/// 書き込みは端末側にだけ行う。埋め込みの値を上書きできると、
/// どちらが使われているのか追えなくなる。
struct LayeredAssessmentCredentialStore: AssessmentCredentialStoring {
    private let bundled: any AssessmentCredentialStoring
    private let device: any AssessmentCredentialStoring

    init(
        bundled: any AssessmentCredentialStoring = BundledAssessmentCredentialStore(),
        device: any AssessmentCredentialStoring = KeychainAssessmentCredentialStore()
    ) {
        self.bundled = bundled
        self.device = device
    }

    func loadToken() -> String? {
        bundled.loadToken() ?? device.loadToken()
    }

    func save(token: String) {
        device.save(token: token)
    }

    func clear() {
        device.clear()
    }

    /// トークンがどこから来たか。設定画面で状態を示すために使う。
    var source: AssessmentTokenSource {
        if bundled.loadToken() != nil { return .bundled }
        if device.loadToken() != nil { return .device }
        return .none
    }
}

enum AssessmentTokenSource: Equatable, Sendable {
    /// ビルド時に埋め込まれた値。
    case bundled
    /// 端末に保存された値。
    case device
    case none

    var descriptionKey: String {
        switch self {
        case .bundled: "settings.assessment.source.bundled"
        case .device: "settings.assessment.source.device"
        case .none: "settings.assessment.source.none"
        }
    }
}
