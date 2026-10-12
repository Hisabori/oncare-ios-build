import SwiftUI
import Combine

struct PracticeView: View {
    @EnvironmentObject private var journal: Journal
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var workout = WorkoutTimerStore()
    @State private var section = 0
    @State private var type = "걷기"
    @State private var goal = 20
    @State private var now = Date()
    @State private var message = ""
    @State private var resetting = false
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var savedSession: Bool { workout.hasSavedRecord(in: journal) }
    var goalSeconds: Double { let minutes = workout.session?.goalMinutes ?? goal; return Double(WorkoutSession.goals.contains(minutes) ? minutes : 20) * 60 }
    var seconds: Double { let value = (try? workout.session?.elapsed(at: now)) ?? workout.session?.elapsedSeconds ?? 0; return value.isFinite ? min(86400, max(0, value)) : 0 }
    var elapsedLabel: String {
        let n = Int(min(86400, max(0, seconds)))
        return n >= 3600 ? String(format: "%02d:%02d:%02d", n / 3600, n / 60 % 60, n % 60) : String(format: "%02d:%02d", n / 60, n % 60)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("오늘의 작은 실천").font(.largeTitle.bold())
                    Text("내 목표로 움직이고, 기록으로 돌아봐요.").font(.subheadline).foregroundStyle(.secondary)
                    Picker("실천 도구", selection: $section) { Text("운동 타이머").tag(0); Text("루틴").tag(1); Text("기록 분석").tag(2) }.pickerStyle(.segmented).accessibilityIdentifier("practice-section")
                    if section == 0 { timerCard } else if section == 1 { routineCards } else { PracticeInsightsView(day: Calendar.current.startOfDay(for: now)) }
                }.padding(22)
            }.background(Color(.systemGroupedBackground)).navigationTitle("실천 센터").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
                .confirmationDialog("운동 세션을 초기화할까요?", isPresented: $resetting, titleVisibility: .visible) {
                    Button("세션 초기화", role: .destructive) { perform { try workout.reset(); message = "새 운동을 시작할 수 있어요." } }.accessibilityIdentifier("workout-reset-confirm")
                } message: { Text("아직 저장하지 않은 시간은 사라져요. 이미 저장된 운동 기록은 유지돼요.") }
                .onAppear { refresh() }
                .onReceive(clock) { _ in if scenePhase == .active { refresh() } }
                .onChange(of: scenePhase) { phase in if phase == .active { refresh() } else { checkpoint() } }
                .onDisappear { checkpoint() }
        }
    }
    var timerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("내가 시작하는 운동", systemImage: "figure.walk").font(.headline).foregroundStyle(Palette.teal)
            if let session = workout.session {
                Text("\(session.type) · 목표 \(session.goalMinutes)분").font(.title3.bold())
                Text(elapsedLabel).font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit().accessibilityIdentifier("workout-elapsed")
                Text(savedSession ? "운동 기록 저장됨 · 세션 정리 대기" : session.finishedAt != nil ? "완료 · 기록 저장 대기" : session.running ? "운동 진행 중" : "일시정지").font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("workout-state")
                ProgressView(value: min(1, seconds / goalSeconds)).tint(Palette.teal)
                if seconds >= goalSeconds, workout.issue == nil { Text("목표 시간에 도달했어요. 완료를 눌러 기록을 남겨주세요.").font(.subheadline).foregroundStyle(Palette.teal) }
                if !session.running, session.finishedAt == nil, session.elapsedSeconds >= 86400 { Text("24시간에 도달해 일시정지했어요. 완료를 눌러 기록을 저장하거나 초기화해주세요.").font(.subheadline).foregroundStyle(Palette.teal) }
                if session.finishedAt == nil, session.elapsedSeconds < 86400, !savedSession {
                    CareButton(title: session.running ? "일시정지" : "계속", color: Palette.teal, id: "workout-toggle") { perform { let date = Date(); if session.running { try workout.pause(at: date) } else { try workout.resume(at: date) }; now = date; message = "" } }.disabled(workout.issue != nil)
                }
                CareButton(title: savedSession ? "저장된 세션 정리" : session.finishedAt == nil ? "완료하고 기록 저장" : "기록 저장 다시 시도", color: Palette.teal, filled: true, id: "workout-finish") { perform { let date = Date(); message = try workout.finish(in: journal, at: date); now = date } }.disabled(!workout.mayFinish(in: journal))
            } else {
                Text("운동 종류").font(.subheadline.weight(.semibold))
                Picker("운동 종류", selection: $type) { ForEach(WorkoutSession.types, id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented).accessibilityIdentifier("workout-type")
                Text("내 목표 시간").font(.subheadline.weight(.semibold))
                Picker("목표 시간", selection: $goal) { ForEach(WorkoutSession.goals, id: \.self) { Text("\($0)분").tag($0) } }.pickerStyle(.segmented).accessibilityIdentifier("workout-goal")
                CareButton(title: "운동 시작", color: Palette.teal, filled: true, id: "workout-start") { perform { let date = Date(); try workout.start(type: type, goal: goal, at: date); now = date; message = "" } }.disabled(workout.issue != nil)
            }
            if workout.session != nil || workout.issue != nil { Button("세션 초기화", role: .destructive) { resetting = true }.font(.subheadline).accessibilityIdentifier("workout-reset") }
            if let issue = workout.issue { Text(issue).font(.subheadline).foregroundStyle(.red).accessibilityIdentifier("workout-issue") }
            if !message.isEmpty { Text(message).font(.subheadline).foregroundStyle(Palette.teal).accessibilityIdentifier("workout-message") }
            Text("시작한 시각으로 시간을 계산해요. 화면이나 앱을 닫아도 이어지고, 일시정지한 시간은 제외해요. 직접 완료해야 기록되며 1분 이상, 최대 24시간만 저장할 수 있어요.").font(.caption).foregroundStyle(.secondary)
            Text("목표 도달은 앱 안에서만 안내해요. 백그라운드 알람이나 운동 자동 측정 기능은 아니에요.").font(.caption).foregroundStyle(.secondary)
        }.careCard()
    }
    var routineCards: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("최근 7일의 루틴").font(.title2.bold())
            Text("오늘을 포함한 7일이에요. 오늘 미완료라면 어제까지 이어진 실천일을 보여줘요.").font(.caption).foregroundStyle(.secondary)
            if journal.routines.isEmpty { Text("오늘 화면의 루틴 편집에서 내 작은 실천을 추가해주세요.").font(.subheadline).careCard() }
            ForEach(journal.routines) { routine in
                let summary = PracticeSummary.routine(routine.id, checks: journal.checks, now: now)
                VStack(alignment: .leading, spacing: 14) {
                    Text(routine.title).font(.headline)
                    Text("\(summary.completedCount) / 7일 완료 · \(summary.streak)일 연속 실천").font(.subheadline).foregroundStyle(Palette.teal)
                    HStack(spacing: 4) { ForEach(summary.days) { day in VStack(spacing: 8) { Text(day.date, format: .dateTime.weekday(.narrow)).font(.caption); Image(systemName: day.completed ? "checkmark.circle.fill" : "circle").foregroundStyle(day.completed ? Palette.teal : .secondary); Text(day.date, format: .dateTime.day()).font(.caption2) }.frame(maxWidth: .infinity).accessibilityElement(children: .ignore).accessibilityLabel(koreanDate(day.date) + (day.completed ? ", 완료" : ", 미완료")) } }
                    CareButton(title: journal.checked(routine.id) ? "오늘 완료 취소" : "오늘 완료하기", color: Palette.teal, id: "practice-routine-" + routine.id) { journal.toggle(routine.id) }
                }.careCard()
            }
        }
    }
    func perform(_ action: () throws -> Void) { do { try action() } catch { message = (error as? PracticeError)?.message ?? PracticeError.unreadable.message } }
    func refresh() { now = Date(); workout.observe(at: now) }
    func checkpoint() { guard workout.session != nil else { return }; do { try workout.checkpoint() } catch {} }
}

