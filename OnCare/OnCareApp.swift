import SwiftUI
import Charts
import Combine

enum Palette {
    static let blue = Color(red: 0.22, green: 0.49, blue: 0.96)
    static let teal = Color(red: 0.09, green: 0.66, blue: 0.61)
    static let purple = Color(red: 0.55, green: 0.45, blue: 0.85)
    static let coral = Color(red: 0.91, green: 0.56, blue: 0.47)
    static func color(_ kind: String) -> Color { kind == "마음" || kind == "수면" ? purple : kind == "체중" ? coral : kind == "운동" ? teal : blue }
}
extension View {
    func careCard() -> some View { padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24)) }
}
struct CareButton: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let title: String
    var color: Color = Palette.blue
    var filled = false
    var id = ""
    let action: () -> Void
    var body: some View {
        Button(action: action) { Text(title).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 15).foregroundStyle(filled ? .white : color) .modifier(CareControlSurface(color: color, filled: filled, reduceTransparency: reduceTransparency)) }
            .buttonStyle(.plain).accessibilityIdentifier(id)
    }
}
struct SectionTitle: View { let title: String; var body: some View { Text(title).font(.title3.bold()).padding(.top, 8) } }
struct CheckRing: View {
    var done: Int
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: 6)
            Circle().trim(from: 0, to: CGFloat(done) / 4).stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 1) { Text("\(done)").font(.title.bold()); Text("/ 4").font(.caption) }.foregroundStyle(.white)
        }.frame(width: 86, height: 86).accessibilityElement(children: .ignore).accessibilityLabel("오늘 \(done)개 항목 기록 완료")
    }
}
struct MoodFace: View {
    let score: Int
    var body: some View {
        Canvas { context, size in
            let w = size.width
            context.fill(Path(ellipseIn: CGRect(origin: .zero, size: size)), with: .color(Palette.purple.opacity(0.12)))
            for x in [0.35, 0.65] { context.fill(Path(ellipseIn: CGRect(x: w*x-w*0.035, y: w*0.39, width: w*0.07, height: w*0.07)), with: .color(Palette.purple)) }
            var mouth = Path(); mouth.move(to: CGPoint(x: w*0.32, y: w*0.65))
            mouth.addQuadCurve(to: CGPoint(x: w*0.68, y: w*0.65), control: CGPoint(x: w*0.5, y: w*(score <= 2 ? 0.45 : score == 3 ? 0.65 : 0.88)))
            context.stroke(mouth, with: .color(Palette.purple), style: StrokeStyle(lineWidth: w*0.045, lineCap: .round))
        }.frame(width: 44, height: 44).accessibilityLabel(moodNames[max(0,min(4,score-1))])
    }
}
struct TrendChart: View {
    let entries: [Entry]
    let kind: String
    var domain: ClosedRange<Double> {
        if kind == "마음" { return 1...5 }
        let low = entries.map(\.value).min() ?? 0, high = entries.map(\.value).max() ?? 1
        let pad = max(0.5, (high-low)*0.2); return (low-pad)...(high+pad)
    }
    var body: some View {
        if entries.isEmpty {
            VStack(alignment: .leading, spacing: 6) { Text("기록이 쌓이면 흐름이 보여요").font(.subheadline.weight(.medium)); Text("없는 기록은 임의로 채우지 않아요.").font(.caption) }.foregroundStyle(.secondary).padding(.vertical, 20)
        } else {
            Chart(entries) { e in
                LineMark(x: .value("날짜", e.date, unit: .day), y: .value(kind, e.value)).foregroundStyle(Palette.color(kind)).lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(x: .value("날짜", e.date, unit: .day), y: .value(kind, e.value)).foregroundStyle(Palette.color(kind))
            }.chartYScale(domain: domain).chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisValueLabel(format: .dateTime.month().day()) } }.frame(height: 150)
                .accessibilityLabel("\(kind) 추세, \(entries.count)일 기록")
        }
    }
}
enum CareSheet: String, Identifiable {
    case survey, preferences, intelligence, healthConnection, sleepRoutine, practice, medications, widgetHelp
    case mood = "마음", weight = "체중", exercise = "운동", sleep = "수면", water = "물", goals, routines, report, reminders, breathing
    var id: String { rawValue }
}
struct SheetContents: View {
    let sheet: CareSheet
    var body: some View {
        switch sheet {
        case .survey: HealthSurveyView()
        case .preferences: AppPreferencesView()
        case .medications: MedicationView()
        case .widgetHelp: WidgetHelpView()
        case .intelligence: IntelligenceView()
        case .healthConnection: HealthConnectionView()
        case .sleepRoutine: SleepRoutineView()
        case .practice: PracticeView()
        case .goals: GoalEditor()
        case .routines: RoutineEditor()
        case .report: ReportView()
        case .reminders: ReminderEditor()
        case .breathing: BreathingView()
        default: RecordView(kind: sheet.rawValue)
        }
    }
}
@main struct OnCareApp: App {
    @UIApplicationDelegateAdaptor(CareShortcutAppDelegate.self) private var appDelegate
    @StateObject private var shortcuts = CareShortcutRouter.shared
    @StateObject private var medications = MedicationStore()
    @StateObject private var articles = ArticleLibrary()
    @StateObject private var journal = Journal()
    @StateObject private var sync = LocalHealthSync()
    @AppStorage("app-theme") private var theme = "system"
    init() { CareAppShortcuts.updateAppShortcutParameters() }
    var body: some Scene {
        WindowGroup {
            RootView().preferredColorScheme(theme == "dark" ? .dark : theme == "light" ? .light : nil).environmentObject(journal).environmentObject(sync).environmentObject(shortcuts).environmentObject(articles).environmentObject(medications).tint(Palette.blue).environment(\.locale, Locale(identifier: "ko_KR"))
                .onOpenURL { let accepted = shortcuts.open($0); print("OnCare link received at app root: accepted=\(accepted)") }
                .alert("온케어 안내", isPresented: Binding(get: { journal.notice != nil }, set: { if !$0 { journal.notice = nil } })) { Button("확인") { journal.notice = nil } } message: { Text(journal.notice ?? "") }
        }
    }
}
struct RootView: View {
    @StateObject private var medicationNavigation = MedicationNavigation.shared
    @EnvironmentObject private var medications: MedicationStore
    @EnvironmentObject private var shortcuts: CareShortcutRouter
    @State private var selectedTab = min(4, max(0, UserDefaults.standard.integer(forKey: "app-start-tab")))
    @State private var tabIdentity = UUID()
    @State private var shortcutSheet: CareSheet?
    @StateObject private var windowReference = CareWindowReference()
    @State private var windowReady = false
    @EnvironmentObject private var journal: Journal
    @EnvironmentObject private var sync: LocalHealthSync
    @Environment(\.scenePhase) private var scenePhase
    private let calendarTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    var body: some View {
        ZStack {
        TabView(selection: $selectedTab) {
            Dashboard().tabItem { Label("오늘", systemImage: "house") }.tag(0)
            MindView().tabItem { Label("마음", systemImage: "face.smiling") }.tag(1)
            BodyView().tabItem { Label("건강", systemImage: "waveform.path.ecg") }.tag(2)
            HistoryView().tabItem { Label("기록", systemImage: "list.bullet.rectangle") }.tag(3)
            ArticleLibraryView().tabItem { Label("읽을거리", systemImage: "book.closed") }.tag(4)
        }.id(tabIdentity)
        }
        .background(CarePresentationAnchor(reference: windowReference) { if !windowReady { windowReady = true } }.frame(width: 0, height: 0))
        .sheet(item: $shortcutSheet) { SheetContents(sheet: $0) }
        .task(id: scenePhase) { if scenePhase == .active { await medications.refresh() } }
        .task(id: String(describing: medicationNavigation.pending) + String(describing: scenePhase) + String(windowReady) + String(windowReference.generation)) {
            guard scenePhase == .active, windowReady, let request = medicationNavigation.pending, let window = windowReference.window else { return }
            await CareModalDismissal.dismiss(in: window)
            guard !Task.isCancelled, medicationNavigation.pending == request else { return }
            shortcutSheet = nil; tabIdentity = UUID(); selectedTab = 2
            do { try await Task.sleep(nanoseconds: 80_000_000) } catch { return }
            guard !Task.isCancelled, medicationNavigation.pending == request else { return }
            shortcutSheet = .medications; medicationNavigation.pending = nil
        }
        .task(id: String(describing: scenePhase) + (sync.pair?.peer ?? "") + (sync.pair?.token ?? "")) {
            guard scenePhase == .active, sync.pair != nil else { return }
            while !Task.isCancelled { await sync.sync(journal); do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { break } }
        }.onReceive(calendarTimer) { _ in journal.refreshCalendar() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in journal.refreshCalendar(force: true) }
            .onChange(of: scenePhase) { if $0 == .active { journal.refreshCalendar(force: true) } }
            .task(id: CareShortcutTaskKey(request: shortcuts.pending?.id, active: scenePhase == .active, windowReady: windowReady, windowGeneration: windowReference.generation)) {
                guard scenePhase == .active, windowReady, let request = shortcuts.pending, let window = windowReference.window else { print("OnCare link deferred: active=\(scenePhase == .active), ready=\(windowReady), window=\(windowReference.window != nil), pending=\(shortcuts.pending != nil)"); return }
                // Dismiss the current form without saving it. Recreate only tab view state so its local modal bindings cannot reopen.
                await CareModalDismissal.dismiss(in: window)
                guard !Task.isCancelled, shortcuts.pending?.id == request.id else { return }
                shortcutSheet = nil; tabIdentity = UUID(); selectedTab = request.destination.tab
                do { try await Task.sleep(nanoseconds: 80_000_000) } catch { return }
                guard !Task.isCancelled, shortcuts.pending?.id == request.id else { return }
                shortcutSheet = request.destination.sheet
                shortcuts.complete(request.id)
            }
    }
}
struct Dashboard: View {
    @EnvironmentObject var journal: Journal
    @State private var sheet: CareSheet?
    @State private var editingPins = false
    @State private var showingHighlights = false
    @AppStorage("summary-pins-v1") private var pinned = "걸음,마음,수면"
    var done: Int { ["마음", "체중", "운동", "물"].filter { journal.latest($0, today: true) != nil }.count }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) { Text(koreanDate(Date(), weekday: true)).font(.caption.weight(.semibold)).foregroundStyle(.secondary); Text("오늘도, 나답게").font(.largeTitle.bold()); Text("몸과 마음의 이야기를 만나보세요").font(.subheadline).foregroundStyle(.secondary) }
                    quickLog
                    pinnedSection
                    hero
                    CareButton(title: "실천 센터 · 운동 타이머와 루틴", color: Palette.teal, id: "practice-open") { sheet = .practice }
                    CareButton(title: "✦ Apple Intelligence로 돌아보기", id: "intelligence-open") { sheet = .intelligence }
                    SectionTitle(title: "오늘의 작은 실천")
                    routineCard
                    MedicationHomeCard { sheet = .medications }
                    SectionTitle(title: "지금의 나, 한눈에")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        metric("체중", value: journal.latest("체중").map { number($0.value) } ?? "—", detail: "최근 기록", sheet: .weight)
                        metric("운동", value: number(journal.sum("운동", from: dayOffset(0))), detail: "오늘 쌓은 움직임", sheet: .exercise)
                        metric("수면", value: journal.latest("수면", today: true).map { number($0.value) } ?? "—", detail: "오늘의 수면 기록", sheet: .sleep)
                        metric("물", value: number(journal.sum("물", from: dayOffset(0))), detail: "오늘 마신 물", sheet: .water)
                    }
                    SectionTitle(title: "오늘의 마음")
                    VStack(alignment: .leading, spacing: 16) {
                        HStack { MoodFace(score: Int(journal.latest("마음", today: true)?.value ?? 3)); VStack(alignment: .leading, spacing: 5) { Text(journal.latest("마음", today: true).map { moodNames[Int($0.value)-1] } ?? "오늘은 어떤 기분인가요?").font(.headline); Text("잠깐 멈춰, 마음을 살펴보세요").font(.caption).foregroundStyle(.secondary) } }
                        CareButton(title: "마음 체크인", color: Palette.purple, id: "open-mood") { sheet = .mood }
                    }.careCard()
                    highlightsSection
                    ArticleRecommendationsSection()
                    SectionTitle(title: "기록이 쌓이면, 흐름이 보여요")
                    VStack(alignment: .leading, spacing: 14) {
                        Text("나의 주간 리포트").font(.title3.bold()); Text("운동·마음·수면과 루틴을 지난주와 비교해요.").font(.subheadline).foregroundStyle(.secondary)
                        CareButton(title: "이번 주 돌아보기", filled: true, id: "report-open") { sheet = .report }
                        CareButton(title: "Android 건강 데이터 연결", id: "health-sync-open") { sheet = .healthConnection }
                        CareButton(title: "위젯 설치 확인", id: "widget-help-open") { sheet = .widgetHelp }
                        CareButton(title: "앱 환경설정", id: "app-preferences-open") { sheet = .preferences }
                        CareButton(title: "하루 기록 알림 설정", id: "reminders-open") { sheet = .reminders }
                    }.careCard()
                }.padding(22)
            }.background(summaryBackground).navigationTitle("요약").navigationBarTitleDisplayMode(.large)
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("목표 설정") { sheet = .goals }.font(.subheadline).accessibilityIdentifier("goals-open") } }
                .sheet(item: $sheet) { SheetContents(sheet: $0) }
                .sheet(isPresented: $editingPins) { SummaryPinEditor(encoded: $pinned) }
        }
    }
    private var summaryBackground: some View {
        ZStack(alignment: .top) { Color(.systemGroupedBackground); LinearGradient(colors: [Palette.purple.opacity(0.38), Palette.coral.opacity(0.18), Color(.systemGroupedBackground).opacity(0)], startPoint: .topLeading, endPoint: .bottomTrailing).frame(height: 390).allowsHitTesting(false) }.ignoresSafeArea()
    }
    private var quickLog: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("빠른 기록").font(.title2.bold())
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                quickTile("마음 상태", kind: "마음", icon: "brain.head.profile", selection: .mood, id: "summary-quick-mood")
                quickTile("수면", kind: "수면", icon: "bed.double.fill", selection: .sleepRoutine, id: "summary-quick-sleep")
                quickTile("체중", kind: "체중", icon: "scalemass.fill", selection: .weight, id: "summary-quick-weight")
                quickTile("투약", kind: nil, icon: "pills.fill", selection: .medications, id: "summary-quick-medication")
            }
        }
    }
    private func quickTile(_ title: String, kind: String?, icon: String, selection: CareSheet, id: String) -> some View {
        Button { sheet = selection } label: { HStack(spacing: 12) { Image(systemName: icon).font(.title2).foregroundStyle(kind.map(SummaryMetrics.color) ?? Palette.teal); VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline).foregroundStyle(.primary); Text(kind.flatMap { journal.latest($0) }.map { koreanDate($0.date) } ?? (kind == nil ? "복용 일정 확인" : "기록 시작하기")).font(.caption).foregroundStyle(.secondary) }; Spacer(minLength: 0) }.padding(18).frame(maxWidth: .infinity, minHeight: 88).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24)) }.buttonStyle(.plain).accessibilityIdentifier(id)
    }
    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("고정됨").font(.title2.bold()); Spacer(); Button("편집") { editingPins = true }.accessibilityIdentifier("summary-pins-edit") }
            ForEach(pinned.split(separator: ",").map(String.init).filter { ["걸음", "마음", "수면", "체중", "운동", "물"].contains($0) }, id: \.self) { kind in
                SummaryMetricCard(kind: kind) { sheet = summarySheet(kind) }
            }
            if pinned.isEmpty { Text("편집에서 요약에 보고 싶은 항목을 골라보세요.").font(.subheadline).foregroundStyle(.secondary).careCard() }
        }.padding(.top, 8)
    }
    private var highlightsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("하이라이트").font(.title2.bold())
            SummaryMetricCard(kind: "걸음", highlight: true) { sheet = .healthConnection }
            if showingHighlights {
                SummaryMetricCard(kind: "운동", highlight: true) { sheet = .practice }
                SummaryMetricCard(kind: "수면", highlight: true) { sheet = .sleepRoutine }
                SummaryMetricCard(kind: "마음", highlight: true) { sheet = .mood }
            }
            Button { showingHighlights.toggle() } label: { HStack { Label(showingHighlights ? "하이라이트 접기" : "모든 하이라이트 보기", systemImage: "list.bullet.clipboard"); Spacer(); Image(systemName: "chevron.right") }.padding(20).background(Color(.secondarySystemGroupedBackground), in: Capsule()) }.buttonStyle(.plain).accessibilityIdentifier("summary-highlights-all")
        }
    }
    private func summarySheet(_ kind: String) -> CareSheet { switch kind { case "걸음": return .healthConnection; case "마음": return .mood; case "수면": return .sleepRoutine; case "체중": return .weight; case "운동": return .exercise; default: return .water } }
    var hero: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Label("나의 하루 요약", systemImage: "heart.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.coral); Spacer(); Text("오늘").font(.caption).foregroundStyle(.secondary) }
            Text(done == 0 ? "지금의 나를,\n천천히 알아가요" : "나를 돌본 순간,\n오늘도 쌓이고 있어요").font(.system(.title, design: .rounded).weight(.bold)).fixedSize(horizontal: false, vertical: true)
            Text(done == 0 ? "작은 기록 하나로 오늘의 이야기를 시작해보세요." : "감정 · 체중 · 운동 · 수분 중 \(done)개를 기록했어요.").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ForEach(["마음", "체중", "운동", "물"], id: \.self) { kind in
                    VStack(spacing: 8) {
                        Image(systemName: journal.latest(kind, today: true) == nil ? symbol(kind) : "checkmark.circle.fill").font(.title3).foregroundStyle(Palette.color(kind))
                        Text(kind == "물" ? "수분" : kind).font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 12).background(Palette.color(kind).opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
                        .accessibilityElement(children: .ignore).accessibilityLabel(kind + (journal.latest(kind, today: true) == nil ? " 오늘 기록 없음" : " 오늘 기록 완료"))
                }
            }
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 30))
            .overlay(alignment: .topTrailing) { Circle().fill(Palette.coral.opacity(0.04)).frame(width: 130, height: 130).offset(x: 30, y: -35).allowsHitTesting(false).accessibilityHidden(true) }
            .clipShape(RoundedRectangle(cornerRadius: 30))
    }
    var routineCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text(journal.routines.isEmpty ? "나에게 맞는 작은 실천" : "오늘 \(journal.routines.filter { journal.checked($0.id) }.count) / \(journal.routines.count)개 완료").font(.headline); Spacer(); Button("편집") { sheet = .routines }.accessibilityIdentifier("routine-edit") }
            if journal.routines.isEmpty { Text("걷기, 스트레칭, 하루 한 줄 일기처럼\n내 생활에 맞는 습관을 골라보세요.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(Array(journal.routines.enumerated()), id: \.element.id) { index, r in
                Button { journal.toggle(r.id) } label: { HStack(spacing: 12) { Image(systemName: journal.checked(r.id) ? "checkmark.square.fill" : "square").font(.title2).foregroundStyle(Palette.teal); Text(r.title).foregroundStyle(.primary); Spacer() }.padding(.vertical, 6) }.buttonStyle(.plain).accessibilityIdentifier("routine-check-\(index)").accessibilityLabel(r.title + (journal.checked(r.id) ? ", 완료" : ", 미완료"))
            }
        }.careCard()
    }
    func metric(_ kind: String, value: String, detail: String, sheet selection: CareSheet) -> some View {
        Button { sheet = selection } label: {
            VStack(alignment: .leading, spacing: 14) { Label(kind == "물" ? "수분" : kind, systemImage: symbol(kind)).font(.subheadline.weight(.medium)).foregroundStyle(Palette.color(kind)); HStack(alignment: .firstTextBaseline, spacing: 4) { Text(value).font(.title.bold()); Text(unit(kind)).font(.caption).foregroundStyle(.secondary) }.foregroundStyle(.primary); Text(detail).font(.caption).foregroundStyle(.secondary) }.careCard()
        }.buttonStyle(.plain).accessibilityIdentifier("open-" + (kind == "체중" ? "weight" : kind == "운동" ? "exercise" : kind == "수면" ? "sleep" : "water"))
    }
}
