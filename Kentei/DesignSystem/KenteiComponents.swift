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

/// 学習の伴走キャラクター。
///
/// 静止画のままでは伴走者に見えないため、待機中はゆっくり呼吸し、
/// 音声再生中は発話の拍に合わせて弾む。Reduce Motion では動きを止める。
struct LearningCompanionView: View {
    let expression: CompanionExpression
    var size: CGFloat = 140
    /// 音声再生中かどうか。話している間だけ口元の音波と揺れを出す。
    var isSpeaking = false
    /// 発話の拍。値が変わるたびに一度弾み、話しているように見せる。
    var speechPulse = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isBreathing = false
    @State private var isTalkingBob = false
    @State private var pulseAmount: CGFloat = 0
    @State private var tiltDirection: Double = 1

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

    private var isAnimated: Bool {
        !reduceMotion
    }

    var body: some View {
        ZStack {
            if isSpeaking {
                speechWaves
            }

            ZStack {
                Image(assetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()

                if showsMouthOverlay {
                    mouth
                }
            }
            .frame(width: size, height: size)
            .scaleEffect(
                x: breathingScale - pulseAmount * 0.075,
                y: breathingScale + pulseAmount * 0.105,
                anchor: .bottom
            )
            .rotationEffect(.degrees(tilt), anchor: .bottom)
            .offset(y: talkingOffset)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear {
            guard isAnimated else { return }
            isBreathing = true
        }
        .onChange(of: isSpeaking) { _, speaking in
            guard isAnimated else { return }
            isTalkingBob = speaking
            if !speaking {
                withAnimation(.easeOut(duration: 0.2)) {
                    pulseAmount = 0
                }
            }
        }
        .onChange(of: speechPulse) { _, _ in
            guard isAnimated, isSpeaking else { return }
            tiltDirection *= -1
            withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
                pulseAmount = 1
            }
            withAnimation(.spring(response: 0.26, dampingFraction: 0.75).delay(0.08)) {
                pulseAmount = 0
            }
        }
        .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: isBreathing)
        .animation(.easeInOut(duration: 0.34).repeatForever(autoreverses: true), value: isTalkingBob)
    }

    private var breathingScale: CGFloat {
        guard isAnimated else { return 1 }
        return isBreathing ? 1.03 : 0.975
    }

    private var talkingOffset: CGFloat {
        guard isAnimated, isTalkingBob else { return 0 }
        return -size * 0.035
    }

    private var tilt: Double {
        guard isAnimated, isSpeaking else { return 0 }
        return tiltDirection * Double(pulseAmount) * 3.6
    }

    /// 口を閉じた立ち姿の素材の上に、開いた口だけを重ねて口パクにする。
    ///
    /// 位置と大きさは `CompanionListening` の造形に合わせた比率で、素材を差し替えるときは
    /// この比率も一緒に見直す。本来は口の開閉を含む表情差分素材で置き換える。
    private var showsMouthOverlay: Bool {
        isSpeaking && assetName == "CompanionListening"
    }

    private var mouthOpenAmount: CGFloat {
        guard isAnimated else { return 0.35 }
        return 0.18 + 0.82 * pulseAmount
    }

    private var mouth: some View {
        let mouthTopY = -size * 0.128
        let height = size * (0.012 + 0.052 * mouthOpenAmount)

        return Ellipse()
            .fill(KenteiTheme.companionMouth)
            .frame(width: size * 0.085, height: height)
            .overlay(alignment: .bottom) {
                Ellipse()
                    .fill(KenteiTheme.companionTongue)
                    .frame(width: size * 0.055, height: height * 0.45)
                    .padding(.bottom, height * 0.06)
            }
            .clipShape(Ellipse())
            .offset(y: mouthTopY + height / 2)
    }

    /// 口元から音が出ていることを、色だけに頼らず形でも示す。
    private var speechWaves: some View {
        HStack(spacing: size * 0.02) {
            waveform.scaleEffect(x: -1)
            Spacer(minLength: size * 0.62)
            waveform
        }
        .frame(width: size * 1.42)
    }

    private var waveform: some View {
        Image(systemName: "waveform")
            .font(.system(size: size * 0.2, weight: .semibold))
            .foregroundStyle(KenteiTheme.brandPrimary.opacity(0.65))
            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isSpeaking && isAnimated)
            .accessibilityHidden(true)
    }
}
