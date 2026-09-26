import SwiftUI

extension Color {
    /// Light/dark pair; light values come from the "Quiet Minimal" design.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let v = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        })
    }

    static let appPrimary = Color(light: 0x16875A, dark: 0x2FB57C)
    static let appSecondary = Color(light: 0x1FA06B, dark: 0x3FC98C)
    static let appBackground = Color(.systemBackground)
    static let appGroupedBackground = Color(.systemGroupedBackground)
    static let appCardBackground = Color(.secondarySystemGroupedBackground)
    static let appSuccess = appPrimary
    static let appWarning = Color(light: 0xC4610A, dark: 0xF0913A)
    static let appError = Color(light: 0xD93636, dark: 0xFF5C5C)
    static let appText = Color(light: 0x111111, dark: 0xF5F5F7)
    static let appTextSecondary = Color(light: 0x6E6E73, dark: 0x98989D)
    static let appTextTertiary = Color(light: 0xA1A1A6, dark: 0x636366)
    static let appBody = Color(light: 0x3A3A3C, dark: 0xD1D1D6)
    /// Row separator inside lists.
    static let appSeparator = Color(light: 0xF2F2F4, dark: 0x2C2C2E)
    /// Section divider and progress track.
    static let appDivider = Color(light: 0xEDEDF0, dark: 0x38383A)
    static let appBorder = Color(light: 0xD2D2D7, dark: 0x48484A)
    /// Search fields, round action buttons.
    static let appFill = Color(light: 0xF2F2F4, dark: 0x1C1C1E)
    static let appIncome = appPrimary
    /// Expenses stay neutral: only income is colored.
    static let appExpense = appText
}
