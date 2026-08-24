import Foundation
import XCTest

@testable import AvivCore

final class RemoteMarkdownChangePlanTests: XCTestCase {
    func testMapsCaretAndSelectionAcrossIncomingInsertion() {
        let old = "# Notes\n\nAlpha\nBeta\nGamma\n"
        let new = "# Notes\n\nAlpha\nExternal line\nBeta\nGamma\n"
        let plan = RemoteMarkdownChangePlan(oldMarkdown: old, newMarkdown: new)
        let oldBeta = (old as NSString).range(of: "Beta")
        let mappedBeta = plan.map(range: oldBeta, newMarkdown: new)

        XCTAssertTrue(plan.hasChanges)
        XCTAssertEqual((new as NSString).substring(with: mappedBeta), "Beta")
        XCTAssertGreaterThan(mappedBeta.location, oldBeta.location)
        XCTAssertFalse(plan.changedLineRanges(in: new).isEmpty)
    }

    func testMapsCaretInsideReplacementWithoutEscapingDocument() {
        let old = "before OLD after"
        let new = "before replacement after"
        let plan = RemoteMarkdownChangePlan(oldMarkdown: old, newMarkdown: new)
        let oldSelection = NSRange(location: 8, length: 2)
        let mapped = plan.map(range: oldSelection, newMarkdown: new)

        XCTAssertGreaterThanOrEqual(mapped.location, plan.newRange.location)
        XCTAssertLessThanOrEqual(NSMaxRange(mapped), (new as NSString).length)
    }

    func testDeletionMarksAdjacentLineAndMapsTrailingCaret() {
        let old = "one\ntwo\nthree\n"
        let new = "one\nthree\n"
        let plan = RemoteMarkdownChangePlan(oldMarkdown: old, newMarkdown: new)
        let oldCaret = (old as NSString).range(of: "three").location

        XCTAssertEqual(plan.map(location: oldCaret), (new as NSString).range(of: "three").location)
        XCTAssertEqual(plan.changedLineRanges(in: new).count, 1)
    }
}
