import Foundation

protocol LearningSessionStoring: Sendable {
    /// 保存済みセッションを読み出す。保存が無い場合は `nil` を返す。
    func load() async throws -> LearningSessionSnapshot?
    func save(_ snapshot: LearningSessionSnapshot) async throws
    func clear() async throws
}

enum LearningSessionStoreError: Error, Equatable {
    /// 保存ファイルが存在するが復号できない。呼び出し側は破棄して新規開始する。
    case corruptedData
}

/// JSONファイルによるセッション永続化。
///
/// 書き込みはアトミックに行い、途中でプロセスが落ちても半端なファイルを残さない。
actor FileLearningSessionStore: LearningSessionStoring {
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

    /// 既定の保存先。バックアップ対象外にはせず、端末移行で学習途中を引き継げるようにする。
    static func defaultFileURL(fileManager: FileManager = .default) throws -> URL {
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return baseURL
            .appending(path: "LearningSessions", directoryHint: .isDirectory)
            .appending(path: "current-session.json", directoryHint: .notDirectory)
    }

    func load() async throws -> LearningSessionSnapshot? {
        guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        do {
            return try decoder.decode(LearningSessionSnapshot.self, from: data)
        } catch {
            throw LearningSessionStoreError.corruptedData
        }
    }

    func save(_ snapshot: LearningSessionSnapshot) async throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directoryURL.path(percentEncoded: false)) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    func clear() async throws {
        guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return }
        try fileManager.removeItem(at: fileURL)
    }
}

/// 保存先を用意できない環境向けのフォールバック。保存は行わず、復帰もしない。
struct DisabledLearningSessionStore: LearningSessionStoring {
    func load() async throws -> LearningSessionSnapshot? { nil }
    func save(_ snapshot: LearningSessionSnapshot) async throws {}
    func clear() async throws {}
}
