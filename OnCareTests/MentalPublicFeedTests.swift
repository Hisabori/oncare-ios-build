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
    func testNCMHMetadataKeepsOriginalTitleAndRejectsUnsafePDFPaths() throws {
        let html = "<span class=\"web_ttl\">마음로그人 33호</span><a onclick=\"fn_fileDown('original.pdf','/2025/09/20250918142603470496_2.pdf','10128');\">다운로드</a>공공누리"
        let items = try NCMHPublication.parse(html)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "마음로그人 33호")
        XCTAssertEqual(items[0].registeredMonth, "2025.09")
        XCTAssertEqual(items[0].url?.host, "www.ncmh.go.kr")
        for path in ["/2025/09/../secret.pdf", "/2025/09/%2e%2e.pdf", "https://evil.test/a.pdf", "/2025/09/file.exe"] { XCTAssertFalse(NCMHPublication.validPath(path)) }
        XCTAssertThrowsError(try NCMHPublication.parse("<html>unavailable</html>"))
    }
    @MainActor func testNewSiriActionsOpenOnlyTheirScreens() async throws {
        let router = CareShortcutRouter.shared
        defer { if let pending = router.pending { router.complete(pending.id) } }
        _ = try await OpenCareMedicationIntent().perform(); XCTAssertEqual(router.pending?.destination, .medication)
        _ = try await OpenCareArticlesIntent().perform(); XCTAssertEqual(router.pending?.destination, .articles)
        _ = try await OpenCareIntelligenceIntent().perform(); XCTAssertEqual(router.pending?.destination, .intelligence)
        XCTAssertEqual(CareDestination.medication.sheet, .medications)
        XCTAssertEqual(CareDestination.articles.sheet, .articles)
    }
}
