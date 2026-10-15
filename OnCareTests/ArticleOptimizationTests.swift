import XCTest
import Combine
@testable import OnCare

@MainActor final class ArticleOptimizationTests: XCTestCase {
    func testOpeningAlreadyReadArticleDoesNotPublishAnotherChange() throws {
        let suite = "article-optimization-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = ArticleLibrary(defaults: defaults)
        var changes = 0
        let subscription = library.objectWillChange.sink { changes += 1 }
        let id = try XCTUnwrap(HealthArticle.catalog.first?.id)
        library.markRead(id); XCTAssertEqual(changes, 1)
        library.markRead(id); library.markRead("unknown"); XCTAssertEqual(changes, 1)
        XCTAssertTrue(ArticleLibrary(defaults: defaults).read.contains(id))
        withExtendedLifetime(subscription) {}
    }
    func testFullTextSearchAndUnreadKeepBookmarks() throws {
        let article = try XCTUnwrap(HealthArticle.catalog.first { $0.id == "sleep-energy" })
        XCTAssertTrue(ArticleSearch.matches(article, query: "  수면   카페인 "))
        XCTAssertTrue(ArticleSearch.matches(article, query: "  "))
        XCTAssertFalse(ArticleSearch.matches(article, query: "수면 없는검색어"))
        let suite = "article-unread-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = ArticleLibrary(defaults: defaults)
        library.toggleSaved(article.id); library.markRead(article.id); library.markUnread(article.id); library.markUnread(article.id)
        let restored = ArticleLibrary(defaults: defaults)
        XCTAssertFalse(restored.read.contains(article.id)); XCTAssertTrue(restored.saved.contains(article.id))
    }
}
