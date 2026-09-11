import AVFoundation
import SwiftUI

struct OralTaskView: View {
    let task: OralTask
    @State private var model: OralTaskModel?
    @State private var initializationFailed = false
    @State private var showingJapaneseHint = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if task.isInterview {
                        Text("interview.instructions").font(.headline)
                        if let model { interviewQuestion(model) }
                    } else {
                        Text(LocalizedStringKey(task.promptKey)).font(.headline)
                    }
                    Text(task.answerMode == .written ? "interview.writtenPolicy" : "oral.policy").font(.subheadline)
                    if let model { controls(model) }
                    if initializationFailed { Text("oral.error.storage") }
                }
                .padding(KenteiTheme.horizontalPadding)
            }
            .background(KenteiTheme.skyBackground)
            .navigationTitle(LocalizedStringKey(task.titleKey))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.close") { if model?.close() != false { dismiss() } }
                        .disabled(model?.state == .submitting)
                }
            }
        }
        .interactiveDismissDisabled()
        .task {
            guard model == nil else { return }
            do {
                let created = OralTaskModel(task: task, recorder: OralRecordingService(),
                    store: try FileOralDraftStore.live(), evaluator: UnconfiguredResponseEvaluator(),
                    questionPlayer: SpeechQuestionAudioPlayer())
                model = created
                created.prepare()
            } catch { initializationFailed = true }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                showingJapaneseHint = false
                model?.suspend(isBackground: phase == .background)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in
            model?.close()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            if let value = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
               AVAudioSession.RouteChangeReason(rawValue: value) == .oldDeviceUnavailable { model?.close() }
        }
        .onDisappear { model?.close() }
    }

    @ViewBuilder
    private func interviewQuestion(_ model: OralTaskModel) -> some View {
        Text("interview.topicRule").font(.footnote)
        Text(LocalizedStringKey("interview.turn.\(min(model.questionIndex + 1, OralTask.maximumInterviewAnswers))"))
        if model.state == .playingQuestion {
            Button("interview.stopQuestion") { model.stopQuestion() }
                .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("interview.stopQuestion")
        } else {
            Button("interview.playQuestion") { model.playQuestion() }
                .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("interview.playQuestion")
                .disabled(model.topicOutcome != nil || model.isBusy || model.state == .recording)
        }
        Text(model.hasHeardQuestion ? "interview.ready" : "interview.listenFirst")
            .font(.subheadline).accessibilityIdentifier("interview.questionStatus")
        Button { showingJapaneseHint.toggle() } label: {
            Label("interview.japaneseHint", systemImage: "questionmark.circle")
        }
        .frame(minHeight: 44).accessibilityIdentifier("interview.hint")
        .popover(isPresented: $showingJapaneseHint) {
            VStack(alignment: .leading, spacing: 16) {
                Text(model.currentJapaneseHint)
                    .accessibilityIdentifier("interview.hintText")
                Button("common.close") { showingJapaneseHint = false }.frame(minHeight: 44)
                    .accessibilityIdentifier("interview.hintClose")
            }
            .padding().frame(idealWidth: 300)
            .presentationCompactAdaptation(.popover)
        }
    }

    @ViewBuilder
    private func controls(_ model: OralTaskModel) -> some View {
        if let failure = model.failure {
            Text(LocalizedStringKey(failure.key)).foregroundStyle(KenteiTheme.error)
            if failure == .cleanup || failure == .storage {
                Button("oral.reload") { model.prepare() }.frame(minHeight: 44)
            }
        }
        if model.isBusy { ProgressView().accessibilityLabel(Text("oral.processing")) }
        if task.answerMode == .voice {
          if model.state == .recording {
            Label("oral.recording", systemImage: "record.circle").foregroundStyle(KenteiTheme.error)
            Button("oral.stop") { model.stop() }.buttonStyle(PrimaryButtonStyle())
        } else {
            Button(model.text.isEmpty ? "oral.start" : "oral.rerecord") { model.start() }
                .buttonStyle(PrimaryButtonStyle()).disabled(model.topicOutcome != nil || model.isBusy || !model.canAnswer)
                .accessibilityIdentifier("oral.start")
        }
        Button("oral.play") { model.play() }.frame(minHeight: 44).disabled(!model.hasRecording || model.isBusy || model.state == .recording)
        }
        if !task.isInterview || task.answerMode == .written || !model.text.isEmpty || model.hasRecording {
        Text(task.answerMode == .written ? "interview.writtenAnswer" : "oral.transcript").font(.headline)
        TextEditor(text: Binding(get: { model.text }, set: { model.edit($0) }))
            .frame(minHeight: 180).disabled(!model.canEditAnswer || model.isBusy || model.state == .recording)
            .accessibilityLabel(Text(task.answerMode == .written ? "interview.writtenAnswer" : "oral.transcript")).accessibilityIdentifier("oral.transcript")
        }
        Toggle("oral.confirm", isOn: Binding(get: { model.confirmed }, set: { model.confirmed = $0 }))
            .accessibilityIdentifier("oral.confirm")
            .disabled(!model.canAnswer || model.isBusy || model.state == .recording)
        if !model.sendingEnabled { Text("oral.pendingNotice").font(.footnote) }
        Button(model.sendingEnabled ? "oral.submit" : "oral.save") {
            Task { await model.submit() }
        }.buttonStyle(PrimaryButtonStyle()).disabled(!model.canSubmit).accessibilityIdentifier("oral.submit")
        if model.state == .saved { Label(task.answerMode == .written ? "interview.saved" : "oral.saved", systemImage: "checkmark.circle") }
        if let result = model.draft.result {
            if let outcome = model.topicOutcome {
                switch outcome {
                case .followUp:
                    Label("interview.followupReady", systemImage: "arrow.turn.down.right")
                    Button("interview.next") {
                        showingJapaneseHint = false
                        model.advanceInterview()
                    }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("interview.next")
                case .passed:
                    Label("interview.topicPassed", systemImage: "checkmark.seal")
                case .failed:
                    Label("interview.topicFailed", systemImage: "xmark.circle")
                }
                Text("interview.practiceNotice").font(.footnote)
            }
            Text("oral.result").font(.headline)
            ForEach(result.scores, id: \.criterionID) { score in
                VStack(alignment: .leading) {
                    Text(LocalizedStringKey(model.task.rubric.criteria.first { $0.id == score.criterionID }?.titleKey ?? "oral.result"))
                    Text("\(score.score) / 4")
                    if let comment = score.commentKey { Text(comment) }
                }
            }
            if let comment = result.overallComment { Text(comment) }
        }
        Button("oral.delete", role: .destructive) { model.discard() }
            .frame(minHeight: 44).disabled(model.isBusy).accessibilityIdentifier("oral.delete")
    }
}
