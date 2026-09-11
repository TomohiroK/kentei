import Foundation

/// 性能目標の対象。
enum PerformanceMetric: String, CaseIterable, Sendable {
    case questionDisplay
    case audioStart
}

/// 性能目標。運用設定として持ち、判定結果に版を残す。
struct PerformanceBudget: Equatable, Sendable {
    static let current = PerformanceBudget(
        version: "performance-2026-08-v1",
        questionDisplaySeconds: 1.0,
        audioStartSeconds: 0.5
    )

    let version: String
    let questionDisplaySeconds: TimeInterval
    let audioStartSeconds: TimeInterval

    func limit(for metric: PerformanceMetric) -> TimeInterval {
        switch metric {
        case .questionDisplay: questionDisplaySeconds
        case .audioStart: audioStartSeconds
        }
    }

    func isWithinBudget(_ metric: PerformanceMetric, duration: TimeInterval) -> Bool {
        duration <= limit(for: metric)
    }
}

/// 性能の実測値。目標を超えた回数を数え、劣化に気づけるようにする。
@MainActor
@Observable
final class PerformanceRecorder {
    let budget: PerformanceBudget

    private(set) var latestDuration: [PerformanceMetric: TimeInterval] = [:]
    private(set) var exceededCount: [PerformanceMetric: Int] = [:]

    init(budget: PerformanceBudget = .current) {
        self.budget = budget
    }

    func record(_ metric: PerformanceMetric, duration: TimeInterval) {
        guard duration >= 0 else { return }

        latestDuration[metric] = duration
        if budget.isWithinBudget(metric, duration: duration) == false {
            exceededCount[metric, default: 0] += 1
        }
    }

    func isWithinBudget(_ metric: PerformanceMetric) -> Bool {
        guard let duration = latestDuration[metric] else { return true }
        return budget.isWithinBudget(metric, duration: duration)
    }

    var hasExceededAnyBudget: Bool {
        exceededCount.values.contains { $0 > 0 }
    }
}
