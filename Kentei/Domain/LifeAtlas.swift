import Foundation
import SwiftUI

/// 生活図鑑のカテゴリ。
///
/// E級・D級は空港・ワルン・コンビニ・Grab、C級で生活手続きの9カテゴリを加える。
enum ScenarioID: String, CaseIterable, Codable, Sendable {
    case airport
    case warung
    case convenience
    case grab
    case hospital
    case pharmacy
    case bank
    case simCard
    case delivery
    case housing
    case police
    case government
    case workplace

    /// このカテゴリを主に扱う級。生活図鑑の並びと出題の既定級に使う。
    var level: CertificationLevel {
        switch self {
        case .airport, .warung, .convenience, .grab: .e
        case .hospital, .pharmacy, .bank, .simCard, .delivery,
             .housing, .police, .government, .workplace: .c
        }
    }
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
    /// 実戦チェックの合格も必要か。実際に使えるかを確かめてから解放する行動に付ける。
    let requiresPracticalCheck: Bool

    init(
        id: ActionID,
        titleKey: String,
        requiredQuestionIDs: [QuestionID],
        requiresPracticalCheck: Bool = false
    ) {
        self.id = id
        self.titleKey = titleKey
        self.requiredQuestionIDs = requiredQuestionIDs
        self.requiresPracticalCheck = requiresPracticalCheck
    }
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
    static let version = "atlas-2026-08-v2"

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
        ),

        // --- C級: 生活手続き ---
        cScenario(.hospital, "atlas.hospital", "atlas.hospital.detail", "cross.case.fill", [
            ("hospital.reception", [61]),
            ("hospital.symptom", [62]),
            ("hospital.medication", [63])
        ]),
        cScenario(.pharmacy, "atlas.pharmacy", "atlas.pharmacy.detail", "pills.fill", [
            ("pharmacy.prescription", [64]),
            ("pharmacy.usage", [65]),
            ("pharmacy.sideEffect", [66])
        ]),
        cScenario(.bank, "atlas.bank", "atlas.bank.detail", "banknote.fill", [
            ("bank.account", [67]),
            ("bank.transfer", [68]),
            ("bank.balance", [69])
        ]),
        cScenario(.simCard, "atlas.simCard", "atlas.simCard.detail", "simcard.fill", [
            ("sim.registration", [70]),
            ("sim.topUp", [71]),
            ("sim.plan", [72])
        ]),
        cScenario(.delivery, "atlas.delivery", "atlas.delivery.detail", "shippingbox.fill", [
            ("delivery.redelivery", [73]),
            ("delivery.receipt", [74]),
            ("delivery.tracking", [75])
        ]),
        cScenario(.housing, "atlas.housing", "atlas.housing.detail", "house.fill", [
            ("housing.rent", [76]),
            ("housing.repair", [77]),
            ("housing.contract", [78])
        ]),
        cScenario(.police, "atlas.police", "atlas.police.detail", "shield.lefthalf.filled", [
            ("police.report", [79]),
            ("police.document", [80]),
            ("police.evidence", [81])
        ]),
        cScenario(.government, "atlas.government", "atlas.government.detail", "building.columns.fill", [
            ("government.visa", [82]),
            ("government.document", [83]),
            ("government.queue", [84])
        ]),
        cScenario(.workplace, "atlas.workplace", "atlas.workplace.detail", "briefcase.fill", [
            ("workplace.report", [85]),
            ("workplace.schedule", [86]),
            ("workplace.request", [87])
        ])
    ]

    static func scenario(with id: ScenarioID) -> LifeScenario? {
        scenarios.first { $0.id == id }
    }

    /// C級カテゴリの定義。行動は「行動ID接尾辞」と必要問題番号の組で書く。
    private static func cScenario(
        _ id: ScenarioID,
        _ titleKey: String,
        _ detailKey: String,
        _ systemImage: String,
        _ actions: [(String, [Int])]
    ) -> LifeScenario {
        LifeScenario(
            id: id,
            titleKey: titleKey,
            detailKey: detailKey,
            systemImage: systemImage,
            actions: actions.enumerated().map { index, item in
                // 各カテゴリの最後の行動は、実戦チェックの合格も条件にする。
                action(
                    item.0,
                    "action.\(item.0)",
                    item.1,
                    requiresPracticalCheck: index == actions.count - 1
                )
            }
        )
    }

    private static func action(
        _ id: String,
        _ titleKey: String,
        _ questionNumbers: [Int],
        requiresPracticalCheck: Bool = false
    ) -> LifeAction {
        LifeAction(
            id: ActionID(rawValue: id),
            titleKey: titleKey,
            requiredQuestionIDs: questionNumbers.map { QuestionID(rawValue: "demo-question-\($0)") },
            requiresPracticalCheck: requiresPracticalCheck
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
