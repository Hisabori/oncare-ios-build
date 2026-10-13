import SwiftUI
import Charts

struct SummaryDay: Identifiable {
    let date: Date
    let value: Double?
    var id: Date { date }
}
enum SummaryMetrics {
    static func days(_ entries: [Entry], kind: String, now: Date = Date()) -> [SummaryDay] {
        (0..<7).map { offset in
            let start = dayOffset(offset - 6, from: now)
            let end = dayOffset(1, from: start)
            let recorded = entries.filter { $0.kind == kind && $0.date >= start && $0.date < end && $0.date <= now }
            let value: Double?
            if recorded.isEmpty { value = nil }
            else if ["걸음", "운동", "물"].contains(kind) { value = recorded.reduce(0) { $0 + $1.value } }
            else { value = recorded.sorted { $0.date == $1.date ? $0.id > $1.id : $0.date > $1.date }.first?.value }
            return SummaryDay(date: start, value: value)
        }
    }
    static func mean(_ values: [SummaryDay]) -> Double? {
        let recorded = values.compactMap(\.value)
        return recorded.isEmpty ? nil : recorded.reduce(0, +) / Double(recorded.count)
    }
    static func color(_ kind: String) -> Color {
        kind == "걸음" || kind == "운동" ? .orange : kind == "마음" ? Palette.teal : Palette.color(kind)
    }
}
struct SummaryMetricCard: View {
    @EnvironmentObject private var journal: Journal
    let kind: String
    var highlight = false
    let action: () -> Void
    private var days: [SummaryDay] { SummaryMetrics.days(journal.entries, kind: kind) }
    private var mean: Double? { SummaryMetrics.mean(days) }
    private var color: Color { SummaryMetrics.color(kind) }
    private var latest: Entry? { journal.latest(kind) }
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label(kind == "물" ? "수분" : kind == "걸음" ? "걸음" : kind, systemImage: kind == "걸음" ? "figure.walk" : symbol(kind)).font(.headline).foregroundStyle(color)
                    Spacer()
                    if !highlight, let latest { Text(koreanDate(latest.date)).font(.caption).foregroundStyle(.secondary) }
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                if highlight {
                    Text(mean.map { "최근 7일 중 기록한 \(days.compactMap(\.value).count)일의 평균은 " + number($0) + " " + unit(kind) + "예요." } ?? "기록이 쌓이면 일주일의 흐름을 볼 수 있어요.")
                        .font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Divider()
                }
                HStack(alignment: .bottom, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        if highlight { Text("기록한 날의 평균").font(.caption.weight(.medium)).foregroundStyle(.secondary) }
                        if kind == "마음", !highlight {
                            Text(latest.map { moodNames[max(0, min(4, Int($0.value) - 1))] } ?? "아직 기록 전").font(.title2.bold())
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(highlight ? mean.map(number) ?? "—" : todayValue).font(.system(highlight ? .largeTitle : .title, design: .rounded).weight(.bold)).monospacedDigit()
                                Text(unit(kind)).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }.layoutPriority(1)
                    Spacer(minLength: 0)
                    if !highlight { miniChart.frame(width: 100, height: 64).accessibilityHidden(true) }
                }
                if highlight { largeChart.frame(height: 170) }
                if latest == nil { Text("데이터 없음 · 기록이나 건강 연결로 시작해요").font(.caption).foregroundStyle(.secondary) }
                if highlight { Text("오늘 포함 · 없는 날짜는 0으로 채우지 않아요.").font(.caption2).foregroundStyle(.secondary) }
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 30))
        }.buttonStyle(.plain).accessibilityIdentifier((highlight ? "summary-highlight-" : "summary-pinned-") + kind)
    }
    private var todayValue: String {
        if ["걸음", "운동", "물"].contains(kind) { return days.last?.value.map(number) ?? "—" }
        return latest.map { number($0.value) } ?? "—"
    }
    private var miniChart: some View {
        Chart(days) { day in
            if let value = day.value { BarMark(x: .value("날짜", day.date, unit: .day), y: .value(kind, value)).foregroundStyle(Calendar.current.isDateInToday(day.date) ? color : Color.secondary.opacity(0.25)).cornerRadius(3) }
        }.chartXAxis(.hidden).chartYAxis(.hidden).chartXScale(domain: days.first!.date...dayOffset(1, from: days.last!.date))
    }
    private var largeChart: some View {
        Chart {
            ForEach(days) { day in
                if let value = day.value { BarMark(x: .value("날짜", day.date, unit: .day), y: .value(kind, value)).foregroundStyle(Color.secondary.opacity(0.3)).cornerRadius(4) }
            }
            if let mean { RuleMark(y: .value("평균", mean)).foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round)) }
        }.chartXAxis { AxisMarks(values: days.map(\.date)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }.chartYAxis(.hidden)
            .chartXScale(domain: days.first!.date...dayOffset(1, from: days.last!.date))
            .accessibilityLabel(kind + " 최근 7일, " + String(days.compactMap(\.value).count) + "일 기록")
    }
}
struct SummaryPinEditor: View {
    @Binding var encoded: String
    @Environment(\.dismiss) private var dismiss
    private let choices = ["걸음", "마음", "수면", "체중", "운동", "물"]
    private var selected: [String] { encoded.split(separator: ",").map(String.init).filter { choices.contains($0) } }
    var body: some View {
        NavigationStack {
            List {
                Section("요약에 고정할 항목") {
                    ForEach(choices, id: \.self) { kind in
                        Button {
                            var next = selected
                            if next.contains(kind) { next.removeAll { $0 == kind } } else { next.append(kind) }
                            encoded = next.joined(separator: ",")
                        } label: { HStack { Label(kind == "물" ? "수분" : kind, systemImage: kind == "걸음" ? "figure.walk" : symbol(kind)); Spacer(); if selected.contains(kind) { Image(systemName: "checkmark").foregroundStyle(Palette.blue) } }.foregroundStyle(.primary) }
                        .accessibilityIdentifier("summary-pin-" + kind)
                    }
                }
                Text("선택한 순서로 표시해요. 기록과 목표는 바꾸지 않습니다.").font(.caption).foregroundStyle(.secondary)
            }.navigationTitle("고정 항목 편집").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
        }
    }
}
