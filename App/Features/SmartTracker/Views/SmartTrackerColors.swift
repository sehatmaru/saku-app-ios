import SwiftUI

/// Smart Tracker colours, light and dark (design "SakuQ Smart Tracker" and "... Dark").
extension Color {
    /// Chips, circle buttons and inputs sitting on a card or the page.
    static let stChip = Color(light: 0xF2F2F4, dark: 0x2C2C2E)
    /// Small surfaces lifted off a card (icon tiles, the mic button).
    static let stRaised = Color(light: 0xFFFFFF, dark: 0x3A3A3C)
    static let stSuccessBg = Color(light: 0xE6F3EC, dark: 0x10301F)
    static let stSuccessText = Color(light: 0x0E5E41, dark: 0x6FE0AE)
    static let stDangerBg = Color(light: 0xFDECEC, dark: 0x3A1716)
    static let stDangerText = Color(light: 0xD1343A, dark: 0xFF6961)
    /// The brand green for fills: the button, the progress, the check.
    static let stGreen = Color(light: 0x16875A, dark: 0x22A06B)
    static let stExpense = Color(light: 0xD93636, dark: 0xFF453A)
    static let stTransfer = Color(light: 0x143A73, dark: 0x2A5BA8)
    static let stCardPayment = Color(light: 0x6B3FA0, dark: 0x8E5BD0)
    static let stLine = Color(light: 0xD9EDE2, dark: 0x1E4632)
    /// The floating bar over the tab bar.
    static let stBar = Color(light: 0xFFFFFF, dark: 0x1C1C1E)
    /// The dark pill buttons of the empty states ("Catat sekarang", "Aktifkan Smart Tracker"): black on light, near-white on dark.
    static let stInk = Color(light: 0x111111, dark: 0xF5F5F7)
    static let stInkText = Color(light: 0xFFFFFF, dark: 0x000000)
    /// Dashed outline of "Contohnya nanti" and "Belum ada aplikasi terhubung".
    static let stDash = Color(light: 0xC7C7CC, dark: 0x545458)
    /// "Belum ada" warning card and orange placeholder values.
    static let stWarnBg = Color(light: 0xFFF4E5, dark: 0x3A2A12)
    static let stWarn = Color(light: 0xC4610A, dark: 0xFF9F0A)
}
