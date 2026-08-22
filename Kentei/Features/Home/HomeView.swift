import SwiftUI

struct HomeView: View {
    let resumeState: AppModel.ResumeState
    let masteredQuestionCount: Int
    let reviewDueCount: Int
    let onStartLearning: () -> Void
    let onResumeLearning: () -> Void

    private let statColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    resumeCard
                    todayLessonCard
                    quickStats
                    nextAction
                    reviewCard
                }
                .padding(.horizontal, KenteiTheme.horizontalPadding)
                .padding(.bottom, 32)
            }
            .background(KenteiTheme.skyBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("home.greeting")
                    .font(.largeTitle.bold())
                    .foregroundStyle(KenteiTheme.textPrimary)
                Text("home.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(KenteiTheme.textSecondary)
            }
            // 大きい文字設定でも見出しを省略しない。折り返して全文を見せる。
            .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button(action: {}) {
                Image(systemName: "bell.fill")
                    .font(.headline)
                    .foregroundStyle(KenteiTheme.brandPrimary)
                    .frame(width: 46, height: 46)
                    .background(KenteiTheme.elevatedSurface, in: Circle())
                    .overlay(alignment: .topTrailing) {
                        Circle()
                            .fill(KenteiTheme.brandAccent)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(KenteiTheme.skyBackground, lineWidth: 2))
                    }
            }
            .accessibilityLabel(Text("home.notifications"))
        }
        .padding(.top, 12)
    }

    /// 途中離脱した学習がある場合、最優先で「続きから」を示す。
    @ViewBuilder
    private var resumeCard: some View {
        if case let .available(answeredCount, totalCount, _) = resumeState {
            KenteiCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("home.resume.title", systemImage: "arrow.uturn.left.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(KenteiTheme.brandPrimary)

                    Text("home.resume.detail")
                        .font(.subheadline)
                        .foregroundStyle(KenteiTheme.textSecondary)

                    HStack(spacing: 10) {
                        ProgressView(value: Double(answeredCount), total: Double(max(totalCount, 1)))
                            .tint(KenteiTheme.brandPrimary)
                        Text("\(answeredCount) / \(totalCount)")
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(KenteiTheme.textPrimary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("session.progress.label"))
                    .accessibilityValue(Text("\(answeredCount) / \(totalCount)"))

                    Button(action: onResumeLearning) {
                        Label("home.resume.action", systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("home.resumeLesson")

                    Button("home.resume.startOver", action: onStartLearning)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KenteiTheme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("home.startOver")
                }
            }
        }
    }

    private var todayLessonCard: some View {
        KenteiCard {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    lessonCopy
                    Spacer(minLength: 4)
                    LearningCompanionView(expression: .encourage, size: 132)
                }

                VStack(spacing: 14) {
                    LearningCompanionView(expression: .encourage, size: 128)
                    lessonCopy
                }
            }
        }
        .overlay(alignment: .topLeading) {
            Capsule()
                .fill(KenteiTheme.brandAccent)
                .frame(width: 64, height: 7)
                .offset(x: 20, y: -3)
        }
    }

    private var lessonCopy: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("home.today", systemImage: "sparkles")
                .font(.caption.weight(.bold))
                .foregroundStyle(KenteiTheme.brandAccent)

            Text("home.lesson.title")
                .font(.title2.weight(.bold))
                .foregroundStyle(KenteiTheme.textPrimary)

            Text("home.lesson.description")
                .font(.subheadline)
                .foregroundStyle(KenteiTheme.textSecondary)

            HStack(spacing: 12) {
                Label("home.lesson.duration", systemImage: "clock")
                Label("home.lesson.questions", systemImage: "checklist")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(KenteiTheme.textSecondary)

            Button(action: onStartLearning) {
                Label("home.lesson.start", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("home.startLesson")
        }
        .frame(maxWidth: 360, alignment: .leading)
    }

    private var quickStats: some View {
        VStack(spacing: 12) {
            SectionTitle(title: "home.progress.title")

            LazyVGrid(columns: statColumns, spacing: 12) {
                MetricChip(
                    systemImage: "checkmark.seal.fill",
                    value: "\(masteredQuestionCount)",
                    label: "home.mastered",
                    tint: KenteiTheme.brandPrimary
                )
                MetricChip(
                    systemImage: "arrow.clockwise",
                    value: "\(reviewDueCount)",
                    label: "home.reviewDue",
                    tint: reviewDueCount > 0 ? .orange : KenteiTheme.brandAccent
                )
            }
        }
    }

    private var nextAction: some View {
        VStack(spacing: 12) {
            SectionTitle(title: "home.action.title")

            KenteiCard {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(KenteiTheme.brandPrimarySoft)
                        Image(systemName: "suitcase.rolling.fill")
                            .font(.title)
                            .foregroundStyle(KenteiTheme.brandPrimary)
                    }
                    .frame(width: 62, height: 62)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("home.action.airport")
                            .font(.headline)
                            .foregroundStyle(KenteiTheme.textPrimary)
                        Text("home.action.airport.detail")
                            .font(.subheadline)
                            .foregroundStyle(KenteiTheme.textSecondary)

                        ProgressView(value: 0.72)
                            .tint(KenteiTheme.brandPrimary)
                    }

                    Text("72%")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(KenteiTheme.brandPrimary)
                }
            }
        }
    }

    private var reviewCard: some View {
        KenteiCard {
            HStack(spacing: 14) {
                Image(systemName: "ear.fill")
                    .font(.title2)
                    .foregroundStyle(KenteiTheme.brandAccent)
                    .frame(width: 48, height: 48)
                    .background(KenteiTheme.brandAccentSoft, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("home.review.title")
                        .font(.headline)
                        .foregroundStyle(KenteiTheme.textPrimary)
                    Text("home.review.description")
                        .font(.subheadline)
                        .foregroundStyle(KenteiTheme.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(KenteiTheme.textSecondary)
            }
        }
    }
}

