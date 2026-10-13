import SwiftUI
import Combine

struct MedicationView: View {
    @EnvironmentObject private var store: MedicationStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing: MedicationPlan?
    @State private var deleting: MedicationPlan?
    @State private var now = Date()
    @State private var showHistory = false
    @State private var showBackup = false
    @Environment(\.scenePhase) private var phase
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    private var today: [MedicationPlan] { MedicationInsights.today(store.state, now: now) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) { Text("나를 챙기는 시간").font(.largeTitle.bold()); Text("처방받은 일정대로, 차분히 확인해요.").foregroundStyle(.secondary) }
                    progressCard
                    statusCard
                    HStack { Button("복용 확인 기록") { showHistory = true }.accessibilityIdentifier("medication-history-open"); Spacer(); Button("투약 백업") { showBackup = true }.accessibilityIdentifier("medication-backup-open") }
                    SectionTitle(title: "오늘의 복용 일정")
                    if today.isEmpty { Text("오늘 예정된 일정이 없어요").foregroundStyle(.secondary).careCard() }
                    ForEach(today) { plan in planCard(plan, today: true) }
                    SectionTitle(title: "등록한 일정 · \(store.state.plans.count) / 8")
                    CareButton(title: "복용 일정 추가", color: Palette.teal, filled: true, id: "medication-add") { editing = MedicationPlan(name: "", enabled: false) }.disabled(!store.readable || store.state.plans.count >= 8)
                    ForEach(store.state.plans) { plan in planCard(plan, today: false) }
                    Text("한 일정에 한 복용 시간을 등록해요. 하루 여러 번이면 일정을 각각 추가하세요. 복용 확인은 오늘의 기록이며 알림 시간을 바꾸지 않습니다. 투약 백업에서 일정과 확인 기록을 별도로 저장하고 옮길 수 있어요. 건강 기록 백업·자동 동기화와는 별도입니다.").font(.caption).foregroundStyle(.secondary)
                }.padding(22)
            }.background(Color(.systemGroupedBackground)).navigationTitle("투약 알림").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("닫기") { dismiss() } } }
                .sheet(item: $editing) { MedicationEditor(plan: $0) }
                .sheet(isPresented: $showHistory) { MedicationHistoryView() }
                .sheet(isPresented: $showBackup) { MedicationBackupView() }
                .onReceive(clock) { now = $0 }
                .onChange(of: phase) { if $0 == .active { now = Date() } }
                .alert("복용 일정을 삭제할까요?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                    Button("취소", role: .cancel) { deleting = nil }
                    Button("삭제", role: .destructive) { if let id = deleting?.id { Task { await store.remove(id) } }; deleting = nil }
                }.task { now = Date(); await store.refresh() }
        }
    }
    private var progressCard: some View {
        let checked = today.filter { store.checked($0.id, now: now) }.count
        let pending = today.filter { !store.checked($0.id, now: now) }
        return VStack(alignment: .leading, spacing: 12) {
            Label("오늘의 복용 확인", systemImage: "pills.fill").font(.headline).foregroundStyle(Palette.teal)
            Text("\(checked) / \(today.count)개 확인").font(.title.bold())
            if !today.isEmpty { ProgressView(value: Double(checked), total: Double(today.count)).tint(Palette.teal) }
            Text(pending.first.map { "남은 첫 일정 · " + $0.timeLabel + " · " + $0.name } ?? (today.isEmpty ? "등록한 요일에 맞춰 일정이 표시돼요." : "오늘 일정의 복용 확인을 모두 남겼어요.")).font(.subheadline)
            Text("확인 기록 기준입니다. 미확인은 미복용을 뜻하지 않으며, 지난 시간의 약을 추가로 복용하라는 안내가 아닙니다.").font(.caption).foregroundStyle(.secondary)
        }.careCard().accessibilityIdentifier("medication-today-progress")
    }
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(store.status, systemImage: "bell.badge").font(.subheadline.weight(.semibold)).accessibilityIdentifier("medication-status")
            Text("알림에는 약 이름을 표시하지 않아요. 집중 모드·알림 설정에 따라 표시나 소리가 달라질 수 있어요.").font(.caption).foregroundStyle(.secondary)
            if let message = store.message { Text(message).font(.caption).foregroundStyle(Palette.coral).accessibilityIdentifier("medication-message") }
            Button("알림 상태 다시 확인") { Task { await store.refresh() } }.accessibilityIdentifier("medication-refresh")
            Button("iPhone 알림 설정 열기") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
        }.careCard()
    }
    private func planCard(_ plan: MedicationPlan, today: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) { Text(plan.timeLabel).font(.title2.bold()).foregroundStyle(Palette.teal); Spacer(); Text(today && store.checked(plan.id, now: now) ? "복용 확인됨" : plan.enabled ? "알림 켜짐" : "알림 꺼짐").font(.caption).foregroundStyle(.secondary) }
            Text(plan.name).font(.headline).accessibilityIdentifier("medication-name-" + plan.id)
            Text(plan.daysLabel).font(.caption).foregroundStyle(.secondary)
            if !plan.instructions.isEmpty { Text(plan.instructions).font(.subheadline).foregroundStyle(.secondary) }
            if today { CareButton(title: store.checked(plan.id, now: now) ? "복용 확인 취소" : "오늘 복용 확인", color: Palette.teal, id: "medication-taken-" + plan.id) { now = Date(); store.toggleTaken(plan.id, now: now) } }
            else { HStack { Button("편집") { editing = plan }; Spacer(); Button("삭제", role: .destructive) { deleting = plan } } }
        }.careCard()
    }
}
struct MedicationEditor: View {
    @EnvironmentObject private var store: MedicationStore
    @Environment(\.dismiss) private var dismiss
    @State var plan: MedicationPlan
    @State private var showBagReader = false
    @State private var busy = false
    private var time: Binding<Date> {
        Binding(get: { Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: plan.hour, minute: plan.minute)) ?? Date() }, set: { plan.hour = Calendar.current.component(.hour, from: $0); plan.minute = Calendar.current.component(.minute, from: $0) })
    }
    var body: some View {
        NavigationStack {
            Form {
                Section { Button("약봉지 사진에서 글자 읽기") { showBagReader = true }.accessibilityIdentifier("medication-ocr-open"); Text("인식한 줄을 선택해 입력하세요. 약 이름·용량·시간은 원본과 직접 확인하며 자동으로 저장하지 않습니다.").font(.caption).foregroundStyle(.secondary) }
                Section("처방받은 복용 일정") {
                    TextField("약 이름", text: $plan.name).accessibilityIdentifier("medication-name")
                    TextField("복용 방법 · 처방대로 입력 (선택)", text: $plan.instructions, axis: .vertical).accessibilityIdentifier("medication-instructions")
                    DatePicker("복용 시간", selection: time, displayedComponents: .hourAndMinute)
                }
                Section("반복 요일") {
                    ForEach([(2,"월요일"),(3,"화요일"),(4,"수요일"),(5,"목요일"),(6,"금요일"),(7,"토요일"),(1,"일요일")], id: \.0) { day, title in
                        Toggle(title, isOn: Binding(get: { plan.weekdays.contains(day) }, set: { if $0 { plan.weekdays.insert(day) } else { plan.weekdays.remove(day) } }))
                    }
                }
                Section {
                    Toggle("알림 켜기", isOn: $plan.enabled).accessibilityIdentifier("medication-enabled")
                    Text("약의 용량이나 복용 시간을 온케어가 추천하지 않습니다. 복용 방법은 처방·약사 안내를 따라 입력하세요.").font(.caption).foregroundStyle(.secondary)
                    if let message = store.message { Text(message).font(.caption).foregroundStyle(Palette.coral) }
                }
            }.disabled(busy).navigationTitle("복용 일정 등록").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) { Button("취소") { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .navigationBarTrailing) { Button(busy ? "저장 중…" : "저장") { savePlan() }.disabled(busy).accessibilityIdentifier("medication-save") }
                }.interactiveDismissDisabled(busy)
                .sheet(isPresented: $showBagReader) { MedicationBagReader { value, name in if name { plan.name = String(value.prefix(80)) } else { plan.instructions = String(value.prefix(200)) }; plan.enabled = false } }
                .onAppear { store.message = nil }
        }
    }
    private func savePlan() {
        busy = true
        Task { if await store.save(plan) { dismiss() }; busy = false }
    }
}
