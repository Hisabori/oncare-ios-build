import SwiftUI

struct PersonalShareReport {
    static func text(entries: [Entry], kinds: Set<String>, days: Int, name: String = "", now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = days == 30 ? 30 : 7
        let start = calendar.date(byAdding: .day, value: 1-days, to: calendar.startOfDay(for: now))!
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let format = DateFormatter(); format.calendar = calendar; format.locale = Locale(identifier: "ko_KR"); format.timeZone = calendar.timeZone; format.dateFormat = "yyyy-MM-dd"
        var lines = ["온케어 · 나의 건강 요약", "기간: " + format.string(from: start) + " ~ " + format.string(from: now)]
        let label = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)).replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        if !label.isEmpty { lines.append("이름: " + label) }
        for kind in categories where kinds.contains(kind) {
            let records = entries.filter { $0.kind == kind && $0.date >= start && $0.date < end && $0.date <= now && $0.value.isFinite && $0.value > 0 }.sorted { $0.date < $1.date }
            guard let last = records.last else { lines.append(kind + ": 기록 없음"); continue }
            var daily: [Date: Double] = [:]
            for record in records { daily[calendar.startOfDay(for: record.date)] = record.value }
            if kind == "체중" { lines.append("체중 최근: " + number(last.value) + " kg (" + format.string(from: last.date) + ")") }
            else if ["운동", "물", "걸음"].contains(kind) { lines.append(kind + " 합계: " + number(records.reduce(0) { $0 + $1.value }) + " " + unit(kind) + " · " + String(daily.count) + "일 기록") }
            else { lines.append(kind + " 평균: " + number(daily.values.reduce(0,+) / Double(daily.count)) + " " + unit(kind) + " · " + String(daily.count) + "일 기록 (날짜별 마지막 기록)") }
        }
        lines.append("개인 기록 요약입니다. 진단·치료 판단용 자료가 아닙니다.")
        return lines.joined(separator: "\n")
    }
}
struct PersonalShareView: View {
    @EnvironmentObject var journal: Journal
    @Environment(\.dismiss) var dismiss
    @State private var days = 7
    @State private var selected: Set<String> = ["운동", "수면", "물", "걸음"]
    @State private var name = ""
    @State private var preview: String?
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("보낼 항목만 골라요. 마음·체중은 처음에는 꺼져 있어요. 메모, 투약 정보, 기기 연결 코드는 공유하지 않아요.").font(.subheadline) }
                Section("공유 범위") {
                    Picker("기간", selection: $days) { Text("최근 7일").tag(7); Text("최근 30일").tag(30) }.pickerStyle(.segmented)
                    ForEach(categories, id: \.self) { kind in Toggle(kind, isOn: Binding(get: { selected.contains(kind) }, set: { if $0 { selected.insert(kind) } else { selected.remove(kind) } })).accessibilityIdentifier("share-kind-" + kind) }
                    TextField("표시할 이름 (선택)", text: $name).accessibilityIdentifier("share-name").onChange(of: name) { name = String($0.prefix(40)) }
                    Text("이름은 이 화면에서만 사용해요. 기록이 있는 날짜만 계산하며, 없는 기록은 채우지 않아요.").font(.caption).foregroundStyle(.secondary)
                }
                Section { Button("공유 내용 미리보기") { preview = PersonalShareReport.text(entries: journal.entries, kinds: selected, days: days, name: name) }.disabled(selected.isEmpty).accessibilityIdentifier("share-preview") }
            }.navigationTitle("나의 정보 공유하기").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
                .sheet(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) { previewView }
        }
    }
    private var previewView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(preview ?? "").textSelection(.enabled).accessibilityIdentifier("share-preview-text")
                    Text("선택한 앱으로 보내면 해당 앱과 수신자가 이 내용을 볼 수 있어요.").font(.caption).foregroundStyle(.secondary)
                    ShareLink(item: preview ?? "") { Label("이 내용 공유하기", systemImage: "square.and.arrow.up") }.accessibilityIdentifier("share-send")
                }.padding(22)
            }.navigationTitle("공유 내용 확인").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("돌아가기") { preview = nil } } }
        }
    }
}

enum CareAppVersion {
    static var label: String { "온케어 " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") + " · 빌드 " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—") }
}
