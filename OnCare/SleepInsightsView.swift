import SwiftUI

struct SleepInsightsView: View {
    let entries: [Entry]
    let goal: Double
    let now: Date
    private var summary: SleepPatternSummary { .analyze(entries, now: now) }
    @State private var selectedID: String?
    private var detailedRecords: [Entry] {
        entries.filter { $0.kind == "수면" && $0.sleepAnalysis != nil && $0.date <= now }
            .sorted { $0.date == $1.date ? $0.id > $1.id : $0.date > $1.date }.prefix(7).map { $0 }
    }
    private var detailed: Entry? { detailedRecords.first { $0.id == selectedID } ?? detailedRecords.first }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text("기록으로 보는 최근 7일").font(.headline)
                Text(summary.meanHours.map { number($0) + "시간" } ?? "기록 없음").font(.largeTitle.bold()).foregroundStyle(Palette.purple)
                Text("오늘 포함 \(summary.entries.count)/7일 기록 · 하루 마지막 기록의 평균").font(.caption).foregroundStyle(.secondary)
                if let mean = summary.meanHours {
                    let difference = mean - goal
                    Text("내 목표 \(number(goal))시간 대비 " + (difference > 0 ? "+" : "") + number(difference) + "시간").font(.subheadline)
                }
                TrendChart(entries: summary.entries, kind: "수면")
                HStack {
                    clockMetric("취침 시각 폭", summary.bedtimeSpan)
                    Spacer()
                    clockMetric("기상 시각 폭", summary.wakeSpan)
                }
                Text("시각 상세가 있는 기록끼리 비교해요. 자정을 넘어도 같은 24시간 시계에서 가장 짧은 범위를 계산하며, 2일 이상 필요해요.").font(.caption).foregroundStyle(.secondary)
            }.careCard().accessibilityIdentifier("sleep-pattern-summary")
            if let entry = detailed, let analysis = entry.sleepAnalysis {
                VStack(alignment: .leading, spacing: 14) {
                    Text("수면 상세").font(.headline)
                    if detailedRecords.count > 1 {
                        Picker("수면 기록 선택", selection: Binding(get: { entry.id }, set: { selectedID = $0 })) {
                            ForEach(detailedRecords) { item in Text(koreanDate(item.date) + " · " + (item.sleepAnalysis?.sourceLabel ?? "기록")).tag(item.id) }
                        }.pickerStyle(.menu).accessibilityIdentifier("sleep-detail-select")
                    }
                    Text(koreanDate(entry.date) + " · " + analysis.sourceLabel).font(.subheadline.bold()).accessibilityIdentifier("sleep-detail-source")
                    if let bed = entry.bedTime, let wake = entry.wakeTime {
                        Text(time(bed) + " → " + time(wake)).font(.title2.bold())
                    }
                    Text("수면 \(number(analysis.sleepMinutes / 60))시간 · 깨어 있던 시간 \(number(analysis.awakeMinutes))분").font(.subheadline)
                    Text("수면 비율 \(number(analysis.efficiency * 100))% · 기록 기준").font(.caption).foregroundStyle(.secondary)
                    if let device = analysis.deviceName { Text("기기: " + device).font(.caption).foregroundStyle(.secondary) }
                    if let method = analysis.recordingMethodLabel { Text("기록 방식: " + method).font(.caption).foregroundStyle(.secondary) }
                    if analysis.hasStages {
                        SleepStageChart(entry: entry)
                        stageTimeline(entry)
                        ForEach([SleepStageType.awake, .light, .deep, .rem, .sleeping], id: \.rawValue) { type in
                            let minutes = analysis.minutes(for: type)
                            if type != .sleeping || minutes > 0 {
                                HStack { Circle().fill(color(type)).frame(width: 9, height: 9); Text(label(type)); Spacer(); Text(minutes > 0 ? number(minutes) + "분" : "제공 없음") }.font(.subheadline)
                            }
                        }
                        HStack { Text("미분류·단계 없는 구간"); Spacer(); Text(number(analysis.unclassifiedMinutes) + "분") }.font(.caption).foregroundStyle(.secondary)
                        Text("단계 분류 \(number(analysis.coverage * 100))% · 원본에 없는 구간은 추정하지 않아요.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("분류된 수면 단계 없음").font(.subheadline.bold()).accessibilityIdentifier("sleep-stages-missing")
                        Text("잠든 시간과 단계는 직접 기록만으로 판별할 수 없어요. 연결한 워치가 Samsung Health와 Health Connect에 공유한 단계만 표시해요.").font(.caption).foregroundStyle(.secondary)
                    }
                    if analysis.needsSourceConfirmation { Text("기기 정보 또는 분류 단계가 부족해 원본 기록 확인이 필요해요.").font(.caption).foregroundStyle(.secondary) }
                }.careCard().accessibilityIdentifier("sleep-detail-card")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("워치 수면 기록을 연결해보세요").font(.headline)
                    Text("Galaxy Watch → Android Samsung Health → Health Connect → iPhone. 건강 연결에서 두 앱을 같은 Wi-Fi에 열어두세요. 수면 단계가 공유되지 않은 기록은 시간만 표시해요.").font(.subheadline).foregroundStyle(.secondary)
                }.careCard()
            }
            Text("워치가 처리한 기록도 원본 앱의 추정값이에요. 이 화면은 수면 단계·건강 상태를 새로 진단하지 않아요.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func clockMetric(_ title: String, _ span: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(title).font(.caption).foregroundStyle(.secondary); Text(span.map { number($0) + "분" } ?? "기록 부족").font(.headline) }
    }
    private func time(_ date: Date) -> String { date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "ko_KR"))) }
    private func label(_ type: SleepStageType) -> String {
        switch type { case .awake: return "깨어 있음"; case .light: return "얕은 수면"; case .deep: return "깊은 수면"; case .rem: return "REM"; case .sleeping: return "수면 · 단계 미상"; case .unknown: return "미분류" }
    }
    private func color(_ type: SleepStageType) -> Color {
        switch type { case .awake: return Palette.coral; case .light: return Palette.blue; case .deep: return Color.indigo; case .rem: return Palette.purple; case .sleeping: return Palette.teal; case .unknown: return Color.gray.opacity(0.25) }
    }
    private func stageTimeline(_ entry: Entry) -> some View {
        Canvas { context, size in
            guard let bed = entry.bedTime, let wake = entry.wakeTime, wake > bed else { return }
            let seconds = wake.timeIntervalSince(bed)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color(.unknown)))
            for stage in entry.sleep?.stages ?? [] {
                let left = CGFloat(max(0, stage.start.timeIntervalSince(bed) / seconds)) * size.width
                let right = CGFloat(min(1, stage.end.timeIntervalSince(bed) / seconds)) * size.width
                context.fill(Path(CGRect(x: left, y: 0, width: max(0, right - left), height: size.height)), with: .color(color(stage.type)))
            }
        }.frame(height: 38).clipShape(RoundedRectangle(cornerRadius: 10)).accessibilityLabel("원본 수면 단계 시간표. 아래 목록에서 각 단계의 시간을 확인하세요.")
    }
}
