import SwiftUI
import UniformTypeIdentifiers
import Combine

struct MedicationHomeCard: View {
    @EnvironmentObject private var store: MedicationStore
    let open: () -> Void
    @State private var now = Date()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    private var plans: [MedicationPlan] { MedicationInsights.today(store.state, now: now) }
    private var confirmed: Int { plans.filter { store.checked($0.id, now: now) }.count }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("오늘의 복용 확인", systemImage: "pills.fill").font(.headline).foregroundStyle(Palette.teal)
            if !store.readable { Text("일정 파일을 확인하거나 투약 백업을 가져와주세요.").font(.subheadline).foregroundStyle(.secondary) }
            else if plans.isEmpty { Text("오늘 예정된 일정이 없어요").font(.subheadline).foregroundStyle(.secondary) }
            else { Text("오늘 \(confirmed) / \(plans.count)개 확인").font(.title2.bold()).accessibilityIdentifier("medication-home-count"); Text("직접 남긴 확인 기록이에요. 확인 없음이 미복용을 뜻하지는 않아요.").font(.caption).foregroundStyle(.secondary) }
            CareButton(title: "투약 알림 · 복용 일정 확인", color: Palette.teal, id: "medication-open", action: open)
        }.careCard().onReceive(timer) { now = $0 }.onAppear { now = Date() }
    }
}
struct MedicationHistoryView: View {
    @EnvironmentObject private var store: MedicationStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section { Text("최근 7일에 직접 남긴 복용 확인이에요. 확인이 없다고 미복용으로 판단하지 않아요. 약 이름은 현재 등록된 일정 기준입니다.").font(.subheadline).foregroundStyle(.secondary) }
                ForEach(MedicationInsights.history(store.state)) { day in
                    Section(koreanDate(day.date, weekday: true)) {
                        if day.confirmed.isEmpty { Text("복용 확인 기록 없음").foregroundStyle(.secondary) }
                        ForEach(day.confirmed) { plan in Label(plan.name + " · " + plan.timeLabel, systemImage: "checkmark.circle.fill").foregroundStyle(Palette.teal) }
                    }
                }
            }.navigationTitle("복용 확인 기록").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("닫기") { dismiss() } } }
        }
    }
}
struct MedicationBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct MedicationBackupView: View {
    @EnvironmentObject private var store: MedicationStore
    @Environment(\.dismiss) private var dismiss
    @State private var exporting = false
    @State private var importing = false
    @State private var pending: MedicationState?
    @State private var document = MedicationBackupDocument()
    @State private var message: String?
    @State private var busy = false
    var body: some View {
        NavigationStack {
            Form {
                Section("기기를 바꿀 때도 이어가요") {
                    Text("투약 일정과 보관된 날짜별 확인을 별도 JSON 파일로 저장해요. iPhone과 Android 온케어 3.7 사이에서 같은 파일을 사용할 수 있습니다.")
                    Text("약 이름과 복용 방법이 담긴 암호화되지 않은 파일이에요. 보관할 위치를 직접 선택하세요.").font(.caption).foregroundStyle(.secondary)
                    Button("투약 백업 저장") { do { document = MedicationBackupDocument(data: try MedicationTransfer.encode(store.state)); exporting = true } catch { message = "백업을 만들지 못했어요." } }.disabled(!store.readable).accessibilityIdentifier("medication-export")
                    Button("투약 백업 가져오기") { importing = true }.accessibilityIdentifier("medication-import")
                }
                if let pending { preview(pending) }
                if let message { Section { Text(message).accessibilityIdentifier("medication-backup-message") } }
            }.disabled(busy).navigationTitle("투약 백업").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("닫기") { dismiss() }.disabled(busy) } }
                .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "OnCare-Medications-" + dateKey(Date())) { result in switch result { case .success: message = "투약 백업을 저장했어요."; case .failure(let error): if !isFileSelectionCancelled(error) { message = "파일을 저장하지 못했어요." } } }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { read($0) }
                .interactiveDismissDisabled(busy)
        }
    }
    private func preview(_ state: MedicationState) -> some View {
        Section("가져오기 전 확인") {
            Text("일정 \(state.plans.count)개 · 확인 기록 \(state.checks.values.reduce(0) { $0 + $1.count })개").font(.headline)
            Text("기존 투약 일정과 확인 기록을 대체합니다. 가져온 알림은 모두 꺼집니다. 먼저 현재 투약 백업을 저장해두세요. 손상된 기존 파일이 있다면 원본을 기기에 따로 보존합니다.").font(.subheadline)
            ForEach(state.plans) { plan in
                VStack(alignment: .leading, spacing: 6) {
                    Text(plan.name + " · " + plan.timeLabel + " · " + plan.daysLabel)
                    if !plan.instructions.isEmpty { Text(plan.instructions).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Button("확인하고 대체하기", role: .destructive) { busy = true; Task { let replaced = await store.replaceFromBackup(state); message = store.message; if replaced { pending = nil }; busy = false } }.accessibilityIdentifier("medication-import-confirm")
            Button("취소") { pending = nil }.accessibilityIdentifier("medication-import-cancel")
        }
    }
    private func read(_ result: Result<URL, Error>) {
        pending = nil
        do {
            let url = try result.get(), scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
            pending = try MedicationTransfer.decode(file.read(upToCount: 65537) ?? Data()); message = nil
        } catch { if !isFileSelectionCancelled(error) { message = "지원하는 투약 백업인지 확인해주세요. 기존 일정은 바뀌지 않았어요." } }
    }
}
