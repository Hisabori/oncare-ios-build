import SwiftUI

struct AppleHealthView: View {
    @EnvironmentObject private var journal: Journal
    @StateObject private var health = AppleHealthStore()
    @State private var selected: Set<String> = ["StepsRecord", "ExerciseSessionRecord", "SleepSessionRecord", "HeartRateRecord", "WeightRecord", "MindfulnessSessionRecord", "StateOfMindRecord"]
    @State private var days = 7
    @State private var deleting = false
    @Environment(\.scenePhase) private var phase
    var body: some View {
        Form {
            Section("Apple 건강 · 피트니스") {
                Text("Apple 건강에 저장된 iPhone·Apple Watch·피트니스 앱의 공유 기록을 읽어요. 건강 앱이나 피트니스 링에 쓰지 않습니다.")
                Text("HealthKit이 허용된 서명 프로파일이 필요해요. 사이드로딩 도구가 권한을 제거하면 읽을 수 없습니다.").font(.caption).foregroundStyle(.secondary)
                Picker("조회 기간", selection: $days) { Text("7일").tag(7); Text("30일").tag(30) }.pickerStyle(.segmented)
                ForEach(AppleHealthType.all) { item in Toggle(item.title, isOn: Binding(get: { selected.contains(item.id) }, set: { if $0 { selected.insert(item.id) } else { selected.remove(item.id) } })) }
            }.disabled(health.busy)
            Section {
                Button("선택 항목 읽기 권한 요청") { Task { await health.update(journal, selected: selected, days: days, authorize: true) } }.disabled(health.busy || selected.isEmpty).accessibilityIdentifier("apple-health-authorize")
                Button("지금 새로고침") { Task { await health.update(journal, selected: selected, days: days, authorize: false) } }.disabled(health.busy || selected.isEmpty).accessibilityIdentifier("apple-health-refresh")
                if health.busy { ProgressView("Apple 건강 확인 중"); Button("결과 반영 취소") { health.cancel() } }
                Text(health.status).font(.subheadline).accessibilityIdentifier("apple-health-status")
                NavigationLink("연결된 건강 정보 보기") { HealthRecordsView() }
            }
            Section("측정값 그대로 확인해요") {
                Text("종류별 최근 최대 600개를 읽으며 일부만 조회하면 이전 기록을 덮어 지우지 않습니다. 수면 단계는 원본 값만 표시하고, 여러 앱의 겹치는 기록을 합산하거나 수면 점수를 만들지 않아요. 오늘 요약·직접 입력 기록과는 별도 보관합니다.").font(.caption)
                Text("마음 상태는 iOS 18 이상에서 원본 감정가·순간/하루 구분·감정 및 관련 요인 코드를 읽어요. 마음챙김 시간도 별도 표시합니다. 진단이나 5점 마음 점수로 바꾸지 않으며, AI 회고 입력에 넣지 않습니다.").font(.caption)
                Text("권한을 끄거나 원본 기록을 모두 지워 빈 결과가 되어도 기존 보관 자료는 자동 삭제하지 않아요. 아래 버튼으로 Apple 건강에서 받은 자료만 지울 수 있습니다.").font(.caption)
                Button("Apple 건강 보관 자료 지우기", role: .destructive) { deleting = true }.disabled(health.busy)
            }
        }.navigationTitle("Apple 건강 연결").navigationBarTitleDisplayMode(.inline)
        .onDisappear { health.cancel() }
        .onChange(of: phase) { if $0 == .background { health.cancel() } }
        .confirmationDialog("Apple 건강에서 받은 보관 자료를 지울까요?", isPresented: $deleting) { Button("보관 자료 지우기", role: .destructive) { var next = journal.state; next.healthRecords?.removeAll { $0.source == "apple-health" }; _ = journal.persist(next) } } message: { Text("Apple 건강 원본, Android에서 받은 기록과 직접 입력한 기록은 유지됩니다.") }
    }
}
