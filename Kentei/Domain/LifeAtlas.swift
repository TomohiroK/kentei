import Foundation
import SwiftUI

/// 生活図鑑のカテゴリ。MVPは空港・ワルン・コンビニ・Grabの4つ。
enum ScenarioID: String, CaseIterable, Codable, Sendable {
    case airport
    case warung
    case convenience
    case grab
}

struct ActionID: Hashable, Sendable, RawRepresentable, Codable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// 生活図鑑の「できること」。解放条件は関連問題の習得状況で判定する。
struct LifeAction: Identifiable, Equatable, Sendable {
    let id: ActionID
    /// 表示名の文言キー。行動名は文言カタログで管理する。
    let titleKey: String
    /// 解放に必要な関連問題。判定根拠として画面にも示す。
    let requiredQuestionIDs: [QuestionID]
}

struct LifeScenario: Identifiable, Equatable, Sendable {
    let id: ScenarioID
    let titleKey: String
    let detailKey: String
    let systemImage: String
    let actions: [LifeAction]

    /// 級別入口と生活図鑑入口で同じ教材を使うため、問題の紐付けは教材側のタグを正とする。
    func questionIDs(in pack: LearningContentPack) -> [QuestionID] {
        pack.questions.filter { $0.scenarioIDs.contains(id) }.map(\.id)
    }
}

/// 生活図鑑の定義。行動と必要問題の紐付けをここで一元管理する。
enum DemoLifeAtlas {
    /// 行動と必要問題の対応を変えたら版を上げる。判定結果に記録して根拠を再現できるようにする。
    static let version = "atlas-2026-08-v1"

    static let scenarios: [LifeScenario] = [
        LifeScenario(
            id: .airport,
            titleKey: "atlas.airport",
            detailKey: "atlas.airport.detail",
            systemImage: "airplane.departure",
            actions: [
                action("airport.checkin", "action.airport.checkin", [35, 21, 19]),
                action("airport.askHelp", "action.airport.askHelp", [7, 8, 19]),
                action("airport.time", "action.airport.time", [13, 18, 40]),
                action("airport.greeting", "action.airport.greeting", [1, 29, 4])
            ]
        ),
        LifeScenario(
            id: .warung,
            titleKey: "atlas.warung",
            detailKey: "atlas.warung.detail",
            systemImage: "fork.knife",
            actions: [
                action("warung.order", "action.warung.order", [5, 31]),
                action("warung.adjust", "action.warung.adjust", [36, 25]),
                action("warung.takeaway", "action.warung.takeaway", [11, 12]),
                action("warung.smallTalk", "action.warung.smallTalk", [2, 24, 38])
            ]
        ),
        LifeScenario(
            id: .convenience,
            titleKey: "atlas.convenience",
            detailKey: "atlas.convenience.detail",
            systemImage: "basket.fill",
            actions: [
                action("convenience.price", "action.convenience.price", [3, 9]),
                action("convenience.payment", "action.convenience.payment", [20, 27, 34]),
                action("convenience.trouble", "action.convenience.trouble", [14, 26]),
                action("convenience.askInStore", "action.convenience.askInStore", [4, 10, 33, 39])
            ]
        ),
        LifeScenario(
            id: .grab,
            titleKey: "atlas.grab",
            detailKey: "atlas.grab.detail",
            systemImage: "car.fill",
            actions: [
                action("grab.destination", "action.grab.destination", [6, 32]),
                action("grab.duration", "action.grab.duration", [16, 23]),
                action("grab.request", "action.grab.request", [15, 22, 28]),
                action("grab.stay", "action.grab.stay", [17, 37, 30])
            ]
        )
    ]

    static func scenario(with id: ScenarioID) -> LifeScenario? {
        scenarios.first { $0.id == id }
    }

    private static func action(_ id: String, _ titleKey: String, _ questionNumbers: [Int]) -> LifeAction {
        LifeAction(
            id: ActionID(rawValue: id),
            titleKey: titleKey,
            requiredQuestionIDs: questionNumbers.map { QuestionID(rawValue: "demo-question-\($0)") }
        )
    }
}

extension LearningQuestion {
    /// 問題が属するカテゴリの表示名。生活図鑑の定義を正とする。
    var scenarioTitleKey: LocalizedStringKey? {
        guard let id = primaryScenarioID, let scenario = DemoLifeAtlas.scenario(with: id) else { return nil }
        return LocalizedStringKey(scenario.titleKey)
    }
}
