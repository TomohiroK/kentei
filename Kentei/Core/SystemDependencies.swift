import Foundation

/// 時刻・識別子・永続化はプロトコル経由で注入し、テストから決定的に差し替えられるようにする。
protocol SessionClock: Sendable {
    func now() -> Date
}

struct SystemSessionClock: SessionClock {
    func now() -> Date {
        Date()
    }
}

protocol IdentifierGenerating: Sendable {
    func newIdentifier() -> UUID
}

struct SystemIdentifierGenerator: IdentifierGenerating {
    func newIdentifier() -> UUID {
        UUID()
    }
}
