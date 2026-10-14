import XCTest
import Foundation
@testable import OnCare

final class MentalPublicFeedTests: XCTestCase {
    func testFeedFiltersFundingExternalURLsAndDuplicates() {
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Useful &amp; public</title><link rel="alternate" href="https://www.nimh.nih.gov/news/a"/><published>2026-10-14</published></entry><entry><title>Duplicate</title><link rel="alternate" href="https://www.nimh.nih.gov/news/a"/></entry><entry><title>Funding</title><link rel="alternate" href="https://www.nimh.nih.gov/funding/a"/></entry><entry><title>Unsafe</title><link rel="alternate" href="https://evil.test/news/a"/></entry></feed>
        """
        let delegate = MentalNewsParser(), parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = delegate
        XCTAssertTrue(parser.parse()); XCTAssertTrue(delegate.hasFeed)
        XCTAssertEqual(delegate.items.count, 1)
        XCTAssertEqual(delegate.items.first?.title, "Useful & public")
        XCTAssertEqual(delegate.items.first?.date, "2026-10-14")
    }
    func testRejectsUnsafeSourceURLs() {
        for url in ["http://www.nimh.nih.gov/news/a", "https://www.nimh.nih.gov.evil.test/news/a", "https://user@www.nimh.nih.gov/news/a", "https://www.nimh.nih.gov:444/news/a", "https://www.nimh.nih.gov/funding/a"] {
            XCTAssertFalse(MentalNewsParser.allowed(url))
        }
    }
}
