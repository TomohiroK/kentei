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

/// 種を指定できる乱数生成器。
///
/// 出題順と選択肢順は毎回変える一方で、テスト・プレビューでは同じ並びを再現したい。
/// 本番は `SystemRandomNumberGenerator`、再現が要る場面はこちらを使う。
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // 0 は後続の計算で状態が進まないため、固定値へ寄せる。
        state = seed == 0 ? 0x4d595df4d0f33173 : seed
    }

    mutating func next() -> UInt64 {
        // SplitMix64。短い実装で分布が安定しており、種から同じ並びを再現できる。
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

/// 乱数生成器を値として持ち回すための包み。
///
/// `RandomNumberGenerator` は `mutating` を含むため、そのままでは保持しづらい。
/// 生成器の種類を差し替え可能にしつつ、`shuffled(using:)` へ渡せる形にする。
struct AnyRandomNumberGenerator: RandomNumberGenerator {
    private var base: any RandomNumberGenerator

    init(_ base: any RandomNumberGenerator) {
        self.base = base
    }

    mutating func next() -> UInt64 {
        base.next()
    }
}

protocol RandomGeneratorProviding: Sendable {
    func makeGenerator() -> AnyRandomNumberGenerator
}

struct SystemRandomGeneratorProvider: RandomGeneratorProviding {
    func makeGenerator() -> AnyRandomNumberGenerator {
        AnyRandomNumberGenerator(SystemRandomNumberGenerator())
    }
}

/// 同じ並びを再現したい場面で使う。テストとプレビュー専用。
struct SeededRandomGeneratorProvider: RandomGeneratorProviding {
    let seed: UInt64

    func makeGenerator() -> AnyRandomNumberGenerator {
        AnyRandomNumberGenerator(SeededRandomNumberGenerator(seed: seed))
    }
}
