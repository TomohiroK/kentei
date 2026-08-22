import CryptoKit
import Foundation

/// 検定の級。MVPで提供するのはE級とD級のみ。
///
/// C級以上はデータ型として保持するが、未提供機能としてUIへ露出しない。
enum CertificationLevel: String, CaseIterable, Codable, Sendable {
    case e
    case d
    case c
    case b
    case a

    var displayText: String {
        "\(rawValue.uppercased())級"
    }

    var isAvailableInMVP: Bool {
        self == .e || self == .d
    }

    static var availableLevels: [CertificationLevel] {
        allCases.filter(\.isAvailableInMVP)
    }
}

/// 問題形式。MVPで採点できるのは選択式のみ。
enum QuestionType: String, Codable, Sendable {
    case audioMeaningChoice = "audio_meaning_choice"
    case audioImageChoice = "audio_image_choice"
    case responseChoice = "response_choice"
    case grammarFunctionChoice = "grammar_function_choice"
    case ordering
    case fillInBlank = "fill_in_blank"
    case contentMatch = "content_match"
    case actionDecision = "action_decision"
    case speaking
    case summarization
    case relatedWords = "related_words"

    /// 固定問題として即時採点できる形式か。AI評価が要る形式はMVPで出題しない。
    var isDeliverableInMVP: Bool {
        switch self {
        case .audioMeaningChoice, .responseChoice, .contentMatch, .actionDecision:
            true
        case .audioImageChoice, .grammarFunctionChoice, .ordering, .fillInBlank,
             .speaking, .summarization, .relatedWords:
            false
        }
    }
}

/// 誤答を作った理由。無作為な誤答を作らないための記録。
enum DistractorReason: String, Codable, Sendable {
    case similarSound = "similar_sound"
    case semanticNeighbor = "semantic_neighbor"
    case differentAffix = "different_affix"
    case differentPartOfSpeech = "different_part_of_speech"
    case subjectObjectReversed = "subject_object_reversed"
    case wrongPoliteness = "wrong_politeness"
    case wrongContext = "wrong_context"
    case registerConfusion = "register_confusion"
    case knownCommonError = "known_common_error"
}

/// 教材の公開状態。
///
/// `draft → content_review → language_review → audio_review → test_delivery → approved → published`
/// 公開済みは上書きせず、新しい版を作る。`deprecated` は新規セッションへの利用を止めるが、
/// 過去の回答から参照できる状態は保つ。
enum ContentStatus: String, Codable, Sendable {
    case draft
    case contentReview = "content_review"
    case languageReview = "language_review"
    case audioReview = "audio_review"
    case testDelivery = "test_delivery"
    case approved
    case published
    case rejected
    case deprecated

    /// 新規セッションで出題してよいのは公開済みだけ。
    var isDeliverable: Bool {
        self == .published
    }

    /// 過去の回答から参照してよいか。公開を終えた教材も履歴からは見られる。
    var isReferenceable: Bool {
        switch self {
        case .published, .deprecated: true
        default: false
        }
    }
}

// MARK: - 検証

/// 公開前に拒否すべき教材の不備。
enum ContentIssue: Equatable, Sendable {
    case duplicatedQuestionID(QuestionID)
    case missingCorrectChoice(QuestionID)
    case correctChoiceNotInChoices(QuestionID)
    case duplicatedChoiceID(QuestionID)
    case duplicatedChoiceText(QuestionID)
    case tooFewChoices(QuestionID)
    case missingUtterance(QuestionID)
    case missingExplanation(QuestionID)
    case missingScenario(QuestionID)
    case missingDistractorReason(QuestionID)
    case unavailableLevel(QuestionID, CertificationLevel)
    case undeliverableQuestionType(QuestionID, QuestionType)
    case checksumMismatch(expected: String, found: String)
}

/// 教材パックの自動検査。
///
/// 不正な列挙値、欠落した正解、重複、破損チェックサムを公開前に拒否する。
struct ContentPackValidator: Sendable {
    func validate(_ pack: LearningContentPack) -> [ContentIssue] {
        var issues: [ContentIssue] = []
        var seenQuestionIDs: Set<QuestionID> = []

        for question in pack.questions {
            if seenQuestionIDs.insert(question.id).inserted == false {
                issues.append(.duplicatedQuestionID(question.id))
            }
            issues.append(contentsOf: validate(question))
        }

        let checksum = LearningContentPack.checksum(of: pack.questions)
        if checksum != pack.checksum {
            issues.append(.checksumMismatch(expected: pack.checksum, found: checksum))
        }

        return issues
    }

    private func validate(_ question: LearningQuestion) -> [ContentIssue] {
        var issues: [ContentIssue] = []

        if question.choices.count < 2 {
            issues.append(.tooFewChoices(question.id))
        }
        if question.choices.contains(where: { $0.id == question.correctChoiceID }) == false {
            issues.append(.correctChoiceNotInChoices(question.id))
        }
        if question.choices.contains(where: { $0.isCorrect }) == false {
            issues.append(.missingCorrectChoice(question.id))
        }
        if Set(question.choices.map(\.id)).count != question.choices.count {
            issues.append(.duplicatedChoiceID(question.id))
        }
        if Set(question.choices.map(\.text)).count != question.choices.count {
            issues.append(.duplicatedChoiceText(question.id))
        }
        if question.utterances.isEmpty || question.utterances.contains(where: { $0.text.isEmpty }) {
            issues.append(.missingUtterance(question.id))
        }
        if question.explanation.isEmpty {
            issues.append(.missingExplanation(question.id))
        }
        if question.scenarioIDs.isEmpty {
            issues.append(.missingScenario(question.id))
        }
        // 誤答は無作為に作らない。理由の無い誤答は公開しない。
        if question.choices.contains(where: { $0.isCorrect == false && $0.distractorReason == nil }) {
            issues.append(.missingDistractorReason(question.id))
        }
        if question.level.isAvailableInMVP == false {
            issues.append(.unavailableLevel(question.id, question.level))
        }
        if question.questionType.isDeliverableInMVP == false {
            issues.append(.undeliverableQuestionType(question.id, question.questionType))
        }

        return issues
    }
}

extension LearningContentPack {
    /// 教材の内容から決まるチェックサム。内容が1文字でも変われば値が変わる。
    static func checksum(of questions: [LearningQuestion]) -> String {
        var hasher = SHA256()
        for question in questions {
            hasher.update(data: Data(question.checksumSource.utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private extension LearningQuestion {
    /// チェックサムの元になる正規化文字列。並び順を含めて内容を表す。
    var checksumSource: String {
        let utteranceText = utterances.map { "\($0.speakerIndex):\($0.text)" }.joined(separator: "|")
        let choiceText = choices.map { "\($0.id.rawValue)=\($0.text)#\($0.isCorrect)" }.joined(separator: "|")
        let scenarioText = scenarioIDs.map(\.rawValue).joined(separator: ",")
        return [
            id.rawValue,
            level.rawValue,
            questionType.rawValue,
            status.rawValue,
            utteranceText,
            choiceText,
            correctChoiceID.rawValue,
            explanation,
            scenarioText
        ].joined(separator: "\u{1F}")
    }
}
