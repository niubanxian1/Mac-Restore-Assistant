import XCTest
import Foundation
@testable import RestoreLogEngine

/// Guards the capture predicate against a regression that silently dropped the
/// main Apple Configurator process.
///
/// The production profile used `process CONTAINS "configurator"` — **case
/// sensitive** — which matches `com.apple.configurator.xpc.*` (lowercase) but not
/// `Apple Configurator` (capital C). A measured 6-hour window showed 3,174 lines
/// from the main app, 403 of which the taxonomy would have classified.
///
/// These tests evaluate the predicate with `NSPredicate`, the same engine `/usr/bin/log`
/// uses, so they test the real matching semantics rather than a string comparison.
final class CapturePredicateCaseTests: XCTestCase {

    /// What the profile actually ships, read from the production value.
    private var productionPredicate: String { CaptureProfile.restoreDefaultV1.predicate }

    /// The predicate as it was before the fix — used only to prove the difference.
    private let legacyPredicate = #"process CONTAINS "configurator""#

    private func matches(_ predicate: String, process: String) -> Bool {
        let p = NSPredicate(format: predicate)
        // `/usr/bin/log` evaluates `process` as a string attribute; the dictionary
        // form is how NSPredicate sees it.
        return p.evaluate(with: ["process": process])
    }

    // MARK: - the contract

    func testPC01MainAppMatches() {
        XCTAssertTrue(matches(productionPredicate, process: "Apple Configurator"),
                      "the GUI process must be captured")
    }

    func testPC02DeviceServiceStillMatches() {
        XCTAssertTrue(matches(productionPredicate, process: "com.apple.configurator.xpc.DeviceService"))
    }

    func testPC03InternetServiceStillMatches() {
        XCTAssertTrue(matches(productionPredicate, process: "com.apple.configurator.xpc.InternetService"))
    }

    func testPC04AirTrafficServiceStillMatches() {
        XCTAssertTrue(matches(productionPredicate, process: "com.apple.configurator.xpc.AirTrafficService"))
    }

    func testPC05UpperCaseVariantMatches() {
        XCTAssertTrue(matches(productionPredicate, process: "CONFIGURATOR"))
    }

    func testPC06LeadingCapitalMatches() {
        XCTAssertTrue(matches(productionPredicate, process: "Configurator"))
    }

    func testPC07UnrelatedFinderRejected() {
        XCTAssertFalse(matches(productionPredicate, process: "Finder"))
    }

    func testPC08UnrelatedSoftwareUpdateRejected() {
        XCTAssertFalse(matches(productionPredicate, process: "softwareupdated"))
    }

    /// The point of the fix: the legacy predicate misses the main app, the new one
    /// does not, and both keep the helper processes.
    func testPC09LegacyVersusProductionDifferOnlyOnCase() {
        XCTAssertFalse(matches(legacyPredicate, process: "Apple Configurator"),
                       "the legacy predicate is expected to miss the main app")
        XCTAssertTrue(matches(productionPredicate, process: "Apple Configurator"))

        for helper in ["com.apple.configurator.xpc.DeviceService",
                       "com.apple.configurator.xpc.InternetService",
                       "com.apple.configurator.xpc.AirTrafficService"] {
            XCTAssertTrue(matches(legacyPredicate, process: helper), "legacy must have covered \(helper)")
            XCTAssertTrue(matches(productionPredicate, process: helper), "new must still cover \(helper)")
        }
    }

    /// No helper that the old predicate covered may be lost by the new one.
    func testPC10NoHelperCoverageRegressed() {
        let helpers = (1...3).map { "com.apple.configurator.xpc.Service\($0)" }
            + ["com.apple.configurator.xpc.DeviceService"]
        for h in helpers {
            XCTAssertTrue(matches(productionPredicate, process: h), "lost \(h)")
        }
    }

    /// The shipped profile must be the case-insensitive one, so this test fails if
    /// someone reverts the constant.
    func testPC11ProductionProfileUsesCaseInsensitiveMatch() {
        XCTAssertEqual(productionPredicate, #"process CONTAINS[c] "configurator""#)
        XCTAssertTrue(productionPredicate.contains("CONTAINS[c]"))
    }

    /// The predicate reaches `/usr/bin/log` as an argument vector, unprefixed.
    func testPC12GeneratedArgumentVectorCarriesThePredicate() {
        let args = CaptureProfile.restoreDefaultV1.commandArguments
        XCTAssertEqual(args.first, "stream")
        XCTAssertEqual(args[args.count - 2], "--predicate")
        XCTAssertEqual(args.last, productionPredicate)
        XCTAssertTrue(args.last!.contains("CONTAINS[c]"))
    }
}
