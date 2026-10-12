import SwiftUI

struct PracticeInsightsView: View {
    @EnvironmentObject private var journal: Journal
    let day: Date
    @State private var window: PracticeWindow = .week
    @State private var showingDays = false

    var body: some View {
        let periods = PracticeSummary.completedPeriods(entries: journal.entries, window: window, now: day)
        let recent = periods[0], prior = periods[1]
        VStack(alignment: .leading, spacing: 16) {
            Text("완료된 \(window.title)을 돌아봐요").font(.title2.bold()).accessibilityIdentifier("insights-heading")
            Picker("분석 기간", selection: $window) {
                ForEach(PracticeWindow.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("insights-window")
            Text("오늘을 제외한 최근 \(window.title)과 그 이전 \(window.title)을 비교해요.").font(.caption).foregroundStyle(.secondary)
            Text("최근: " + dates(recent) + "\n이전: " + dates(prior)).font(.subheadline).foregroundStyle(.secondary)
            comparison("운동 합계", recent.exercise, prior.exercise, suffix: "분", color: Palette.teal)
            comparison("수면 평균", recent.sleep, prior.sleep, suffix: "시간", color: Palette.purple)
            comparison("마음 평균", recent.mood, prior.mood, suffix: "점", color: Palette.purple)
            DisclosureGroup(isExpanded: $showingDays) {
                let days = PracticeSummary.daily(entries: journal.entries, in: recent)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(days.reversed()) { value in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(koreanDate(value.start, weekday: true)).font(.subheadline.bold())
                            Text("운동 " + formatted(value.exercise, "분") + " · 수면 " + formatted(value.sleep, "시간") + " · 마음 " + formatted(value.mood, "점"))
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }.accessibilityElement(children: .combine)
                        if value.id != days.first?.id { Divider() }
                    }
                }.padding(.top, 12).accessibilityIdentifier("insights-days")
            } label: {
                Label("날짜별 기록", systemImage: "calendar").font(.headline)
            }.tint(Palette.teal).careCard().accessibilityIdentifier("insights-details")
            VStack(alignment: .leading, spacing: 10) {
                ShareLink(item: PracticeSummary.shareText(recent: recent, prior: prior, window: window)) {
                    Label("요약 공유", systemImage: "square.and.arrow.up").font(.headline)
                }.accessibilityIdentifier("insights-share")
                Text("선택한 기간의 운동·수면·마음 요약을 공유해요. 개인 메모와 개별 기록은 포함하지 않아요.")
                    .font(.caption).foregroundStyle(.secondary)
            }.careCard()
            Text("운동은 기록의 합계예요. 수면·마음은 하루 마지막 값의 평균이며 기록 없는 날은 제외해요. 기록 일수가 다르면 평균이나 합계만으로 비교하기 어려울 수 있어요.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func dates(_ period: PracticePeriod) -> String {
        koreanDate(period.start) + " – " + koreanDate(Calendar.current.date(byAdding: .day, value: -1, to: period.end)!)
    }
    private func formatted(_ metric: PracticeMetric, _ suffix: String) -> String {
        metric.value.map { number($0) + suffix } ?? "기록 없음"
    }
    private func comparison(_ title: String, _ recent: PracticeMetric, _ prior: PracticeMetric, suffix: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).foregroundStyle(color)
            Text(formatted(recent, " " + suffix)).font(.title.bold())
            ProgressView(value: Double(recent.recordedDays), total: Double(window.rawValue)).tint(color)
                .accessibilityLabel("최근 기록 일수").accessibilityValue("\(window.rawValue)일 중 \(recent.recordedDays)일")
            Text("최근 \(recent.recordedDays)/\(window.rawValue)일 기록 · 이전 \(prior.recordedDays)/\(window.rawValue)일 기록")
                .font(.caption).foregroundStyle(.secondary)
            Text("이전: " + formatted(prior, " " + suffix)).font(.subheadline).foregroundStyle(.secondary)
            if let current = recent.value, let previous = prior.value {
                let delta = current - previous
                Text("이전 \(window.title) 대비 " + (delta > 0 ? "+" : "") + number(delta) + " " + suffix).font(.subheadline)
            } else {
                Text("두 기간 모두 기록이 있어야 차이를 계산해요.").font(.caption).foregroundStyle(.secondary)
            }
        }.careCard()
    }
}
