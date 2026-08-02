import SwiftUI

private enum AppTab: Hashable {
    case home
    case learn
    case atlas
    case progress
    case settings
}

struct RootView: View {
    @State private var selectedTab: AppTab = .home
    @State private var isShowingSession: Bool
    private let initialSession: LearningSessionState

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        _selectedTab = State(initialValue: arguments.contains("-showAtlas") ? .atlas : .home)
        let showsSession = arguments.contains("-showLearningSession")
            || arguments.contains("-showMidpointResult")
            || arguments.contains("-showFinalResult")

        _isShowingSession = State(initialValue: showsSession)

        if arguments.contains("-showFinalResult") {
            initialSession = .demoFinalResult
        } else if arguments.contains("-showMidpointResult") {
            initialSession = .demoMidpoint
        } else {
            initialSession = .demo
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView {
                isShowingSession = true
            }
            .tabItem {
                Label("tab.home", systemImage: "house.fill")
            }
            .tag(AppTab.home)

            LearnView {
                isShowingSession = true
            }
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
        .fullScreenCover(isPresented: $isShowingSession) {
            LearningSessionContainer(initialState: initialSession)
        }
    }
}
