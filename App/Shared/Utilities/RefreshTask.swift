import Foundation

/// Runs a pull-to-refresh load in a task of its own. SwiftUI cancels the `.refreshable` task when the screen redraws,
/// which would drop the load halfway and leave the old data on screen.
@MainActor
func runRefresh(_ work: @escaping @MainActor () async -> Void) async {
    await Task { await work() }.value
}
