import Foundation

struct QuestionID: Hashable, Codable, Sendable {
    let rawValue: String
}

struct ChoiceID: Hashable, Codable, Sendable {
    let rawValue: String
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

enum LearningSessionPhase: Equatable, Sendable {
    case answering
    case midpoint
    case finalResult
}

struct LearningSessionState: Equatable, Sendable {
    static let checkpointQuestionCount = 10

    let questions: [LearningQuestion]
    private(set) var phase: LearningSessionPhase = .answering
    private(set) var currentIndex = 0
    private(set) var selectedChoiceID: ChoiceID?
    private(set) var submittedChoiceID: ChoiceID?
    private(set) var answers: [QuestionID: ChoiceID] = [:]
    private(set) var audioPlayCount = 0

    var currentQuestion: LearningQuestion? {
        guard questions.indices.contains(currentIndex) else { return nil }
        return questions[currentIndex]
    }

    var answeredCount: Int {
        answers.count
    }

    var correctCount: Int {
        questions.reduce(into: 0) { count, question in
            guard answers[question.id] == question.correctChoiceID else { return }
            count += 1
        }
    }

    var accuracy: Double {
        guard answeredCount > 0 else { return 0 }
        return Double(correctCount) / Double(answeredCount)
    }

    var isSubmittedAnswerCorrect: Bool {
        guard let question = currentQuestion, let submittedChoiceID else { return false }
        return submittedChoiceID == question.correctChoiceID
    }

    mutating func select(_ choiceID: ChoiceID) {
        guard phase == .answering,
              submittedChoiceID == nil,
              currentQuestion?.choices.contains(where: { $0.id == choiceID }) == true else {
            return
        }
        selectedChoiceID = choiceID
    }

    @discardableResult
    mutating func submit() -> Bool {
        guard phase == .answering,
              submittedChoiceID == nil,
              let question = currentQuestion,
              let selectedChoiceID else {
            return false
        }

        submittedChoiceID = selectedChoiceID
        answers[question.id] = selectedChoiceID
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
        answers = [:]
        audioPlayCount = 0
    }
}

extension LearningSessionState {
    static let demo = LearningSessionState(questions: DemoLearningContent.questions)

    static var demoMidpoint: LearningSessionState {
        var session = demo
        session.answerDemoQuestions(count: checkpointQuestionCount)
        return session
    }

    static var demoFinalResult: LearningSessionState {
        var session = demoMidpoint
        session.continueAfterMidpoint()
        session.answerDemoQuestions(count: 10)
        return session
    }

    private mutating func answerDemoQuestions(count: Int) {
        for _ in 0..<count {
            guard let currentQuestion else { return }
            select(currentQuestion.correctChoiceID)
            submit()
            advance()
        }
    }
}

private enum DemoLearningContent {
    private struct Template: Sendable {
        let transcript: String
        let choices: [String]
        let correctIndex: Int
        let explanation: String
        let scenarioName: String
    }

    private static let templates: [Template] = [
        Template(
            transcript: "Selamat pagi.",
            choices: ["おはようございます", "こんにちは", "おやすみなさい", "ありがとうございます"],
            correctIndex: 0,
            explanation: "Selamat pagi は、朝のあいさつです。",
            scenarioName: "あいさつ"
        ),
        Template(
            transcript: "Saya mau pesan nasi goreng.",
            choices: ["ナシゴレンを注文したいです", "ナシゴレンを作りました", "お会計をお願いします", "辛くしないでください"],
            correctIndex: 0,
            explanation: "mau pesan は「注文したい」という意味です。",
            scenarioName: "ワルン"
        ),
        Template(
            transcript: "Tolong antar saya ke bandara.",
            choices: ["空港まで送ってください", "空港で待ってください", "荷物を預けてください", "ここで降ります"],
            correctIndex: 0,
            explanation: "antar は「送る」、ke bandara は「空港へ」です。",
            scenarioName: "Grab"
        ),
        Template(
            transcript: "Berapa harganya?",
            choices: ["いくらですか", "どこですか", "何時ですか", "いくつありますか"],
            correctIndex: 0,
            explanation: "berapa は数量を尋ね、harganya は「その値段」です。",
            scenarioName: "買い物"
        ),
        Template(
            transcript: "Di mana toiletnya?",
            choices: ["トイレはどこですか", "出口はどこですか", "これは誰のものですか", "何を探していますか"],
            correctIndex: 0,
            explanation: "di mana は場所を尋ねる疑問表現です。",
            scenarioName: "コンビニ"
        )
    ]

    static let questions: [LearningQuestion] = (0..<20).compactMap { index in
        let template = templates[index % templates.count]
        let questionID = QuestionID(rawValue: "demo-question-\(index + 1)")
        let choices = template.choices.enumerated().map { choiceIndex, text in
            LearningChoice(
                id: ChoiceID(rawValue: "demo-question-\(index + 1)-choice-\(choiceIndex + 1)"),
                text: text
            )
        }

        guard choices.indices.contains(template.correctIndex) else { return nil }

        return LearningQuestion(
            id: questionID,
            transcript: template.transcript,
            choices: choices,
            correctChoiceID: choices[template.correctIndex].id,
            explanation: template.explanation,
            scenarioName: template.scenarioName
        )
    }
}
