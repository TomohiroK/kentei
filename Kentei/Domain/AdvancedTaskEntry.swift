import Foundation

/// B級・A級の入口に並べる課題。
///
/// この2つの級に選択式問題は用意しない。作文と発話の自由回答課題で構成する。
/// 入口は常に出し、始められない場合は理由を添える。導線ごと消すと、
/// 利用者からは機能が存在しないように見える。
struct AdvancedTaskEntry: Identifiable, Equatable, Sendable {
    /// 始められない理由。利用者に推測させないため、必ず理由を持たせる。
    enum Availability: Equatable, Sendable {
        case available
        /// 未提供の発話課題に使う互換用の状態。提供済みのローカル練習には使わない。
        case recordingNotAvailable

        var canStart: Bool { self == .available }

        var reasonKey: String? {
            switch self {
            case .available: nil
            case .recordingNotAvailable: "advanced.reason.recording"
            }
        }
    }

    let id: String
    let titleKey: String
    let detailKey: String
    let level: CertificationLevel
    let taskType: AssessmentTaskType
    /// 作文の場合に対応する課題。発話課題は oralTask に対応する。
    let writingTask: WritingTask?
    let availability: Availability
    /// 開始はできるが、先に知らせておくこと。
    ///
    /// 採点サーバーが未設定でも課題は開ける。書くところまで試せるのに
    /// 入口で止めると、機能を確かめる手段がなくなる。
    /// 書いた文章は送れなくても端末に残る。
    let noticeKey: String?
    var oralTask: OralTask? { OralTask.all.first { $0.id == id } }
}

enum AdvancedTaskCatalog {
    /// 入口に並べる級。選択式問題を持たないため `availableLevels` とは別に持つ。
    static let levels: [CertificationLevel] = [.b, .a]

    /// 入口一覧を組み立てる。
    ///
    /// 呼び出しトークンの有無で開始可否を変えない。トークンは開発中の都合であって、
    /// 学習者に入力を求めるものではない。取得できない場合は、書けることは変えずに
    /// 「送信できない」ことだけを添える。
    ///
    /// - Parameter isAssessmentConfigured: 採点へ接続できる状態か。
    static func entries(isAssessmentConfigured: Bool) -> [AdvancedTaskEntry] {
        var entries: [AdvancedTaskEntry] = []

        // 級ごとに、作文を出してから面接を出す。始められるものを先に置く。
        for level in levels {
            for task in DemoWritingTasks.tasks(for: level) {
                entries.append(
                    AdvancedTaskEntry(
                        id: task.id,
                        titleKey: task.titleKey,
                        detailKey: "advanced.writing.detail",
                        level: level,
                        taskType: task.taskType,
                        writingTask: task,
                        availability: .available,
                        noticeKey: isAssessmentConfigured ? nil : "advanced.notice.notConfigured"
                    )
                )
            }

            for task in OralTask.all where task.level == level {
                entries.append(
                    AdvancedTaskEntry(
                        id: task.id,
                        titleKey: task.titleKey,
                        detailKey: task.isInterview ? "interview.detail.\(task.answerMode.rawValue)" : "oral.detail",
                        level: level,
                        taskType: task.type,
                        writingTask: nil,
                        availability: .available,
                        noticeKey: "oral.pendingNotice"
                    )
                )
            }
        }

        return entries
    }

    /// 級ごとにまとめる。表示順は levels の並びに従う。
    static func entriesByLevel(isAssessmentConfigured: Bool) -> [(level: CertificationLevel, entries: [AdvancedTaskEntry])] {
        let all = entries(isAssessmentConfigured: isAssessmentConfigured)
        return levels.compactMap { level in
            let matching = all.filter { $0.level == level }
            return matching.isEmpty ? nil : (level, matching)
        }
    }
}
