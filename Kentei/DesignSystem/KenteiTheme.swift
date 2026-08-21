import SwiftUI
import UIKit

enum KenteiTheme {
    static let brandPrimary = adaptive(
        light: UIColor(red: 0.00, green: 0.55, blue: 0.64, alpha: 1),
        dark: UIColor(red: 0.24, green: 0.76, blue: 0.82, alpha: 1)
    )
    static let brandPrimarySoft = adaptive(
        light: UIColor(red: 0.87, green: 0.96, blue: 0.98, alpha: 1),
        dark: UIColor(red: 0.05, green: 0.20, blue: 0.24, alpha: 1)
    )
    static let brandAccent = adaptive(
        light: UIColor(red: 0.94, green: 0.31, blue: 0.53, alpha: 1),
        dark: UIColor(red: 1.00, green: 0.48, blue: 0.65, alpha: 1)
    )
    static let brandAccentSoft = adaptive(
        light: UIColor(red: 0.99, green: 0.91, blue: 0.94, alpha: 1),
        dark: UIColor(red: 0.28, green: 0.10, blue: 0.17, alpha: 1)
    )
    static let skyBackground = adaptive(
        light: UIColor(red: 0.94, green: 0.98, blue: 1.00, alpha: 1),
        dark: UIColor(red: 0.04, green: 0.10, blue: 0.14, alpha: 1)
    )
    static let warmSurface = adaptive(
        light: UIColor(red: 1.00, green: 0.97, blue: 0.91, alpha: 1),
        dark: UIColor(red: 0.22, green: 0.17, blue: 0.08, alpha: 1)
    )
    static let textPrimary = adaptive(
        light: UIColor(red: 0.09, green: 0.19, blue: 0.26, alpha: 1),
        dark: UIColor(red: 0.91, green: 0.96, blue: 0.98, alpha: 1)
    )
    static let textSecondary = adaptive(
        light: UIColor(red: 0.32, green: 0.40, blue: 0.46, alpha: 1),
        dark: UIColor(red: 0.66, green: 0.74, blue: 0.78, alpha: 1)
    )
    static let surface = adaptive(
        light: UIColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1),
        dark: UIColor(red: 0.07, green: 0.13, blue: 0.16, alpha: 1)
    )
    static let elevatedSurface = adaptive(
        light: .white,
        dark: UIColor(red: 0.08, green: 0.15, blue: 0.18, alpha: 1)
    )
    static let success = adaptive(
        light: UIColor(red: 0.09, green: 0.48, blue: 0.36, alpha: 1),
        dark: UIColor(red: 0.31, green: 0.79, blue: 0.62, alpha: 1)
    )
    static let error = adaptive(
        light: UIColor(red: 0.71, green: 0.23, blue: 0.29, alpha: 1),
        dark: UIColor(red: 0.98, green: 0.46, blue: 0.53, alpha: 1)
    )
    /// キャラクターの口パク用。参照素材の開いた口と同じ色域に合わせる。
    static let companionMouth = Color(uiColor: UIColor(red: 0.62, green: 0.22, blue: 0.31, alpha: 1))
    static let companionTongue = Color(uiColor: UIColor(red: 0.95, green: 0.55, blue: 0.60, alpha: 1))

    static let divider = Color(uiColor: .separator).opacity(0.22)

    static let cardCornerRadius: CGFloat = 20
    static let controlCornerRadius: CGFloat = 16
    static let horizontalPadding: CGFloat = 16

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

private struct KenteiCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(KenteiTheme.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: KenteiTheme.cardCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: KenteiTheme.cardCornerRadius, style: .continuous)
                    .stroke(KenteiTheme.divider, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.05), radius: 12, y: 6)
    }
}

extension View {
    func kenteiCard() -> some View {
        modifier(KenteiCardModifier())
    }
}
