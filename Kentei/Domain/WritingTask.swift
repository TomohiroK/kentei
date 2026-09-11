import Foundation

/// 記述課題。
///
/// B級・A級に選択式出題は用意せず、記述課題を独立した入口として扱う。
/// スピーチ・面接は OralTask に分離し、作文の基準を流用しない。
struct WritingTask: Identifiable, Equatable, Sendable {
    let id: String
    /// 一覧に出す短い題名の文言キー。
    ///
    /// 設問をそのまま一覧に出すと、資料を含む課題で行が画面を占有する。
    /// 設問は課題画面と採点にだけ使う。
    let titleKey: String
    /// 設問の文言キー。
    let promptKey: String
    /// 書き方の助けになる観点の文言キー。
    let hintKey: String
    /// 模範回答の文言キー。インドネシア語。
    ///
    /// 採点後にだけ見せる。書く前に見せると写して終わりになり、
    /// 何がどう良いのかを考える機会がなくなる。
    let modelAnswerKey: String
    /// 模範回答が各観点でなぜ評価されるかの説明の文言キー。UI言語で書く。
    ///
    /// 良い答案を並べるだけでは、次に自分が何を直せばよいか分からない。
    /// 採点で見られる観点と対応づけて示す。
    let modelAnswerNotesKey: String
    let rubricID: RubricID
    let level: CertificationLevel
    let minimumCharacters: Int

    var taskType: AssessmentTaskType { .writing }
}

enum DemoWritingTasks {
    static let all: [WritingTask] = [
        WritingTask(
            id: "writing-daily-life",
            titleKey: "writing.title.dailyLife",
            promptKey: "writing.task.dailyLife",
            hintKey: "writing.task.dailyLife.hint",
            modelAnswerKey: "writing.model.dailyLife",
            modelAnswerNotesKey: "writing.model.dailyLife.notes",
            rubricID: DemoAssessment.writingRubric.id,
            level: .b,
            minimumCharacters: 60
        ),
        WritingTask(
            id: "writing-work-report",
            titleKey: "writing.title.workReport",
            promptKey: "writing.task.workReport",
            hintKey: "writing.task.workReport.hint",
            modelAnswerKey: "writing.model.workReport",
            modelAnswerNotesKey: "writing.model.workReport.notes",
            rubricID: DemoAssessment.writingRubric.id,
            level: .b,
            minimumCharacters: 60
        ),
        WritingTask(
            id: "writing-a-policy-debate",
            titleKey: "writing.title.policyDebate",
            promptKey: "writing.task.policyDebate",
            hintKey: "writing.task.policyDebate.hint",
            modelAnswerKey: "writing.model.policyDebate",
            modelAnswerNotesKey: "writing.model.policyDebate.notes",
            rubricID: DemoAssessment.writingRubricA.id,
            level: .a,
            minimumCharacters: 250
        ),
        WritingTask(
            id: "writing-a-social-change",
            titleKey: "writing.title.socialChange",
            promptKey: "writing.task.socialChange",
            hintKey: "writing.task.socialChange.hint",
            modelAnswerKey: "writing.model.socialChange",
            modelAnswerNotesKey: "writing.model.socialChange.notes",
            rubricID: DemoAssessment.writingRubricA.id,
            level: .a,
            minimumCharacters: 250
        ),
        WritingTask(
            id: "writing-a-two-sources",
            titleKey: "writing.title.twoSources",
            promptKey: "writing.task.twoSources",
            hintKey: "writing.task.twoSources.hint",
            modelAnswerKey: "writing.model.twoSources",
            modelAnswerNotesKey: "writing.model.twoSources.notes",
            rubricID: DemoAssessment.writingRubricA.id,
            level: .a,
            minimumCharacters: 250
        ),
    ]

    static func task(with id: String) -> WritingTask? {
        all.first { $0.id == id }
    }

    static func tasks(for level: CertificationLevel) -> [WritingTask] {
        all.filter { $0.level == level }
    }
}
