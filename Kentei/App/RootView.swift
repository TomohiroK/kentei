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
    private static let scenarioArguments = ["-showLearningSession", "-showMidpointResult", "-showFinalResult"]

    init(appModel: AppModel? = nil) {
        let arguments = ProcessInfo.processInfo.arguments
        let isScenarioLaunch = arguments.contains { Self.scenarioArguments.contains($0) }
        let resolvedModel = appModel
            ?? (isScenarioLaunch ? AppModel(store: DisabledLearningSessionStore()) : AppModel.live())

        _appModel = State(initialValue: resolvedModel)
        _selectedTab = State(initialValue: arguments.contains("-showAtlas") ? .atlas : .home)
        _activeSession = State(
            initialValue: Self.scenarioSession(arguments: arguments, appModel: resolvedModel)
        )
    }

    var body: some View {
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
        .task {
            await appModel.refreshResumeState()
        }
        .fullScreenCover(item: $activeSession, onDismiss: refreshResumeState) { session in
            LearningSessionContainer(model: session)
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

    private static func scenarioSession(arguments: [String], appModel: AppModel) -> LearningSessionModel? {
        if arguments.contains("-showFinalResult") {
            return appModel.makeSessionModel(state: .demoFinalResult)
        }
        if arguments.contains("-showMidpointResult") {
            return appModel.makeSessionModel(state: .demoMidpoint)
        }
        if arguments.contains("-showLearningSession") {
            return appModel.makeSessionModel(state: .demo)
        }
        return nil
    }
}
