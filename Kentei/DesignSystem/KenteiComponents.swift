import SwiftUI

enum CompanionExpression: Sendable {
    case normal
    case happy
    case surprised
    case thinking
    case celebrate
    case encourage
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isEnabled ? Color.white : KenteiTheme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 18)
            .background(isEnabled ? KenteiTheme.brandPrimary : KenteiTheme.divider.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: KenteiTheme.controlCornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed && isEnabled ? 0.88 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(KenteiTheme.brandPrimary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 18)
            .background(KenteiTheme.brandPrimarySoft)
            .clipShape(RoundedRectangle(cornerRadius: KenteiTheme.controlCornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct KenteiCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kenteiCard()
    }
}

struct SectionTitle: View {
    let title: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(KenteiTheme.textPrimary)

            Spacer()

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(KenteiTheme.brandPrimary)
            }
        }
    }
}

struct MetricChip: View {
    let systemImage: String
    let value: String
    let label: LocalizedStringKey
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(KenteiTheme.textPrimary)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(KenteiTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(KenteiTheme.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(KenteiTheme.divider, lineWidth: 1)
        }
    }
}

struct ProgressRing: View {
    let progress: Double
    let label: String
    var size: CGFloat = 74

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(KenteiTheme.brandPrimarySoft, lineWidth: 8)
            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(
                    KenteiTheme.brandPrimary,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text(label)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(KenteiTheme.textPrimary)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("common.progress"))
        .accessibilityValue(Text(label))
    }
}

struct LearningCompanionView: View {
    let expression: CompanionExpression
    var size: CGFloat = 140

    private var assetName: String {
        switch expression {
        case .normal, .thinking:
            "CompanionListening"
        case .happy, .celebrate:
            "CompanionHappy"
        case .surprised, .encourage:
            "CompanionEncourage"
        }
    }

    var body: some View {
        Image(assetName)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
