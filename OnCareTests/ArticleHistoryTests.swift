import XCTest
@testable import OnCare
final class ArticleHistoryTests: XCTestCase {
    func testNormalizationDropsUnknownDuplicatesAndCapsHistory() {
        let ids = (0..<15).map(String.init)
        let result = ArticleHistory.normalized(["unknown", "0", "0"] + ids, known: Set(ids))
        XCTAssertEqual(result, Array(ids.prefix(10)))
    }
    @MainActor func testOpeningMovesToFrontAndRestoresLocally() throws {
        let suite = "article-history-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let ids = HealthArticle.catalog.map(\.id), library = ArticleLibrary(defaults: defaults)
        library.recordOpened(ids[0]); library.recordOpened(ids[1]); library.recordOpened(ids[0]); library.recordOpened("unknown")
        XCTAssertEqual(library.recent, [ids[0], ids[1]])
        XCTAssertEqual(ArticleLibrary(defaults: defaults).recent, [ids[0], ids[1]])
        XCTAssertTrue(library.read.isEmpty, "Opening history does not independently change read status")
    }
    @MainActor func testClearAndDisableKeepBookmarksAndReadState() throws {
        let suite = "article-history-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let library = ArticleLibrary(defaults: defaults), id = HealthArticle.catalog[0].id
        library.toggleSaved(id); library.markRead(id); library.recordOpened(id); library.clearRecent()
        XCTAssertTrue(library.recent.isEmpty); XCTAssertTrue(library.saved.contains(id)); XCTAssertTrue(library.read.contains(id))
        library.recordOpened(id); library.keepRecent = false; library.recordOpened(id)
        XCTAssertTrue(library.recent.isEmpty); XCTAssertNil(defaults.object(forKey: "care-articles-v1.recent"))
        XCTAssertFalse(ArticleLibrary(defaults: defaults).keepRecent)
        library.keepRecent = true; XCTAssertTrue(library.recent.isEmpty)
    }
}
