import XCTest
@testable import Saku

/// BUG-43: a session restored after the app was closed mid-onboarding must show setup again.
final class OnboardingProgressTests: XCTestCase {
    func testInterruptedSetupWithNoWalletsShowsSetup() {
        XCTAssertTrue(OnboardingProgress.needsSetup(markedComplete: false, accountCount: 0))
    }

    func testExistingAccountWithWalletsSkipsSetup() {
        XCTAssertFalse(OnboardingProgress.needsSetup(markedComplete: false, accountCount: 2))
    }

    func testFinishedSetupNeverShowsSetupAgain() {
        XCTAssertFalse(OnboardingProgress.needsSetup(markedComplete: true, accountCount: 0))
    }

    func testUnknownAccountCountDoesNotLockTheUserOut() {
        XCTAssertFalse(OnboardingProgress.needsSetup(markedComplete: false, accountCount: nil))
    }
}
