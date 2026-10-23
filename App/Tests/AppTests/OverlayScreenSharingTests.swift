import Foundation
import XCTest

@testable import RealtimeTranslator

/// Tests the overlay's "hide from screen sharing" toggle and that it's remembered across launches
/// (`OverlayViewModel.isHiddenFromScreenSharing`), against a throwaway `UserDefaults` suite.
@MainActor
final class OverlayScreenSharingTests: XCTestCase {
    private nonisolated(unsafe) var suiteName: String!
    private nonisolated(unsafe) var userDefaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "AppTests-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    func testVisibleToScreenSharingByDefault() {
        XCTAssertFalse(OverlayViewModel(userDefaults: userDefaults).isHiddenFromScreenSharing)
    }

    func testToggleIsRememberedByTheNextLaunch() {
        let viewModel = OverlayViewModel(userDefaults: userDefaults)
        viewModel.toggleHiddenFromScreenSharing()
        XCTAssertTrue(viewModel.isHiddenFromScreenSharing)
        XCTAssertTrue(OverlayViewModel(userDefaults: userDefaults).isHiddenFromScreenSharing)

        viewModel.toggleHiddenFromScreenSharing()
        XCTAssertFalse(OverlayViewModel(userDefaults: userDefaults).isHiddenFromScreenSharing)
    }
}
