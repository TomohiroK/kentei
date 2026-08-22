import XCTest
@testable import Kentei

@MainActor
final class OnboardingTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "kentei-tests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    // MARK: - プロフィールの保存

    func testProfileRoundTripsThroughUserDefaults() throws {
        let store = UserDefaultsLearnerProfileStore(defaults: defaults)
        let profile = LearnerProfile(
            interfaceLanguage: .indonesian,
            purpose: .work,
            targetLevel: .d,
            experience: .conversational,
            completedOnboardingAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        store.save(profile)

        XCTAssertEqual(store.load(), profile)
    }

    func testLoadReturnsNilWhenOnboardingNeverCompleted() {
        let store = UserDefaultsLearnerProfileStore(defaults: defaults)

        XCTAssertNil(store.load())
    }

    func testCorruptedProfileDoesNotBlockLaunch() {
        defaults.set(Data("これはJSONではない".utf8), forKey: UserDefaultsLearnerProfileStore.storageKey)
        let store = UserDefaultsLearnerProfileStore(defaults: defaults)

        XCTAssertNil(store.load(), "壊れた設定値は初回導入からやり直す")
    }

    // MARK: - 初回導入の要否

    func testOnboardingIsRequiredUntilCompleted() {
        let model = AppModel(
            store: DisabledLearningSessionStore(),
            audioPlayer: FakeQuestionAudioPlayer(),
            profileStore: UserDefaultsLearnerProfileStore(defaults: defaults)
        )

        XCTAssertTrue(model.needsOnboarding)

        model.completeOnboarding(with: .preview)

        XCTAssertFalse(model.needsOnboarding)
        XCTAssertEqual(model.learnerProfile, .preview)
    }

    func testCompletedOnboardingIsRestoredOnNextLaunch() {
        let store = UserDefaultsLearnerProfileStore(defaults: defaults)
        let first = AppModel(
            store: DisabledLearningSessionStore(),
            audioPlayer: FakeQuestionAudioPlayer(),
            profileStore: store
        )
        first.completeOnboarding(with: .preview)

        let relaunched = AppModel(
            store: DisabledLearningSessionStore(),
            audioPlayer: FakeQuestionAudioPlayer(),
            profileStore: store
        )

        XCTAssertFalse(relaunched.needsOnboarding, "次回起動で初回導入を繰り返さない")
    }

    func testInterfaceLanguageDrivesLocale() {
        let model = AppModel(
            store: DisabledLearningSessionStore(),
            audioPlayer: FakeQuestionAudioPlayer(),
            profileStore: UserDefaultsLearnerProfileStore(defaults: defaults)
        )

        var profile = LearnerProfile.preview
        profile.interfaceLanguage = .indonesian
        model.completeOnboarding(with: profile)

        XCTAssertEqual(model.interfaceLocale.identifier, "id")
    }

    // MARK: - キャラクター素材

    func testEveryExpressionResolvesToAnAvailableAsset() {
        for expression in CompanionExpression.allCases {
            let assetName = CompanionAssetResolver.assetName(for: expression)
            XCTAssertTrue(
                CompanionAssetResolver.isAvailable(assetName),
                "\(expression.rawValue): 表示できる素材が必要（解決先 \(assetName)）"
            )
        }
    }

    func testMouthOverlayIsOnlyUsedForClosedMouthPoses() {
        XCTAssertTrue(CompanionExpression.normal.supportsMouthOverlay)
        XCTAssertTrue(CompanionExpression.thinking.supportsMouthOverlay)
        XCTAssertFalse(CompanionExpression.happy.supportsMouthOverlay)
        XCTAssertFalse(CompanionExpression.celebrate.supportsMouthOverlay)
    }
}
