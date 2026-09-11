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
    @State private var activeWritingTask: WritingTask?
    @State private var activeOralTask: OralTask?
    @State private var oralDeletionFailed = false

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
        .environment(\.locale, effectiveLocale)
        .onChange(of: appModel.networkMonitor.isOnline) { _, isOnline in
            // 再接続したら、オフライン中に積んだ回答を送り直す。
            guard isOnline else { return }
            Task { await appModel.flushPendingAnswers() }
        }
        .task {
            // Cleanup also runs when no oral screen is opened after an abnormal termination.
            // A failed cleanup is retried and blocks recording in OralTaskModel.prepare().
            do { try OralAudioFiles().prepare() } catch { /* Oral entry retries with a visible error. */ }
            if ProcessInfo.processInfo.arguments.contains("-resetLearningData") {
                do { try Self.deleteOralData() } catch { oralDeletionFailed = true; return }
                await appModel.resetStoredLearningData()
            }
            await appModel.refreshMastery()
            await appModel.refreshResumeState()
            await appModel.refreshPendingSyncCount()
            presentScenarioDetailIfRequested()
            presentWritingResultIfRequested()
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-showOralTask"), let id = arguments[safe: index + 1] {
                activeOralTask = OralTask.all.first { $0.id == id }
            }
        }
        .fullScreenCover(item: $activeSession, onDismiss: refreshAfterSession) { session in
            LearningSessionContainer(model: session)
        }
        .sheet(item: $activeWritingTask) { task in
            WritingTaskView(
                model: appModel.makeWritingTaskModel(
                    task: task,
                    initialState: Self.scriptedResult(for: task).map { .scored($0) } ?? .editing
                )
            )
        }
        .sheet(item: $activeOralTask) { task in
            OralTaskView(task: task)
                .environment(\.locale, effectiveLocale)
        }
        .alert("oral.error.storage", isPresented: $oralDeletionFailed) {
            Button("common.close", role: .cancel) {}
        }
        .sheet(item: $selectedScenario) { progress in
            ScenarioDetailView(
                progress: progress,
                onStartLearning: { scenarioID in
                    selectedScenario = nil
                    startSession(origin: .scenario(scenarioID))
                },
                onStartPracticalCheck: { scenarioID in
                    selectedScenario = nil
                    startSession(origin: .practicalCheck(scenarioID))
                }
            )
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
                isAssessmentConfigured: appModel.isAssessmentAvailable,
                onStartLearning: startSession(origin:),
                onStartWriting: { activeWritingTask = $0 },
                onStartOral: { activeOralTask = $0 }
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
                isAssessmentConfigured: appModel.isAssessmentAvailable,
                assessmentTokenSource: appModel.assessmentTokenSource,
                contentIssueCount: appModel.contentIssues.count,
                pendingSyncCount: appModel.pendingSyncCount,
                isOnline: appModel.networkMonitor.isOnline,
                onDeleteLearningData: deleteLearningData
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

    /// 表示言語。`-interfaceLanguage <ja|id>` があれば初回導入の選択より優先する。画面確認用。
    private var effectiveLocale: Locale {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-interfaceLanguage"),
              let rawValue = arguments[safe: flagIndex + 1],
              let language = InterfaceLanguage(rawValue: rawValue) else {
            return appModel.interfaceLocale
        }
        return Locale(identifier: language.localeIdentifier)
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

    /// `-showWritingResult <課題ID>` で作文の採点結果を直接開く。画面確認用。
    ///
    /// 採点結果は外部の採点を経ないと出せないため、確認のたびに採点を呼ぶことになる。
    /// 決まった結果を持つ画面を直接開けるようにして、表示だけを確かめられるようにする。
    private func presentWritingResultIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-showWritingResult"),
              let taskID = arguments[safe: flagIndex + 1],
              let task = DemoWritingTasks.task(with: taskID) else {
            return
        }
        activeWritingTask = task
    }

    /// 画面確認用の決まった採点結果。合否・観点・講評の並びを確かめるために使う。
    ///
    /// 起動引数から都度組み立てる。別の状態に持たせると、画面が出る時点で
    /// その状態が反映されているかどうかに結果が左右される。
    private static func scriptedResult(for task: WritingTask) -> AssessmentResult? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-showWritingResult"),
              arguments[safe: flagIndex + 1] == task.id,
              let rubric = DemoAssessment.rubric(with: task.rubricID) else {
            return nil
        }
        let scores = rubric.criteria.map { criterion in
            CriterionScore(criterionID: criterion.id, score: 3, commentKey: nil)
        }
        let normalized = rubric.normalizedScore(
            from: Dictionary(uniqueKeysWithValues: scores.map { ($0.criterionID, $0.score) })
        )
        return AssessmentResult(
            submissionID: AssessmentID(rawValue: "preview-\(task.id)"),
            scores: scores,
            overallComment: "画面確認用の講評です。",
            normalizedScore: normalized,
            isPassed: rubric.isPassing(normalized),
            modelVersion: "preview",
            rubricVersion: rubric.version,
            evaluatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            humanReview: .notRequested
        )
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

    private func deleteLearningData() {
        Task {
            do { try Self.deleteOralData() } catch { oralDeletionFailed = true; return }
            await appModel.resetStoredLearningData()
            await appModel.refreshResumeState()
        }
    }

    private static func deleteOralData() throws {
        try OralAudioFiles().clear()
        try FileOralDraftStore.live().deleteAll()
    }

    private func refreshAfterSession() {
        Task {
            await appModel.refreshMastery()
            await appModel.refreshResumeState()
            await appModel.refreshPendingSyncCount()
            await appModel.flushPendingAnswers()
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
