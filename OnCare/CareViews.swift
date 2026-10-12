import SwiftUI
import Combine

struct RecordView: View {
    let kind: String
    let existing: Entry?
    @EnvironmentObject var journal: Journal
    @Environment(\.dismiss) var dismiss
    @State private var value: String
    @State private var mood: Int
    @State private var date: Date
    @State private var note: String
    @State private var exerciseType: String
    @State private var sets: String
    @State private var reps: String
    @State private var error = ""
    init(kind: String, existing: Entry? = nil, initialMood: Int = 3, initialType: String = "걷기") {
        self.kind = kind; self.existing = existing
        _value = State(initialValue: existing.map { rawNumber($0.value) } ?? "")
        _mood = State(initialValue: Int(existing?.value ?? Double(initialMood)))
        _date = State(initialValue: existing?.date ?? Date())
        _note = State(initialValue: existing?.note ?? "")
        _exerciseType = State(initialValue: existing?.type ?? initialType)
        _sets = State(initialValue: existing?.sets.flatMap { $0 > 0 ? String($0) : nil } ?? "")
        _reps = State(initialValue: existing?.reps.flatMap { $0 > 0 ? String($0) : nil } ?? "")
    }
    var parsed: Double? { kind == "마음" ? Double(mood) : inputNumber(value) }
    var valid: Bool {
        guard let n = parsed, n.isFinite, n > 0 else { return false }
        let max: Double = kind == "마음" ? 5 : kind == "체중" ? 500 : kind == "운동" ? 1440 : kind == "수면" ? 24 : 20000
        guard n <= max else { return false }
        if kind == "운동" {
            guard !exerciseType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            if !sets.isEmpty || !reps.isEmpty { guard let s = Int(sets), let r = Int(reps), (1...100).contains(s), (1...1000).contains(r) else { return false } }
        }
        return true
    }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(kind == "마음" ? "지금의 마음을 있는 그대로 남겨요." : "작은 기록부터 차근차근 쌓아보세요.").font(.subheadline).foregroundStyle(.secondary) }
                Section(kind + " 기록") {
                    if kind == "마음" {
                        HStack { ForEach(1...5, id: \.self) { score in
                            Button { mood = score } label: { VStack(spacing: 8) { MoodFace(score: score); Text(["힘듦", "지침", "보통", "좋음", "행복"][score-1]).font(.caption2) }.padding(.vertical, 10).frame(maxWidth: .infinity).background(mood == score ? Palette.purple.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain).accessibilityIdentifier("select-mood-\(score)").accessibilityLabel(moodNames[score-1])
                        } }
                    } else {
                        HStack { Text(kind); TextField("예: " + (kind == "체중" ? "72.4" : kind == "수면" ? "7.5" : kind == "운동" ? "30" : "300"), text: $value).keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityIdentifier("record-value"); Text(unit(kind)).foregroundStyle(.secondary) }
                    }
                    DatePicker("기록 시각", selection: $date, in: Date(timeIntervalSince1970: 1)...Date.now)
                }
                if kind == "운동" {
                    Section("운동 상세") {
                        TextField("운동 종류", text: $exerciseType).accessibilityIdentifier("exercise-type")
                        HStack { Text("세트 (선택)"); TextField("3", text: $sets).keyboardType(.numberPad).multilineTextAlignment(.trailing).accessibilityIdentifier("exercise-sets") }
                        HStack { Text("회 / 세트 (선택)"); TextField("12", text: $reps).keyboardType(.numberPad).multilineTextAlignment(.trailing).accessibilityIdentifier("exercise-reps") }
                        Text("세트와 횟수는 함께 입력해요.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if existing?.bedTime != nil { Section { Text("시각으로 계산한 수면 기록이에요. 수면량이나 기록 시각을 바꾸면 시각 상세 정보는 초기화돼요.").font(.caption).foregroundStyle(.secondary) } }
                Section(kind == "마음" ? "오늘의 이야기 (선택)" : "메모 (선택)") { TextField("편하게 적어주세요", text: $note, axis: .vertical).lineLimit(3...6).accessibilityIdentifier("record-note") }
                if !error.isEmpty { Section { Text(error).foregroundStyle(.red) } }
                if !valid && !value.isEmpty { Section { Text("숫자 범위와 선택 항목을 확인해주세요.").font(.caption).foregroundStyle(.secondary) } }
            }.navigationTitle(kind + (existing == nil ? " 기록" : " 기록 수정")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("저장") { save() }.disabled(!valid).accessibilityIdentifier("record-save") }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("완료") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } }
                }
                .onChange(of: note) { if $0.count > 2000 { note = String($0.prefix(2000)) } }
                .onChange(of: exerciseType) { if $0.count > 100 { exerciseType = String($0.prefix(100)) } }
        }
    }
    func save() {
        guard valid, let value = parsed else { return }
        var e = Entry(id: existing?.id ?? UUID().uuidString, date: date, kind: kind, value: value, note: note, type: kind == "운동" ? exerciseType : nil, sets: kind == "운동" ? Int(sets) : nil, reps: kind == "운동" ? Int(reps) : nil)
        if kind == "수면", let existing, existing.value == value, existing.date == date { e.bedTime = existing.bedTime; e.wakeTime = existing.wakeTime; e.awakeMinutes = existing.awakeMinutes; e.sleep = existing.sleep }
        if journal.save(e) { dismiss() } else { error = "저장하지 못했어요. 입력값과 저장 공간을 확인해주세요." }
    }
}

struct EntryCard: View {
    let entry: Entry
    let edit: () -> Void
    @EnvironmentObject var journal: Journal
    @State private var deleting = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Label(entry.kind == "운동" ? entry.type ?? "운동" : entry.kind, systemImage: symbol(entry.kind)).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.color(entry.kind)); Spacer(); Text(entry.date, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.secondary) }
            Text(entry.kind == "마음" ? moodNames[Int(entry.value)-1] : number(entry.value) + " " + unit(entry.kind)).font(.title3.bold())
            if let sets = entry.sets, let reps = entry.reps, sets > 0 { Text("\(sets)세트 × \(reps)회").font(.caption).foregroundStyle(.secondary) }
            if !entry.note.isEmpty { Text(entry.note).font(.subheadline).foregroundStyle(.secondary) }
            if entry.source?.hasPrefix("health-connect:") == true { Text("Health Connect에서 가져옴 · 원본에서 관리").font(.caption).foregroundStyle(.secondary) } else {
            HStack(spacing: 24) { Button("수정", action: edit); Button("삭제") { deleting = true }.foregroundStyle(.secondary) }.font(.caption).padding(.top, 4)
            }
        }.careCard().confirmationDialog("이 기록을 삭제할까요?", isPresented: $deleting, titleVisibility: .visible) { Button("삭제", role: .destructive) { journal.remove(entry.id) } }
    }
}
struct MindView: View {
    @EnvironmentObject var journal: Journal
    @State private var mood: Int?
    @State private var sheet: CareSheet?
    @State private var editing: Entry?
    var data: [Entry] { journal.daily("마음", from: dayOffset(-6)) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("마음에 귀 기울이는 시간").font(.largeTitle.bold())
                    VStack(alignment: .leading, spacing: 16) {
                        Text("지금의 마음은 어떤가요?").font(.headline); Text("감정을 고르고, 오늘의 이야기를 남겨보세요.").font(.subheadline).foregroundStyle(.secondary)
                        HStack { ForEach(1...5, id: \.self) { score in Button { mood = score } label: { VStack(spacing: 8) { MoodFace(score: score); Text(["힘듦", "지침", "보통", "좋음", "행복"][score-1]).font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity) }.buttonStyle(.plain).accessibilityIdentifier("mood-choice-\(score)") } }
                    }.careCard()
                    SectionTitle(title: "최근 7일, 마음의 흐름")
                    VStack(alignment: .leading, spacing: 12) { Text(data.isEmpty ? "아직 기록이 없어요" : number(data.reduce(0) { $0 + $1.value } / Double(data.count)) + " / 5").font(.title.bold()); Text("하루 마지막 체크인 기준 · \(data.count)일 기록").font(.caption).foregroundStyle(.secondary); TrendChart(entries: data, kind: "마음") }.careCard()
                    SectionTitle(title: "1분, 나를 위한 쉼")
                    VStack(alignment: .leading, spacing: 12) { Label("편안하게 호흡해요", systemImage: "wind").font(.headline); Text("들이쉬기 4초 · 내쉬기 6초").font(.subheadline).foregroundStyle(.secondary); CareButton(title: "호흡 시작", color: Palette.purple, id: "breathing-open") { sheet = .breathing }; Text("불편하면 언제든 멈추세요.").font(.caption).foregroundStyle(.secondary) }.careCard()
                    SectionTitle(title: "나의 마음 일기")
                    ForEach(Array(journal.entries.filter { $0.kind == "마음" }.prefix(3))) { e in EntryCard(entry: e) { editing = e } }
                }.padding(22)
            }.background(Color(.systemGroupedBackground)).navigationTitle("마음").navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: Binding(get: { mood != nil }, set: { if !$0 { mood = nil } })) { RecordView(kind: "마음", initialMood: mood ?? 3) }
                .sheet(item: $sheet) { SheetContents(sheet: $0) }.sheet(item: $editing) { RecordView(kind: $0.kind, existing: $0) }
        }
    }
}
struct BreathingView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) var phase
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var elapsed: Double = 0
    @State private var start: Double = 0
    @State private var running = false
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    var inhale: Bool { Int(elapsed) % 10 < 4 }
    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer(); Text(elapsed >= 60 ? "잘 쉬었어요" : running ? inhale ? "천천히 들이쉬기" : "편안하게 내쉬기" : "편안하게 호흡해요").font(.title2.bold())
                ZStack { Circle().stroke(Palette.purple.opacity(0.12), lineWidth: 10); Circle().trim(from: 0, to: elapsed/60).stroke(Palette.purple, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90)); VStack(spacing: 8) { Image(systemName: "wind").font(.system(size: 40)); Text("\(max(0,60-Int(elapsed)))초 남음").monospacedDigit() }.foregroundStyle(Palette.purple) }.frame(width: 210, height: 210).scaleEffect(running && inhale ? 1.05 : 1).animation(reduceMotion ? nil : .easeInOut(duration: 3), value: inhale)
                CareButton(title: running ? "잠시 멈추기" : elapsed >= 60 ? "다시 시작" : elapsed == 0 ? "호흡 시작" : "이어하기", color: Palette.purple, id: "breathing-toggle") { if running { running = false } else { if elapsed >= 60 { elapsed = 0 }; start = ProcessInfo.processInfo.systemUptime - elapsed; running = true } }
                Text("불편하면 언제든 멈추세요.").font(.caption).foregroundStyle(.secondary); Spacer()
            }.padding(30).navigationTitle("1분, 나를 위한 쉼").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
                .onReceive(timer) { _ in if running { elapsed = min(60, ProcessInfo.processInfo.systemUptime-start); if elapsed >= 60 { running = false } } }
                .onChange(of: phase) { if $0 != .active { running = false } }.onDisappear { running = false }
        }
    }
}
struct BodyView: View {
    @EnvironmentObject var journal: Journal
    @State private var range = 30
    @State private var sheet: CareSheet?
    @State private var exerciseType = "걷기"
    var weights: [Entry] { journal.daily("체중", from: dayOffset(1-range)) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("내 몸의 변화를 차근차근").font(.largeTitle.bold())
                    CareButton(title: "실천 센터 · 운동 시작하기", color: Palette.teal, id: "body-practice-open") { sheet = .practice }
                    Picker("기간", selection: $range) { ForEach([7,30,90], id: \.self) { Text("\($0)일").tag($0) } }.pickerStyle(.segmented)
                    weightCard
                    VStack(alignment: .leading, spacing: 12) { Label("오늘의 걸음", systemImage: "figure.walk").font(.headline).foregroundStyle(Palette.teal); Text(number(journal.sum("걸음", from: dayOffset(0))) + " 걸음").font(.title2.bold()); CareButton(title: "Android 건강 연결", id: "body-sync-open") { sheet = .healthConnection } }.careCard()
                    SectionTitle(title: "이번 주 움직임")
                    exerciseCard
                    SectionTitle(title: "기본 습관도 놓치지 않게")
                    waterCard
                    VStack(alignment: .leading, spacing: 14) { Label("오늘의 수면", systemImage: "moon").font(.headline).foregroundStyle(Palette.purple); Text(journal.latest("수면", today: true).map { number($0.value) + " 시간" } ?? "아직 기록 전").font(.title2.bold()); Text("내 목표 \(number(journal.goals.sleep))시간 · 오늘 입력한 최근 기록").font(.caption).foregroundStyle(.secondary); CareButton(title: "수면 기록하기", color: Palette.purple) { sheet = .sleep }; CareButton(title: "수면 루틴 · 취침 시간 계산", color: Palette.purple, id: "sleep-routine-open") { sheet = .sleepRoutine } }.careCard()
                }.padding(22)
            }.background(Color(.systemGroupedBackground)).navigationTitle("건강").navigationBarTitleDisplayMode(.inline)
                .sheet(item: $sheet) { if $0 == .exercise { RecordView(kind: "운동", initialType: exerciseType) } else { SheetContents(sheet: $0) } }
        }
    }
    var weightCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("체중 변화", systemImage: "scalemass").font(.headline).foregroundStyle(Palette.coral)
            Text(journal.latest("체중").map { number($0.value) + " kg" } ?? "— kg").font(.largeTitle.bold())
            if weights.count > 1 { let d = weights.last!.value-weights.first!.value; Text((d > 0 ? "+" : "") + number(d) + " kg · 선택 기간 첫 기록 대비").font(.caption).foregroundStyle(.secondary) }
            TrendChart(entries: weights, kind: "체중")
            HStack { Text(journal.goals.weight > 0 ? "내 목표 \(number(journal.goals.weight)) kg" : "목표 체중을 정해보세요").font(.subheadline.weight(.semibold)); Spacer(); Button("설정") { sheet = .goals } }
            if journal.goals.weight > 0, let latest = journal.latest("체중") { Text("목표까지 차이 \(number(abs(latest.value-journal.goals.weight))) kg").font(.caption).foregroundStyle(.secondary) }
            Text("그래프의 세로축은 기록 범위에 맞춰 조정돼요.").font(.caption2).foregroundStyle(.secondary)
            CareButton(title: "체중 기록하기", color: Palette.coral, filled: true, id: "body-weight-open") { sheet = .weight }
        }.careCard()
    }
    var exerciseCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("운동 목표", systemImage: "figure.walk").font(.headline).foregroundStyle(Palette.teal)
            let amount = journal.sum("운동", from: monday())
            Text("\(number(amount)) / \(number(journal.goals.exercise)) 분").font(.title2.bold())
            ProgressView(value: min(1,amount/journal.goals.exercise)).tint(Palette.teal)
            Text("월요일부터 오늘까지 · 직접 정한 주간 목표").font(.caption).foregroundStyle(.secondary)
            HStack { ForEach(["걷기","달리기","근력"], id: \.self) { type in CareButton(title: type, color: Palette.teal) { exerciseType = type; sheet = .exercise } } }
            CareButton(title: "운동 상세 기록", color: Palette.teal, filled: true) { sheet = .exercise }
        }.careCard()
    }
    var waterCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("수분", systemImage: "drop").font(.headline).foregroundStyle(Palette.blue)
            let amount = journal.sum("물", from: dayOffset(0))
            Text("\(number(amount)) / \(number(journal.goals.water)) ml").font(.title2.bold()); ProgressView(value: min(1,amount/journal.goals.water))
            HStack { ForEach([200,300,500], id: \.self) { n in CareButton(title: "+\(n)") { journal.save(Entry(kind: "물", value: Double(n))) } } }
            CareButton(title: "직접 입력") { sheet = .water }
        }.careCard()
    }
}
struct ReportView: View {
    @EnvironmentObject var journal: Journal
    @Environment(\.dismiss) var dismiss
    @State private var week = 0
    var length: Int { week == 0 ? (Calendar.current.component(.weekday, from: Date())+5)%7+1 : 7 }
    var start: Date { dayOffset(week*7, from: monday()) }
    var end: Date { dayOffset(length, from: start) }
    var prior: Date { dayOffset(-7, from: start) }
    var priorEnd: Date { dayOffset(length, from: prior) }
    func change(_ n: Double?, _ old: Double?, unit: String) -> String {
        guard let n, let old else { return "비교할 기록이 아직 부족해요" }; let delta = n-old
        return "지난주 같은 기간 대비 " + (delta > 0 ? "+" : "") + number(delta) + unit
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(koreanDate(start) + " – " + koreanDate(dayOffset(-1, from: end))).font(.headline)
                    Text(week == 0 ? "이번 주와 지난주를 같은 요일 수로 비교해요." : "완료된 한 주와 직전 한 주를 비교해요.").font(.caption).foregroundStyle(.secondary)
                    Picker("주", selection: $week) { Text("이번 주").tag(0); Text("지난주").tag(-1); Text("2주 전").tag(-2) }.pickerStyle(.segmented)
                    let dates = Set(journal.entries.filter { $0.date >= start && $0.date < end }.map { dateKey($0.date) })
                    report("나를 돌아본 날", "\(dates.count) / \(length)일", "기록을 한 번 이상 남긴 날짜 기준", Palette.blue)
                    let exercise = journal.sum("운동", from: start, to: end)
                    report("쌓인 움직임", number(exercise)+" 분", change(exercise,journal.sum("운동",from: prior,to: priorEnd),unit: " 분"), Palette.teal)
                    average("마음", suffix: " / 5")
                    average("수면", suffix: " 시간")
                    let weights = journal.daily("체중",from: start,to: end)
                    if weights.count > 1 { let d = weights.last!.value-weights.first!.value; report("체중 변화",(d > 0 ? "+" : "")+number(d)+" kg","선택 주의 첫 기록과 마지막 기록 비교",Palette.coral) }
                    if !journal.routines.isEmpty {
                        VStack(alignment: .leading, spacing: 16) { Text("루틴 실천").font(.headline); ForEach(journal.routines) { r in let n = (0..<length).filter { journal.checked(r.id,date: dayOffset($0,from: start)) }.count; VStack(alignment: .leading, spacing: 8) { Text("\(r.title) · \(n) / \(length)일").font(.subheadline); ProgressView(value: Double(n)/Double(length)).tint(Palette.teal) } } }.careCard()
                    }
                    Text("마음과 수면은 하루 마지막 기록으로 계산해요. 기록이 없는 날은 평균에서 제외해요.").font(.caption).foregroundStyle(.secondary)
                }.padding(22)
            }.background(Color(.systemGroupedBackground)).navigationTitle("나의 주간 리포트").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
    }
    func report(_ title: String,_ value: String,_ detail: String,_ color: Color) -> some View { VStack(alignment: .leading,spacing: 12) { Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(color); Text(value).font(.title.bold()); Text(detail).font(.caption).foregroundStyle(.secondary) }.careCard() }
    func average(_ kind: String,suffix: String) -> some View {
        let n = journal.mean(kind,from: start,to: end), previous = journal.mean(kind,from: prior,to: priorEnd)
        return report(kind+" 평균",n.map { number($0)+suffix } ?? "기록 전",change(n,previous,unit: kind == "마음" ? "점" : "시간")+" · \(journal.daily(kind,from: start,to: end).count)일 기록",Palette.purple)
    }
}
