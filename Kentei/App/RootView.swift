import SwiftUI

private enum AppTab: Hashable {
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

    /// UIテスト用の起動引数。永続化を伴わない決まった画面を直接開く。
    private static let scenarioArguments = [
        "-showLearningSession",
        "-showFeedback",
        "-showMidpointResult",
        "-showFinalResult",
        "-showHome",
        "-showAtlas"
    ]

    init(appModel: AppModel? = nil) {
        let arguments = ProcessInfo.processInfo.arguments
        let isScenarioLaunch = arguments.contains { Self.scenarioArguments.contains($0) }
        let resolvedModel = appModel ?? Self.makeModel(arguments: arguments, isScenarioLaunch: isScenarioLaunch)

        _appModel = State(initialValue: resolvedModel)
        _selectedTab = State(initialValue: arguments.contains("-showAtlas") ? .atlas : .home)
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
            await appModel.refreshResumeState()
        }
        .fullScreenCover(item: $activeSession, onDismiss: refreshResumeState) { session in
            LearningSessionContainer(model: session)
        }
    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            HomeView(
                resumeState: appModel.resumeState,
                onStartLearning: startNewSession,
                onResumeLearning: resumeSession
            )
            .tabItem {
                Label("tab.home", systemImage: "house.fill")
            }
            .tag(AppTab.home)

            LearnView(onStartLearning: startNewSession)
                .tabItem {
                    Label("tab.learn", systemImage: "headphones")
                }
                .tag(AppTab.learn)

            ScenarioAtlasView()
                .tabItem {
                    Label("tab.atlas", systemImage: "map.fill")
                }
                .tag(AppTab.atlas)

            LearningProgressView()
                .tabItem {
                    Label("tab.progress", systemImage: "chart.bar.fill")
                }
                .tag(AppTab.progress)

            SettingsView()
                .tabItem {
                    Label("tab.settings", systemImage: "gearshape.fill")
                }
                .tag(AppTab.settings)
        }
    }

    /// 再開データがあっても、明示的に「最初から」を選んだ場合は新しいセッションで上書きする。
    private func startNewSession() {
        activeSession = appModel.makeNewSessionModel()
    }

    private func resumeSession() {
        activeSession = appModel.makeResumedSessionModel() ?? appModel.makeNewSessionModel()
    }

    private func refreshResumeState() {
        Task {
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
