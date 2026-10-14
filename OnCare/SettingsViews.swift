import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct GoalEditor: View {
    @EnvironmentObject var journal: Journal
    @Environment(\.dismiss) var dismiss
    @State private var weight = ""
    @State private var exercise = "120"
    @State private var water = "1500"
    @State private var sleep = "7"
    @State private var error = ""
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("목표는 내 생활에 맞춰 자유롭게 정해요.").font(.subheadline).foregroundStyle(.secondary) }
                Section("나에게 맞는 목표") {
                    goal("목표 체중 · kg (선택)", text: $weight, id: "goal-weight")
                    goal("주간 운동 · 분", text: $exercise, id: "goal-exercise")
                    goal("하루 수분 · ml", text: $water, id: "goal-water")
                    goal("하루 수면 · 시간", text: $sleep, id: "goal-sleep")
                }
                if !error.isEmpty { Section { Text(error).foregroundStyle(.red) } }
            }.navigationTitle("나에게 맞는 목표").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("저장") { save() }.accessibilityIdentifier("goals-save") } }
                .onAppear { let g = journal.goals; weight = g.weight > 0 ? rawNumber(g.weight) : ""; exercise = rawNumber(g.exercise); water = rawNumber(g.water); sleep = rawNumber(g.sleep) }
        }
    }
    func goal(_ title: String,text: Binding<String>,id: String) -> some View { HStack { Text(title).font(.subheadline); TextField("숫자 입력",text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityIdentifier(id) } }
    func save() {
        func parse(_ s: String) -> Double? { inputNumber(s) }
        guard let w = weight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : parse(weight), let e = parse(exercise), let a = parse(water), let s = parse(sleep) else { error = "숫자를 다시 확인해주세요."; return }
        let g = CareGoals(weight: w,exercise: e,water: a,sleep: s)
        do { try g.validate(); if journal.setGoals(g) { dismiss() } else { error = "목표를 저장하지 못했어요." } } catch { self.error = "입력한 목표 범위를 확인해주세요." }
    }
}
struct RoutineEditor: View {
    @EnvironmentObject var journal: Journal
    @Environment(\.dismiss) var dismiss
    @State private var title = ""
    @State private var deleting: Routine?
    @State private var error = ""
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("완료 여부는 날짜별로 따로 보관해요. 최대 8개까지 추가할 수 있어요.").font(.subheadline).foregroundStyle(.secondary) }
                if !journal.routines.isEmpty { Section("내 루틴") { ForEach(journal.routines) { r in HStack { Text(r.title); Spacer(); Button("삭제",role: .destructive) { deleting = r } } } } }
                Section("새 루틴") {
                    TextField("예: 저녁 10분 산책",text: $title).accessibilityIdentifier("routine-title")
                    HStack { ForEach(["10분 걷기","스트레칭","마음 일기"],id: \.self) { s in Button(s) { title = s }.font(.caption).buttonStyle(.bordered) } }
                    Text("\(title.count) / 40자").font(.caption2).foregroundStyle(.secondary)
                }
                if !error.isEmpty { Section { Text(error).foregroundStyle(.red) } }
            }.navigationTitle("나의 루틴 만들기").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("추가") { if journal.addRoutine(title) { dismiss() } else { error = "이미 있는 루틴이거나 최대 8개를 채웠어요. 저장 공간도 확인해주세요." } }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 40).accessibilityIdentifier("routine-add") }
                }.onChange(of: title) { if $0.count > 40 { title = String($0.prefix(40)) } }
                .confirmationDialog("이 루틴과 완료 이력을 삭제할까요?",isPresented: Binding(get: { deleting != nil },set: { if !$0 { deleting = nil } }),titleVisibility: .visible) { Button("삭제",role: .destructive) { if let r = deleting { journal.deleteRoutine(r.id) }; deleting = nil } }
        }
    }
}
struct ReminderEditor: View {
    @Environment(\.dismiss) var dismiss
    @State private var enabled = UserDefaults.standard.bool(forKey: "reminder-enabled")
    @State private var time: Date = {
        let p = UserDefaults.standard; let hour = p.object(forKey: "reminder-hour") == nil ? 21 : p.integer(forKey: "reminder-hour")
        return Calendar.current.date(bySettingHour: hour,minute: p.integer(forKey: "reminder-minute"),second: 0,of: Date()) ?? Date()
    }()
    @State private var error = ""
    @State private var saving = false
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("하루 한 번, 마음과 실천을 돌아볼 시간을 정해요.").font(.subheadline).foregroundStyle(.secondary) }
                Section { Toggle("하루 기록 알림",isOn: $enabled).accessibilityIdentifier("reminder-toggle"); DatePicker("매일 알림 시간",selection: $time,displayedComponents: .hourAndMinute) }
                Section { Text("알림을 켤 때만 권한을 요청해요. 집중 모드나 휴대폰 설정에 따라 도착이 늦어질 수 있어요.").font(.caption).foregroundStyle(.secondary); Button("휴대폰 알림 설정 열기") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } }
                if !error.isEmpty { Section { Text(error).foregroundStyle(.red) } }
            }.disabled(saving).navigationTitle("하루 기록 알림").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() }.disabled(saving) }; ToolbarItem(placement: .confirmationAction) { Button(saving ? "저장 중" : "저장") { save() }.disabled(saving).accessibilityIdentifier("reminders-save") } }.interactiveDismissDisabled(saving)
        }
    }
    func save() {
        guard !saving else { return }
        saving = true
        let chosenEnabled = enabled, chosenTime = time
        Task { do { let c = Calendar.current.dateComponents([.hour,.minute],from: chosenTime); let ok = try await ReminderScheduler.update(enabled: chosenEnabled,hour: c.hour!,minute: c.minute!); saving = false; if ok { dismiss() } else { enabled = false; error = "알림을 켜지 않았어요. 휴대폰 설정에서 알림을 허용해주세요." } } catch { saving = false; enabled = UserDefaults.standard.bool(forKey: "reminder-enabled"); self.error = "저장하지 못했어요. 기존 알림 설정은 유지돼요." } }
    }
}
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct HistoryView: View {
    @EnvironmentObject var journal: Journal
    @State private var query = ""
    @State private var filter = "전체"
    @State private var days = 0
    @State private var editing: Entry?
    @State private var sharing = false
    @State private var reminders = false
    @State private var exporting = false
    @State private var importing = false
    @State private var document = BackupDocument(data: Data())
    @State private var pending: CareBackup?
    @State private var clearing = false
    var filtered: [Entry] {
        journal.entries.filter { e in
            let kindMatches = filter == "전체" || filter == e.kind || filter == "생활" && ["수면","물"].contains(e.kind)
            let dateMatches = days == 0 || e.date >= dayOffset(1-days)
            let text = e.kind + " " + e.note + " " + (e.type ?? "") + " " + dateKey(e.date)
            return kindMatches && dateMatches && (query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.localizedCaseInsensitiveContains(query.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading,spacing: 16) {
                    Text("나를 알아가는 기록").font(.largeTitle.bold())
                    TextField("기록 검색",text: $query).textFieldStyle(.roundedBorder).accessibilityIdentifier("journal-search").submitLabel(.search)
                    Picker("종류",selection: $filter) { ForEach(["전체","마음","체중","운동","생활"],id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
                    Picker("날짜",selection: $days) { Text("모든 날짜").tag(0); Text("최근 7일").tag(7); Text("최근 30일").tag(30) }.pickerStyle(.segmented)
                    Text("\(filtered.count)개 기록" + (filtered.count > 100 ? " · 최근 100개 표시" : "")).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("search-count")
                    if filtered.isEmpty { Text("일치하는 기록이 없어요. 검색어나 날짜 범위를 바꿔보세요.").font(.subheadline).foregroundStyle(.secondary) }
                    ForEach(Array(filtered.prefix(100))) { e in VStack(alignment: .leading,spacing: 10) { Text(e.date,format: .dateTime.month().day().weekday()).font(.caption).foregroundStyle(.secondary); EntryCard(entry: e) { editing = e } } }
                    SectionTitle(title: "내 기록은 내가 관리해요")
                    VStack(alignment: .leading,spacing: 14) {
                        Text("기록 · 목표 · 루틴을 한 번에").font(.headline); Text("백업은 건강 정보가 담긴 일반 JSON 파일이에요. 보관할 위치를 직접 선택해주세요.").font(.caption).foregroundStyle(.secondary)
                        CareButton(title: "나의 정보 공유하기",id: "personal-share-open") { sharing = true }
                        CareButton(title: "전체 백업하기",id: "backup-export") { export() }
                        CareButton(title: "백업에서 가져오기",id: "backup-import") { importing = true }
                        CareButton(title: "하루 기록 알림 설정",id: "history-reminders") { reminders = true }
                        Button("모든 기록 삭제",role: .destructive) { clearing = true }.font(.subheadline).padding(.vertical,10)
                    }.careCard()
                    Text(CareAppVersion.label + " · 개인 기록용 앱\n진단이나 치료를 제공하지 않아요.").accessibilityIdentifier("app-version").font(.caption).foregroundStyle(.secondary)
                }.padding(22)
            }.scrollDismissesKeyboard(.interactively).background(Color(.systemGroupedBackground)).navigationTitle("기록").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("완료") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to: nil,from: nil,for: nil) } } }
                .sheet(item: $editing) { RecordView(kind: $0.kind,existing: $0) }.sheet(isPresented: $reminders) { ReminderEditor() }.sheet(isPresented: $sharing) { PersonalShareView() }
                .fileExporter(isPresented: $exporting,document: document,contentType: .json,defaultFilename: "OnCare-"+dateKey(Date())) { result in switch result { case .success: journal.notice = "기록과 목표, 루틴을 백업했어요."; case .failure(let error): if !isFileSelectionCancelled(error) { journal.notice = "백업 파일을 저장하지 못했어요." } } }
                .fileImporter(isPresented: $importing,allowedContentTypes: [.json]) { result in read(result) }
                .confirmationDialog("백업을 가져올까요?",isPresented: Binding(get: { pending != nil },set: { if !$0 { pending = nil } }),titleVisibility: .visible) {
                    Button("가져오기") { if let backup = pending { let before = journal.entries.count; if journal.merge(backup) { journal.notice = "\(journal.entries.count-before)개 기록을 가져왔어요." } }; pending = nil }
                } message: { Text("\(pending?.entries.count ?? 0)개 기록을 중복 없이 합쳐요. 백업에 목표와 루틴이 있으면 해당 설정으로 바뀌어요. 알림 설정은 유지돼요.") }
                .confirmationDialog("모든 기록을 삭제할까요?",isPresented: $clearing,titleVisibility: .visible) { Button("삭제",role: .destructive) { journal.clear() } } message: { Text("목표와 루틴은 유지돼요. 삭제한 기록은 백업으로만 복구할 수 있어요.") }
        }
    }
    func export() { do { var out = journal.state; out.exportedAt = Date().timeIntervalSince1970*1000; document = BackupDocument(data: try out.encoded()); exporting = true } catch { journal.notice = "백업을 만들지 못했어요." } }
    func read(_ result: Result<URL,Error>) {
        do { let url = try result.get(); let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }; let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0; guard size <= 5*1024*1024 else { throw CareError.invalid }; pending = try CareBackup.decode(Data(contentsOf: url)) }
        catch { if !isFileSelectionCancelled(error) { journal.notice = "백업을 읽지 못했어요. 기존 기록은 그대로예요." } }
    }
}

struct AppPreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("app-theme") private var theme = "system"
    @AppStorage("app-start-tab") private var startTab = 0
    @AppStorage("app-mood-days") private var moodDays = 7
    @State private var reset = false
    var body: some View {
        NavigationStack { Form {
            Section("화면") {
                Picker("테마", selection: $theme) { Text("시스템 설정").tag("system"); Text("라이트").tag("light"); Text("다크").tag("dark") }.accessibilityIdentifier("preferences-theme")
                Picker("앱 시작 화면", selection: $startTab) { Text("오늘").tag(0); Text("마음").tag(1); Text("건강").tag(2); Text("기록").tag(3); Text("읽을거리").tag(4) }.accessibilityIdentifier("preferences-start-tab")
                Text("시작 화면은 다음 앱 실행부터 적용해요. 바로가기 링크는 요청한 화면을 먼저 엽니다.").font(.caption).foregroundStyle(.secondary)
            }
            Section("개인화와 도움") { NavigationLink("나에게 맞추기") { PersonalCareSettingsView() }; NavigationLink("도움과 위기지원") { CrisisSupportView() } }
            Section("기록 기본값") { Picker("마음 기록 조회 기간", selection: $moodDays) { Text("7일").tag(7); Text("30일").tag(30) }; Text("마음 화면을 새로 열 때 적용해요.").font(.caption).foregroundStyle(.secondary) }
            Section("알림과 앱 정보") { NavigationLink("하루 기록 알림") { ReminderEditor() }; Text("온케어 " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") + " · 빌드 " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")); Text("설정은 이 기기에 저장돼요. 건강 기록·투약 일정·연결 정보를 바꾸지 않습니다.").font(.caption).foregroundStyle(.secondary) }
            Section { Button("환경설정 기본값으로 복원") { reset = true }.accessibilityIdentifier("preferences-reset") }
        }.navigationTitle("앱 환경설정").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("닫기") { dismiss() } } }
        .confirmationDialog("환경설정만 기본값으로 복원할까요?", isPresented: $reset, titleVisibility: .visible) { Button("기본값 복원") { theme = "system"; startTab = 0; moodDays = 7 } }
        }
    }
}
