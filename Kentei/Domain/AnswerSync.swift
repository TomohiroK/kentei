import Foundation

/// 回答同期の冪等キー。
///
/// セッション・問題・回答試行を一意に表す。同じ回答を二度送っても、
/// サーバー側で二重登録にならないようにするための識別子である。
struct SyncIdempotencyKey: Hashable, Codable, Sendable {
    let sessionID: UUID
    let questionID: QuestionID
    let attempt: Int

    var rawValue: String {
        "\(sessionID.uuidString)/\(questionID.rawValue)/\(attempt)"
    }
}

/// 未送信の回答。オフラインでもローカルへ積み、再接続後に送る。
struct PendingAnswer: Codable, Equatable, Sendable {
    let key: SyncIdempotencyKey
    let answer: AnsweredQuestion
    let contentVersion: String
    let queuedAt: Date
}

/// 未同期操作キューの保存形式。
struct PendingAnswerQueue: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let pending: [PendingAnswer]

    init(schemaVersion: Int = PendingAnswerQueue.currentSchemaVersion, pending: [PendingAnswer]) {
        self.schemaVersion = schemaVersion
        self.pending = pending
    }
}

enum AnswerSyncError: Error, Equatable {
    /// 送信先が未確定。決定するまで送らず、キューに保持する。
    case backendNotConfigured
    /// 通信できない。再接続後に再試行する。
    case offline
    case server(statusCode: Int)
}

/// 回答の送信口。
///
/// 送信先（バックエンド）は決定ゲートのため、ここではプロトコルだけを定義し、
/// 特定サービスのSDKを持ち込まない。
protocol AnswerSyncing: Sendable {
    /// 冪等キー付きで回答を送り、サーバーが受理したキーを返す。
    func send(_ answers: [PendingAnswer]) async throws -> [SyncIdempotencyKey]
}

/// 送信先が決まるまでの既定実装。送らずにキューを保持する。
struct UnconfiguredAnswerSyncer: AnswerSyncing {
    func send(_ answers: [PendingAnswer]) async throws -> [SyncIdempotencyKey] {
        throw AnswerSyncError.backendNotConfigured
    }
}

/// 同期の結果。
struct AnswerSyncResult: Equatable, Sendable {
    let syncedKeys: [SyncIdempotencyKey]
    let remainingCount: Int
    let failure: AnswerSyncError?

    var didSyncAnything: Bool {
        syncedKeys.isEmpty == false
    }
}
