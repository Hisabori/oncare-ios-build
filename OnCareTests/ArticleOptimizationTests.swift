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
}
