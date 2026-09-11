import Foundation

protocol PendingAnswerStoring: Sendable {
    func load() async throws -> PendingAnswerQueue?
    func save(_ queue: PendingAnswerQueue) async throws
    func clear() async throws
}

/// 未同期の回答をJSONファイルへ保持する。
actor FilePendingAnswerStore: PendingAnswerStoring {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    static func defaultFileURL(fileManager: FileManager = .default) throws -> URL {
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return baseURL
            .appending(path: "LearningSessions", directoryHint: .isDirectory)
            .appending(path: "pending-answers.json", directoryHint: .notDirectory)
    }

    func load() async throws -> PendingAnswerQueue? {
        guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return nil }

        let data = try Data(contentsOf: fileURL)
        let queue: PendingAnswerQueue
        do {
            queue = try decoder.decode(PendingAnswerQueue.self, from: data)
        } catch {
            throw LearningSessionStoreError.corruptedData
        }

        guard queue.schemaVersion == PendingAnswerQueue.currentSchemaVersion else { return nil }
        return queue
    }

    func save(_ queue: PendingAnswerQueue) async throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directoryURL.path(percentEncoded: false)) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        try encoder.encode(queue).write(to: fileURL, options: [.atomic])
    }

    func clear() async throws {
        guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return }
        try fileManager.removeItem(at: fileURL)
    }
}

struct DisabledPendingAnswerStore: PendingAnswerStoring {
    func load() async throws -> PendingAnswerQueue? { nil }
    func save(_ queue: PendingAnswerQueue) async throws {}
    func clear() async throws {}
}

/// 未同期回答のキュー。
///
/// オフラインでも回答を積み、再接続後にまとめて送る。同じ冪等キーは二度積まず、
/// サーバーが受理したキーだけをキューから外す。これにより二重送信と二重進捗を防ぐ。
actor AnswerSyncQueue {
    private let store: any PendingAnswerStoring
    private var pending: [PendingAnswer] = []
    private var isLoaded = false

    init(store: any PendingAnswerStoring) {
        self.store = store
    }

    var pendingCount: Int {
        pending.count
    }

    func load() async {
        guard isLoaded == false else { return }
        isLoaded = true
        // 壊れたキューで学習を止めない。読めない場合は空から始める。
        pending = ((try? await store.load()) ?? nil)?.pending ?? []
    }

    /// 回答を積む。既に同じ冪等キーがある場合は積み直さない。
    func enqueue(_ answer: PendingAnswer) async {
        await load()
        guard pending.contains(where: { $0.key == answer.key }) == false else { return }
        pending.append(answer)
        try? await store.save(PendingAnswerQueue(pending: pending))
    }

    /// 送信を試みる。受理されたキーだけを外し、残りは次の機会に再送する。
    @discardableResult
    func flush(using syncer: any AnswerSyncing) async -> AnswerSyncResult {
        await load()

        guard pending.isEmpty == false else {
            return AnswerSyncResult(syncedKeys: [], remainingCount: 0, failure: nil)
        }

        do {
            let acceptedKeys = try await syncer.send(pending)
            let accepted = Set(acceptedKeys)
            pending.removeAll { accepted.contains($0.key) }
            try? await store.save(PendingAnswerQueue(pending: pending))
            return AnswerSyncResult(
                syncedKeys: acceptedKeys,
                remainingCount: pending.count,
                failure: nil
            )
        } catch {
            // 送信できない回答は消さない。ローカル保存済みのまま次の接続を待つ。
            return AnswerSyncResult(
                syncedKeys: [],
                remainingCount: pending.count,
                failure: error as? AnswerSyncError ?? .offline
            )
        }
    }

    func clear() async {
        pending = []
        isLoaded = true
        try? await store.clear()
    }
}
