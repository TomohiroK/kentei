import SwiftUI

private enum AppTab: String, Hashable {
    case home
    case learn
    case atlas
    case progress
    case settings
}

struct RootView: View {
    @State private var appModel: AppModel
    @State private var selectedTab: AppTab
    @State private var activeSession: LearningSessionModel?
    @State private var selectedScenario: ScenarioProgress?

    /// UIテスト用の起動引数。永続化を伴わない決まった画面を直接開く。
    private static let scenarioArguments = [
        "-showLearningSession",
        "-showFeedback",
        "-showMidpointResult",
        "-showFinalResult",
        "-showHome"
    ]

    init(appModel: AppModel? = nil) {
        let arguments = ProcessInfo.processInfo.arguments
        let isScenarioLaunch = arguments.contains { Self.scenarioArguments.contains($0) }
        let resolvedModel = appModel ?? Self.makeModel(arguments: arguments, isScenarioLaunch: isScenarioLaunch)

        _appModel = State(initialValue: resolvedModel)
        _selectedTab = State(initialValue: Self.initialTab(arguments: arguments))
        _activeSession = State(
            initialValue: Self.scenarioSession(arguments: arguments, appModel: resolvedModel)
        )
    }

    var body: some View {
        Group {
            if appModel.needsOnboarding {
                OnboardingView(
                    audioPlayer: appModel.sampleAudioPlayer,
                    startingStepIndex: Self.onboardingStepIndex(arguments: ProcessInfo.processInfo.arguments)
                ) { profile in
                    appModel.completeOnboarding(with: profile)
                    startNewSession()
                }
            } else {
                mainTabs
            }
        }
        .environment(\.locale, appModel.interfaceLocale)
        .task {
            if ProcessInfo.processInfo.arguments.contains("-resetLearningData") {
                await appModel.resetStoredLearningData()
            }
            await appModel.refreshMastery()
            await appModel.refreshResumeState()
            presentScenarioDetailIfRequested()
        }
        .fullScreenCover(item: $activeSession, onDismiss: refreshAfterSession) { session in
            LearningSessionContainer(model: session)
        }
        .sheet(item: $selectedScenario) { progress in
            ScenarioDetailView(progress: progress) { scenarioID in
                selectedScenario = nil
                startSession(origin: .scenario(scenarioID))
            }
        }
    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            HomeView(
                resumeState: appModel.resumeState,
                masteredQuestionCount: appModel.masteredQuestionCount,
                reviewDueCount: appModel.reviewDueCount(),
                onStartLearning: startNewSession,
                onResumeLearning: resumeSession
            )
            .tabItem {
                Label("tab.home", systemImage: "house.fill")
            }
            .tag(AppTab.home)

            LearnView(
                reviewDueCount: appModel.reviewDueCount(),
                onStartLearning: startSession(origin:)
            )
                .tabItem {
                    Label("tab.learn", systemImage: "headphones")
                }
                .tag(AppTab.learn)

            ScenarioAtlasView(
                progressList: appModel.scenarioProgressList(),
                totalAchievement: appModel.atlasAchievement(),
                onSelectScenario: { selectedScenario = $0 }
            )
                .tabItem {
                    Label("tab.atlas", systemImage: "map.fill")
                }
                .tag(AppTab.atlas)

            LearningProgressView(
                masteredQuestionCount: appModel.masteredQuestionCount,
                totalQuestionCount: appModel.contentPack.questions.count,
                reviewDueCount: appModel.reviewDueCount(),
                scenarioProgressList: appModel.scenarioProgressList()
            )
                .tabItem {
                    Label("tab.progress", systemImage: "chart.bar.fill")
                }
                .tag(AppTab.progress)

            SettingsView(
                contentPack: appModel.contentPack,
                contentIssueCount: appModel.contentIssues.count
            )
                .tabItem {
                    Label("tab.settings", systemImage: "gearshape.fill")
                }
                .tag(AppTab.settings)
        }
    }

    /// 再開データがあっても、明示的に「最初から」を選んだ場合は新しいセッションで上書きする。
    private func startNewSession() {
        startSession(origin: .recommended)
    }

    /// `-showAtlas` または `-showTab <タブ名>` で最初に開くタブを指定する。画面確認用。
    private static func initialTab(arguments: [String]) -> AppTab {
        if arguments.contains("-showAtlas") {
            return .atlas
        }
        guard let flagIndex = arguments.firstIndex(of: "-showTab"),
              let rawValue = arguments[safe: flagIndex + 1],
              let tab = AppTab(rawValue: rawValue) else {
            return .home
        }
        return tab
    }

    /// `-showScenarioDetail <カテゴリ>` でカテゴリ詳細を直接開く。画面確認用。
    private func presentScenarioDetailIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-showScenarioDetail"),
              let rawValue = arguments[safe: flagIndex + 1],
              let scenarioID = ScenarioID(rawValue: rawValue) else {
            return
        }
        selectedScenario = appModel.scenarioProgressList().first { $0.scenario.id == scenarioID }
    }

    /// 入口ごとに出題の選び方を変える。教材プールは共通。
    private func startSession(origin: LearningSessionOrigin) {
        activeSession = appModel.makeNewSessionModel(origin: origin)
    }

    private func resumeSession() {
        activeSession = appModel.makeResumedSessionModel() ?? appModel.makeNewSessionModel()
    }

    private func refreshAfterSession() {
        Task {
            await appModel.refreshMastery()
            await appModel.refreshResumeState()
        }
    }

    /// 起動引数から依存を組み立てる。
    ///
    /// - `-showXxx`: 決まった画面を撮る起動。保存にも初回導入にも依存させない。
    /// - `-skipOnboarding`: 保存は本物のまま、初回導入だけ済んだ状態にする。
    /// - `-resetLearningData`: 起動時に保存済みの学習データと初回導入の結果を消す。
    private static func makeModel(arguments: [String], isScenarioLaunch: Bool) -> AppModel {
        if isScenarioLaunch {
            return AppModel(
                store: DisabledLearningSessionStore(),
                profileStore: StaticLearnerProfileStore(profile: .preview)
            )
        }

        guard arguments.contains("-skipOnboarding") else {
            return AppModel.live()
        }
        return AppModel.live(profileStore: StaticLearnerProfileStore(profile: .preview))
    }

    /// `-onboardingStep <番号>` で初回導入の途中手順を直接開く。画面確認用。
    private static func onboardingStepIndex(arguments: [String]) -> Int {
        guard let flagIndex = arguments.firstIndex(of: "-onboardingStep"),
              let value = arguments[safe: flagIndex + 1],
              let index = Int(value) else {
            return 0
        }
        return index
    }

    private static func scenarioSession(arguments: [String], appModel: AppModel) -> LearningSessionModel? {
        if arguments.contains("-showFinalResult") {
            return appModel.makeSessionModel(state: .demoFinalResult)
        }
        if arguments.contains("-showMidpointResult") {
            return appModel.makeSessionModel(state: .demoMidpoint)
        }
        if arguments.contains("-showFeedback") {
            return appModel.makeSessionModel(state: .demoAnsweredIncorrectly)
        }
        if arguments.contains("-showLearningSession") {
            return appModel.makeSessionModel(state: .demo)
        }
        return nil
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
