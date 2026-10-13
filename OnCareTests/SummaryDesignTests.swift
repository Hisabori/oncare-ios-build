import XCTest
@testable import OnCare
final class SummaryDesignTests: XCTestCase {
 func testMissingDaysStayMissingAndFutureRecordsAreExcluded(){let now=Date(timeIntervalSince1970:1_800_000_000);let entries=[Entry(date:dayOffset(-2,from:now).addingTimeInterval(3600),kind:"걸음",value:100),Entry(date:dayOffset(-2,from:now).addingTimeInterval(7200),kind:"걸음",value:200),Entry(date:now.addingTimeInterval(3600),kind:"걸음",value:999)];let days=SummaryMetrics.days(entries,kind:"걸음",now:now);XCTAssertEqual(days.count,7);XCTAssertEqual(days.compactMap(\.value),[300]);XCTAssertEqual(SummaryMetrics.mean(days),300);XCTAssertNil(days.last?.value)}
 func testSleepUsesLastRecordWithoutSummingSeparateNights(){let now=Date(timeIntervalSince1970:1_800_000_000);let start=dayOffset(-1,from:now);let entries=[Entry(id:"a",date:start.addingTimeInterval(3600),kind:"수면",value:6),Entry(id:"b",date:start.addingTimeInterval(7200),kind:"수면",value:8)];XCTAssertEqual(SummaryMetrics.mean(SummaryMetrics.days(entries,kind:"수면",now:now)),8)}
 func testEmptySummaryDoesNotInventZeroAverage(){XCTAssertNil(SummaryMetrics.mean(SummaryMetrics.days([],kind:"마음")))}
}
