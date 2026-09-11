import Foundation
import Network

/// 接続状態の監視。
///
/// 学習そのものは同梱教材で完結するため、オフラインでも止めない。
/// 接続状態は未同期回答を送り直す合図としてのみ使う。
@MainActor
@Observable
final class NetworkMonitor {
    /// 起動直後は接続ありとして扱い、判定が来たら更新する。
    private(set) var isOnline = true

    private let pathMonitor = PathMonitorBox()

    init() {
        pathMonitor.start { [weak self] isOnline in
            Task { @MainActor [weak self] in
                self?.isOnline = isOnline
            }
        }
    }
}

/// `NWPathMonitor` の寿命だけを持つ入れ物。
///
/// `@MainActor` の型では nonisolated な `deinit` から監視を止められないため、
/// 停止だけを担う非分離の小さな型に切り出す。
private final class PathMonitorBox: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.tomohirok.kentei.network-monitor")

    func start(_ onChange: @escaping @Sendable (Bool) -> Void) {
        monitor.pathUpdateHandler = { path in
            onChange(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
