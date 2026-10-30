import XCTest
@testable import Saku

@MainActor
final class TrialEndedAfterLogoutTests: XCTestCase {
    /// After signing out the entitlement is "free" and the old trial flags are still on the device: the next sign-in must not
    /// see a "trial ended" summary before its own profile has been read.
    func testNoSummaryUntilTheProfileIsRead() {
        UserDefaults.standard.set(true, forKey: "plusWasTrial")
        UserDefaults.standard.set(false, forKey: "plusTrialEndedSeen")
        PlusStore.shared.reset()
        XCTAssertFalse(PlusStore.shared.trialEndedSummaryDue)
    }
}
