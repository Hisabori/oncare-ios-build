import XCTest
@testable import OnCare

final class ArticleTests: XCTestCase {
    func testCatalogHasUniqueVerifiedSourcesAndUsefulContent() {
        let catalog = HealthArticle.catalog
        XCTAssertEqual(Set(catalog.map(\.id)).count, catalog.count)
        XCTAssertEqual(Set(catalog.map(\.topic)), Set(ArticleTopic.allCases))
        for article in catalog {
            XCTAssertNotNil(article.sourceURL)
            XCTAssertEqual(article.takeaways.count, 3)
            XCTAssertFalse(article.summary.isEmpty)
            XCTAssertFalse(article.action.isEmpty)
        }
    }
    func testSourceURLRejectsImpersonationAndUnsafeSchemes() {
        for raw in ["http://www.nhs.uk/a", "https://www.nhs.uk.evil.test/a", "https://user@www.nhs.uk/a", "https://www.nhs.uk:444/a", "https://www.nhs.uk/a?record=private", "oncare://open/mood", "https://evil.test/", "https://www.nhs.uk/a#private"] {
            XCTAssertNil(HealthArticle.validSourceURL(raw), raw)
        }
    }
    func testInterestOverridesRecentRecordsAndRankingIsStable() {
        let result = ArticleRecommender.recommendations(interests: [.nutrition], recentKinds: ["수면"], read: [])
        XCTAssertEqual(result.first?.article.topic, .nutrition)
        XCTAssertTrue(result.first!.reason.contains("관심 주제"))
        XCTAssertEqual(result.first(where: { $0.article.topic == .sleep })?.article.topic, .sleep)
        XCTAssertTrue(result.first(where: { $0.article.topic == .sleep })!.reason.contains("최근 7일"))
        XCTAssertEqual(result.map(\.id), ArticleRecommender.recommendations(interests: [.nutrition], recentKinds: ["수면"], read: []).map(\.id))
    }
    func testFutureAndOldRecordsDoNotInfluenceRecommendations() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entries = [Entry(date: now.addingTimeInterval(-60), kind: "운동", value: 15), Entry(date: now.addingTimeInterval(60), kind: "체중", value: 70), Entry(date: now.addingTimeInterval(-9 * 86400), kind: "수면", value: 8)]
        XCTAssertEqual(ArticleRecommender.recentKinds(entries: entries, now: now), ["운동"])
    }
    @MainActor func testPreferencesPersistAndRecordUseRequiresOptIn() throws {
        let suite = "article-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = ArticleLibrary(defaults: defaults)
        let entries = [Entry(kind: "체중", value: 70, note: "private-note")]
        XCTAssertFalse(library.useRecords)
        XCTAssertEqual(library.recommendations(entries: entries).first?.article.topic, .sleep)
        library.useRecords = true
        XCTAssertEqual(library.recommendations(entries: entries).first?.article.topic, .nutrition)
        library.toggleInterest(.mind); library.toggleSaved("mind-five"); library.markRead("mind-five")
        library.toggleSaved("invalid"); library.markRead("invalid")
        let restored = ArticleLibrary(defaults: defaults)
        XCTAssertEqual(restored.interests, [.mind]); XCTAssertEqual(restored.saved, ["mind-five"]); XCTAssertEqual(restored.read, ["mind-five"])
        XCTAssertTrue(restored.useRecords)
        restored.toggleSaved("mind-five"); restored.toggleInterest(.mind)
        XCTAssertTrue(ArticleLibrary(defaults: defaults).saved.isEmpty)
        XCTAssertTrue(ArticleLibrary(defaults: defaults).interests.isEmpty)
    }
}
