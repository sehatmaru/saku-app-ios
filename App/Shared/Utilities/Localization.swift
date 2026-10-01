import Foundation

/// In-app language ("id" or "en", chosen in Profil › Bahasa). Indonesian text is the key
/// everywhere, so a missing English translation just falls back to Indonesian.
enum AppLanguage {
    static var code: String { UserDefaults.standard.string(forKey: "appLanguage") ?? "id" }

    /// Locale for dates and names. Currency formatting stays id_ID on purpose (Rp1.500.000).
    static var locale: Locale { Locale(identifier: code == "en" ? "en_US" : "id_ID") }

    /// nil for Indonesian: the key already is the text (and `.main` would follow the device language).
    static var bundle: Bundle? {
        guard code != "id" else { return nil }
        return Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:))
    }
}

/// Localized string for code that builds plain `String`s (SwiftUI `Text("literal")` already localizes
/// itself). The key is the Indonesian text with `%@` / `%lld` placeholders, e.g. `L("Sisa %@", amount)`.
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = AppLanguage.bundle?.localizedString(forKey: key, value: key, table: nil) ?? key
    return args.isEmpty ? format : String(format: format, locale: AppLanguage.locale, arguments: args)
}

/// For an Indonesian word that needs a different English meaning than its other uses (e.g. "Keluar":
/// "Sign out" on the profile, "Out" next to income).
func Lx(_ id: String, en: String) -> String { AppLanguage.code == "en" ? en : id }
