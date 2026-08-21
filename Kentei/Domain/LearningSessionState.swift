import Foundation

struct QuestionID: Hashable, Sendable, RawRepresentable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

struct ChoiceID: Hashable, Sendable, RawRepresentable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// 保存データを読みやすく保つため、識別子は入れ子オブジェクトではなく素の文字列として符号化する。
extension QuestionID: Codable {
    init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension ChoiceID: Codable {
    init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct LearningChoice: Identifiable, Equatable, Sendable {
    let id: ChoiceID
    let text: String
}

struct LearningQuestion: Identifiable, Equatable, Sendable {
    let id: QuestionID
    let transcript: String
    let choices: [LearningChoice]
    let correctChoiceID: ChoiceID
    let explanation: String
    let scenarioName: String
}

/// バージョン付きの教材パック。版が変わった保存データは復帰対象にしない。
struct LearningContentPack: Equatable, Sendable {
    let version: String
    let questions: [LearningQuestion]
}

enum LearningSessionPhase: Equatable, Sendable {
    case answering
    case midpoint
    case finalResult
}

struct LearningSessionState: Equatable, Sendable {
    static let checkpointQuestionCount = 10

    let contentVersion: String
    let questions: [LearningQuestion]
    private(set) var phase: LearningSessionPhase = .answering
    private(set) var currentIndex = 0
    private(set) var selectedChoiceID: ChoiceID?
    private(set) var submittedChoiceID: ChoiceID?
    /// 回答順を保った回答イベント。1問につき最大1件だけ保持し、再送で重複を作らない。
    private(set) var answers: [AnsweredQuestion] = []
    private(set) var audioPlayCount = 0

    init(contentPack: LearningContentPack) {
        contentVersion = contentPack.version
        questions = contentPack.questions
    }

    var currentQuestion: LearningQuestion? {
        guard questions.indices.contains(currentIndex) else { return nil }
        return questions[currentIndex]
    }

    var answeredCount: Int {
        answers.count
    }

    var correctCount: Int {
        answers.count(where: { $0.isCorrect })
    }

    var accuracy: Double {
        guard answeredCount > 0 else { return 0 }
        return Double(correctCount) / Double(answeredCount)
    }

    var isSubmittedAnswerCorrect: Bool {
        guard let question = currentQuestion, let submittedChoiceID else { return false }
        return submittedChoiceID == question.correctChoiceID
    }

    /// 中間結果までの区間で正解した数。総合結果でも中間区間の実績を再現できるようにする。
    var correctCountUpToCheckpoint: Int {
        answers.prefix(Self.checkpointQuestionCount).count(where: { $0.isCorrect })
    }

    func answeredChoiceID(for questionID: QuestionID) -> ChoiceID? {
        answers.first { $0.questionID == questionID }?.choiceID
    }

    mutating func select(_ choiceID: ChoiceID) {
        guard phase == .answering,
              submittedChoiceID == nil,
              currentQuestion?.choices.contains(where: { $0.id == choiceID }) == true else {
            return
        }
        selectedChoiceID = choiceID
    }

    /// 回答を確定する。確定済み・未選択・同一問題の二重回答は無視し、`false` を返す。
    @discardableResult
    mutating func submit(at date: Date) -> Bool {
        guard phase == .answering,
              submittedChoiceID == nil,
              let question = currentQuestion,
              let selectedChoiceID,
              answeredChoiceID(for: question.id) == nil else {
            return false
        }

        submittedChoiceID = selectedChoiceID
        answers.append(
            AnsweredQuestion(
                questionID: question.id,
                choiceID: selectedChoiceID,
                isCorrect: selectedChoiceID == question.correctChoiceID,
                answeredAt: date,
                audioPlayCount: audioPlayCount
            )
        )
        return true
    }

    mutating func registerAudioPlayback() {
        guard phase == .answering else { return }
        audioPlayCount += 1
    }

    mutating func advance() {
        guard phase == .answering, submittedChoiceID != nil else { return }

        if answeredCount >= questions.count {
            phase = .finalResult
            return
        }

        currentIndex = answeredCount
        selectedChoiceID = nil
        submittedChoiceID = nil
        audioPlayCount = 0

        if answeredCount == Self.checkpointQuestionCount {
            phase = .midpoint
        }
    }

    mutating func continueAfterMidpoint() {
        guard phase == .midpoint else { return }
        phase = .answering
    }

    mutating func restart() {
        phase = .answering
        currentIndex = 0
        selectedChoiceID = nil
        submittedChoiceID = nil
        answers = []
        audioPlayCount = 0
    }
}

// MARK: - 保存と復帰

extension LearningSessionState {
    func snapshot(sessionID: UUID, startedAt: Date, updatedAt: Date) -> LearningSessionSnapshot {
        LearningSessionSnapshot(
            sessionID: sessionID,
            contentVersion: contentVersion,
            questionIDs: questions.map(\.id),
            answers: answers,
            phase: LearningSessionSnapshot.Phase(phase),
            startedAt: startedAt,
            updatedAt: updatedAt
        )
    }

    /// 保存データを現行教材へ復帰する。
    ///
    /// 未確定の選択は復帰させない。回答直後に保存された確定回答だけを引き継ぐことで、
    /// 途中離脱後の再開が同じ問題を二重に回答しない状態から始まるようにする。
    static func restored(
        from snapshot: LearningSessionSnapshot,
        contentPack: LearningContentPack
    ) throws -> LearningSessionState {
        guard snapshot.schemaVersion == LearningSessionSnapshot.currentSchemaVersion else {
            throw LearningSessionRestoreFailure.unsupportedSchemaVersion(snapshot.schemaVersion)
        }
        guard snapshot.contentVersion == contentPack.version else {
            throw LearningSessionRestoreFailure.contentVersionMismatch(
                expected: contentPack.version,
                found: snapshot.contentVersion
            )
        }
        guard snapshot.questionIDs == contentPack.questions.map(\.id) else {
            throw LearningSessionRestoreFailure.questionSetMismatch
        }
        guard snapshot.answers.count <= contentPack.questions.count else {
            throw LearningSessionRestoreFailure.questionSetMismatch
        }

        var seenQuestionIDs: Set<QuestionID> = []
        for answer in snapshot.answers {
            guard let question = contentPack.questions.first(where: { $0.id == answer.questionID }),
                  question.choices.contains(where: { $0.id == answer.choiceID }) else {
                throw LearningSessionRestoreFailure.unknownAnswerReference
            }
            guard seenQuestionIDs.insert(answer.questionID).inserted else {
                throw LearningSessionRestoreFailure.duplicatedAnswer(answer.questionID)
            }
        }

        var state = LearningSessionState(contentPack: contentPack)
        state.answers = snapshot.answers
        state.phase = snapshot.phase.domainPhase
        state.currentIndex = min(snapshot.answers.count, max(contentPack.questions.count - 1, 0))
        return state
    }
}

private extension LearningSessionSnapshot.Phase {
    init(_ phase: LearningSessionPhase) {
        switch phase {
        case .answering: self = .answering
        case .midpoint: self = .midpoint
        case .finalResult: self = .finalResult
        }
    }

    var domainPhase: LearningSessionPhase {
        switch self {
        case .answering: .answering
        case .midpoint: .midpoint
        case .finalResult: .finalResult
        }
    }
}

// MARK: - プロトタイプ教材

extension LearningSessionState {
    static var demo: LearningSessionState {
        LearningSessionState(contentPack: DemoLearningContent.pack)
    }

    /// UIテスト・プレビュー用に、指定数まで正解で埋めた状態を作る。
    static func demo(answeringCorrectly count: Int, at date: Date = Date(timeIntervalSince1970: 0)) -> LearningSessionState {
        var session = demo
        for _ in 0..<count {
            guard let question = session.currentQuestion else { break }
            session.select(question.correctChoiceID)
            session.submit(at: date)
            session.advance()
            if session.phase == .midpoint {
                session.continueAfterMidpoint()
            }
        }
        return session
    }

    static var demoMidpoint: LearningSessionState {
        var session = demo(answeringCorrectly: checkpointQuestionCount)
        session.phase = .midpoint
        return session
    }

    static var demoFinalResult: LearningSessionState {
        demo(answeringCorrectly: DemoLearningContent.questions.count)
    }
}

enum DemoLearningContent {
    /// 教材を差し替えたら版を上げる。版が変わると保存済みセッションは復帰せず破棄される。
    static let version = "demo-2026-08-v2"

    static var pack: LearningContentPack {
        LearningContentPack(version: version, questions: questions)
    }

    /// 出題1件の原稿。`choices` の先頭を正解として書き、表示位置は `correctPositions` で散らす。
    private struct Template: Sendable {
        let transcript: String
        /// 先頭が正解。残りは誤答で、いずれも聞き分けの理由がある選択肢にする。
        let choices: [String]
        let explanation: String
        let scenarioName: String
    }

    /// 正解の表示位置。特定の位置に正解が偏ると、聞き取らずに当てられてしまう。
    private static let correctPositions = [0, 2, 1, 3, 2, 0, 3, 1, 0, 2, 3, 1, 2, 0, 1, 3, 0, 2, 1, 3]

    private static let templates: [Template] = [
        Template(
            transcript: "Selamat pagi.",
            choices: ["おはようございます", "こんばんは", "おやすみなさい", "さようなら"],
            explanation: "selamat はあいさつの頭に付き、pagi は朝を指します。",
            scenarioName: "あいさつ"
        ),
        Template(
            transcript: "Terima kasih banyak.",
            choices: ["本当にありがとうございます", "どういたしまして", "すみません", "お願いします"],
            explanation: "terima kasih が「ありがとう」、banyak が「たくさん」で感謝を強めます。",
            scenarioName: "あいさつ"
        ),
        Template(
            transcript: "Berapa harganya?",
            choices: ["いくらですか", "どこですか", "何時ですか", "いくつありますか"],
            explanation: "berapa は数量や値段を尋ね、harganya は「その値段」です。",
            scenarioName: "買い物"
        ),
        Template(
            transcript: "Di mana toilet?",
            choices: ["トイレはどこですか", "トイレは使えますか", "トイレは何時までですか", "トイレは新しいですか"],
            explanation: "di mana は場所を尋ねる表現です。",
            scenarioName: "コンビニ"
        ),
        Template(
            transcript: "Saya mau pesan nasi goreng.",
            choices: ["ナシゴレンを注文したいです", "ナシゴレンを作りました", "ナシゴレンは辛いですか", "ナシゴレンが好きです"],
            explanation: "mau は「〜したい」、pesan は「注文する」です。",
            scenarioName: "ワルン"
        ),
        Template(
            transcript: "Tolong antar saya ke bandara.",
            choices: ["空港まで送ってください", "空港で待っていてください", "空港はどこですか", "空港まで歩きます"],
            explanation: "tolong は依頼、antar は「送る」、ke bandara は「空港へ」です。",
            scenarioName: "Grab"
        ),
        Template(
            transcript: "Saya tidak mengerti.",
            choices: ["わかりません", "知っています", "聞こえています", "話せます"],
            explanation: "tidak は否定、mengerti は「理解する」です。",
            scenarioName: "あいさつ"
        ),
        Template(
            transcript: "Bisa bicara pelan-pelan?",
            choices: ["ゆっくり話してもらえますか", "大きい声で話してください", "もう一度書いてください", "英語で話せますか"],
            explanation: "pelan-pelan は「ゆっくり」。bisa は可能を尋ねます。",
            scenarioName: "あいさつ"
        ),
        Template(
            transcript: "Ini terlalu mahal.",
            choices: ["これは高すぎます", "これは安いです", "これは新しいです", "これは重いです"],
            explanation: "terlalu は「〜すぎる」、mahal は「高い」です。",
            scenarioName: "買い物"
        ),
        Template(
            transcript: "Boleh saya lihat?",
            choices: ["見てもいいですか", "買ってもいいですか", "持って帰ってもいいですか", "使ってもいいですか"],
            explanation: "boleh は許可を尋ね、lihat は「見る」です。",
            scenarioName: "買い物"
        ),
        Template(
            transcript: "Tolong bungkus untuk dibawa pulang.",
            choices: ["持ち帰り用に包んでください", "ここで食べます", "袋はいりません", "温めてください"],
            explanation: "bungkus は「包む」、dibawa pulang は「持ち帰る」です。",
            scenarioName: "ワルン"
        ),
        Template(
            transcript: "Saya alergi udang.",
            choices: ["エビのアレルギーがあります", "エビが好きです", "エビを追加してください", "エビは高いです"],
            explanation: "alergi はアレルギー、udang はエビです。",
            scenarioName: "ワルン"
        ),
        Template(
            transcript: "Jam berapa sekarang?",
            choices: ["今何時ですか", "何時に始まりますか", "どのくらいかかりますか", "いつ行きますか"],
            explanation: "jam berapa は時刻を尋ね、sekarang は「今」です。",
            scenarioName: "あいさつ"
        ),
        Template(
            transcript: "Kartu saya tidak bisa dipakai.",
            choices: ["私のカードが使えません", "私のカードをなくしました", "カードで払います", "カードはありますか"],
            explanation: "dipakai は「使われる」。tidak bisa で「〜できない」です。",
            scenarioName: "コンビニ"
        ),
        Template(
            transcript: "Tolong panggil taksi.",
            choices: ["タクシーを呼んでください", "タクシーはどこですか", "タクシーで行きます", "タクシーは高いです"],
            explanation: "panggil は「呼ぶ」です。",
            scenarioName: "Grab"
        ),
        Template(
            transcript: "Berapa lama perjalanannya?",
            choices: ["移動はどのくらいかかりますか", "いくらかかりますか", "何時に着きますか", "どこへ行きますか"],
            explanation: "berapa lama は所要時間、perjalanan は「移動・道のり」です。",
            scenarioName: "Grab"
        ),
        Template(
            transcript: "Saya menginap di hotel dekat sini.",
            choices: ["この近くのホテルに泊まっています", "この近くのホテルを探しています", "ホテルは遠いです", "ホテルまで歩きます"],
            explanation: "menginap は「宿泊する」、dekat sini は「この近く」です。",
            scenarioName: "Grab"
        ),
        Template(
            transcript: "Tolong tunggu sebentar.",
            choices: ["少し待ってください", "急いでください", "また来てください", "先に行ってください"],
            explanation: "tunggu は「待つ」、sebentar は「少しの間」です。",
            scenarioName: "空港"
        ),
        Template(
            transcript: "Ada yang bisa berbahasa Inggris?",
            choices: ["英語が話せる人はいますか", "英語で書いてください", "英語のメニューはありますか", "英語を勉強しています"],
            explanation: "ada yang bisa は「〜できる人がいる」、berbahasa Inggris は「英語を話す」です。",
            scenarioName: "空港"
        ),
        Template(
            transcript: "Saya mau bayar dengan kartu.",
            choices: ["カードで払いたいです", "現金で払います", "領収書をください", "両替したいです"],
            explanation: "bayar は「払う」、dengan kartu は「カードで」です。",
            scenarioName: "コンビニ"
        )
    ]

    static let questions: [LearningQuestion] = templates.enumerated().compactMap { index, template in
        let questionNumber = index + 1
        let questionID = QuestionID(rawValue: "demo-question-\(questionNumber)")

        // 選択肢のIDは原稿の並び順に固定し、表示順だけを入れ替える。
        // こうすると正解の位置を変えても、保存済み回答の参照が壊れない。
        let authored = template.choices.enumerated().map { choiceIndex, text in
            LearningChoice(
                id: ChoiceID(rawValue: "demo-question-\(questionNumber)-choice-\(choiceIndex + 1)"),
                text: text
            )
        }

        guard let correctChoice = authored.first,
              correctPositions.indices.contains(index) else {
            return nil
        }

        let offset = correctPositions[index] % authored.count
        let displayed = (0..<authored.count).map { position in
            authored[(position - offset + authored.count) % authored.count]
        }

        return LearningQuestion(
            id: questionID,
            transcript: template.transcript,
            choices: displayed,
            correctChoiceID: correctChoice.id,
            explanation: template.explanation,
            scenarioName: template.scenarioName
        )
    }
}
