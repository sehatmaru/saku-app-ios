import Foundation

/// An email shown partly hidden ("bu••@gmail.com"), so a guest can tell which account they would switch to
/// without the screen giving the whole address away.
enum EmailMask {
    static func masked(_ email: String) -> String {
        let parts = email.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return "••" }
        let local = parts[0]
        let shown = local.count > 2 ? 2 : 1
        return String(local.prefix(shown)) + "••@" + parts[1]
    }
}

/// Reads what the provider says about the email in a sign-in token. The server still checks the token's signature;
/// this only lets the app refuse an address the provider has not verified before anything is linked.
enum IdentityToken {
    static func emailIsVerified(_ idToken: String) -> Bool {
        guard let claims = claims(idToken) else { return false }
        if let flag = claims["email_verified"] as? Bool { return flag }
        if let text = claims["email_verified"] as? String { return text.lowercased() == "true" }
        return false
    }

    static func claims(_ idToken: String) -> [String: Any]? {
        let segments = idToken.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var base64 = segments[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
