import SwiftUI

/// Short taps of feedback for the moments that matter.
@MainActor
enum Haptics {
    /// Opening the add-transaction form.
    static func add() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    /// Landing on Beranda after the app opens.
    static func welcome() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    /// Signing out.
    static func logout() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
