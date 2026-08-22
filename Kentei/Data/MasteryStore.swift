import Foundation

/// 習得記録の保存形式。
///
/// 保存形式・キー・列挙値は互換性契約である。変更時は `currentSchemaVersion` を上げ、
/// 旧バージョンの読込テストを同じ変更で追加する。
struct MasteryRecords: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    /// 判定に使った設定の版。係数変更前後の説明可能性を保つ。
    let settingsVersion: String
    let records: [QuestionMastery]

    init(
        schemaVersion: Int = MasteryRecords.currentSchemaVersion,
        settingsVersion: String = MasteryScoringSettings.current.version,
        records: [QuestionMastery]
    ) {
        self.schemaVersion = schemaVersion
        self.settingsVersion = settingsVersion
        self.records = records
    }

    var byQuestionID: [QuestionID: QuestionMastery] {
        Dictionary(records.map { ($0.questionID, $0) }, uniquingKeysWith: { _, latest in latest })
    }
}

protocol MasteryStoring: Sendable {
    func load() async throws -> MasteryRecords?
    func save(_ records: MasteryRecords) async throws
    func clear() async throws
}

/// JSONファイルによる習得記録の永続化。セッションの保存とは別ファイルにする。
actor FileMasteryStore: MasteryStoring {
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
            .appending(path: "mastery.json", directoryHint: .notDirectory)
    }

    func load() async throws -> MasteryRecords? {
        guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return nil }

        let data = try Data(contentsOf: fileURL)
        let records: MasteryRecords
        do {
            records = try decoder.decode(MasteryRecords.self, from: data)
        } catch {
            throw LearningSessionStoreError.corruptedData
        }

        guard records.schemaVersion == MasteryRecords.currentSchemaVersion else {
            // 対応外の版は捨てる。誤った習得判定で行動を解放しない。
            return nil
        }
        return records
    }

    func save(_ records: MasteryRecords) async throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directoryURL.path(percentEncoded: false)) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        try encoder.encode(records).write(to: fileURL, options: [.atomic])
    }

    func clear() async throws {
        guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return }
        try fileManager.removeItem(at: fileURL)
    }
}

/// 保存先を用意できない環境向けのフォールバック。
struct DisabledMasteryStore: MasteryStoring {
    func load() async throws -> MasteryRecords? { nil }
    func save(_ records: MasteryRecords) async throws {}
    func clear() async throws {}
}
