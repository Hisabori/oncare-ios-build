import SwiftUI

struct SleepPlan: Codable, Equatable {
    var hour = 7
    var minute = 0
    var latency = 15
    var cycle = 90
    var cycles = 5
    func validate() throws {
        guard (0...23).contains(hour), (0...59).contains(minute), (0...90).contains(latency), (60...120).contains(cycle), (3...8).contains(cycles) else { throw CareError.invalid }
    }
    func nextWake(after now: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.nextDate(after: now, matching: DateComponents(hour: hour, minute: minute, second: 0), matchingPolicy: .nextTime) ?? now.addingTimeInterval(86400)
    }
    func bedtime(wake: Date, count: Int? = nil) -> Date { wake.addingTimeInterval(-Double(cycle * (count ?? cycles) + latency) * 60) }
    static func measuredHours(start: Date, end: Date, awake: Double) -> Double? {
        let minutes = end.timeIntervalSince(start) / 60
        guard minutes > 0, minutes <= 1440, awake.isFinite, awake >= 0, awake < minutes else { return nil }
        return (minutes - awake) / 60
    }
    static func load(defaults: UserDefaults = .standard) -> SleepPlan {
        guard let data = defaults.data(forKey: "sleep-plan"), let plan = try? JSONDecoder().decode(Self.self, from: data), (try? plan.validate()) != nil else { return SleepPlan() }; return plan
    }
    func save(defaults: UserDefaults = .standard) throws { try validate(); defaults.set(try JSONEncoder().encode(self), forKey: "sleep-plan") }
}
struct SleepRoutineView: View {
    @EnvironmentObject var journal: Journal
    @Environment(\.dismiss) private var dismiss
    @State private var showSound = false
    @State private var mode = 0
    @StateObject private var tracking = SleepTrackingStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date()
    @State private var trackingLatency = "15"
    @State private var trackingAwake = ""
    @State private var confirmingReset = false
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    @State private var plan = SleepPlan.load()
    @State private var wake = Date()
    @State private var start = Date().addingTimeInterval(-8 * 3600)
    @State private var end = Date()
    @State private var awake = ""
    @State private var message = ""
    @State private var trackingMessage = ""
    var nextWake: Date { plan.nextWake() }
    var awakeMinutes: Double? { awake.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : inputNumber(awake) }
    var measured: Double? { awakeMinutes.flatMap { SleepPlan.measuredHours(start: start, end: end, awake: $0) } }
    var recent: [Entry] { journal.daily("수면", from: dayOffset(-6)) }
    func time(_ date: Date) -> String { date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "ko_KR"))) }
    var body: some View {
        NavigationStack {
            sleepContent
                .navigationTitle("수면 루틴").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("완료") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } }
                }
                .sheet(isPresented: $showSound) { SleepSoundView() }
                .onAppear(perform: configureWake)
                .onChange(of: mode) { _ in clearMessages() }
                .onDisappear(perform: checkpointTracking)
                .onReceive(clock, perform: refreshClock)
                .onChange(of: scenePhase, perform: phaseChanged)
                .alert("취침 기록을 초기화할까요?", isPresented: $confirmingReset) { resetActions } message: { Text("진행 중인 취침 기록을 버려요. 이미 저장한 수면 기록은 유지돼요.") }
        }
    }
    private var sleepContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("내 생활에 맞춘 수면 루틴").font(.largeTitle.bold())
                Button { showSound = true } label: { Label("마이크로 수면 소리 기록", systemImage: "waveform").frame(minHeight: 44) }.accessibilityIdentifier("sleep-sound-open")
                Picker("수면 도구", selection: $mode) { Text("취침 계산").tag(0); Text("수면 기록").tag(1); Text("수면 분석").tag(2) }.pickerStyle(.segmented).accessibilityIdentifier("sleep-mode")
                if mode == 0 { planner } else if mode == 1 { logger } else { SleepInsightsView(entries: journal.entries, goal: journal.goals.sleep, now: now) }
                if !message.isEmpty { Text(message).font(.subheadline).foregroundStyle(Palette.purple).accessibilityIdentifier("sleep-message") }
                if mode != 2 { recentCard }
            }.padding(22)
        }.background(Color(.systemGroupedBackground))
    }
    @ViewBuilder private var resetActions: some View {
        Button("초기화", role: .destructive) { performTracking { try tracking.reset(); trackingMessage = "취침 기록을 초기화했어요." } }.accessibilityIdentifier("sleep-tracking-reset-confirm")
        Button("계속 기록", role: .cancel) {}.accessibilityIdentifier("sleep-tracking-reset-cancel")
    }
    private func configureWake() { wake = Calendar.current.date(bySettingHour: plan.hour, minute: plan.minute, second: 0, of: Date()) ?? Date() }
    private func clearMessages() { message = ""; trackingMessage = "" }
    private func refreshClock(_ value: Date) { now = value; tracking.observe(at: value) }
    private func checkpointTracking() { if tracking.session != nil { try? tracking.checkpoint() } }
    private func phaseChanged(_ value: ScenePhase) {
        now = Date(); tracking.observe(at: now)
        if value != .active, tracking.session != nil {
            do { try tracking.checkpoint(at: now) } catch { trackingMessage = (error as? SleepTrackingError)?.message ?? SleepTrackingError.unreadable.message }
        }
    }
    var recentSummary: String {
        guard !recent.isEmpty else { return "기록을 남기면 흐름이 보여요" }
        let mean = recent.reduce(0.0) { $0 + $1.value } / Double(recent.count)
        return "하루 마지막 기록 평균 " + number(mean) + "시간 · \(recent.count)일"
    }
    var recentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("최근 7일 수면").font(.headline)
            Text(recentSummary).font(.subheadline).foregroundStyle(.secondary)
            TrendChart(entries: recent, kind: "수면")
            ForEach(Array(recent.suffix(3).reversed())) { entry in
                VStack(alignment: .leading, spacing: 5) {
                    Text(koreanDate(entry.date) + " · " + number(entry.value) + "시간").font(.subheadline.bold())
                    if let bed = entry.bedTime, let wake = entry.wakeTime { Text(time(bed) + " → " + time(wake) + " · 깨어 있던 시간 " + number(entry.awakeMinutes ?? 0) + "분").font(.caption).foregroundStyle(.secondary) }
                    Text(entry.sleepAnalysis?.sourceLabel ?? (entry.source == nil ? "직접 입력한 기록" : "Health Connect에서 가져온 기록")).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }.careCard()
    }
    var planner: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text("기상 시간에서 거꾸로 계산해요").font(.headline)
                DatePicker("원하는 기상 시간", selection: $wake, displayedComponents: .hourAndMinute).onChange(of: wake) { date in let parts = Calendar.current.dateComponents([.hour, .minute], from: date); plan.hour = parts.hour ?? 7; plan.minute = parts.minute ?? 0 }
                Stepper("잠드는 데 \(plan.latency)분", value: $plan.latency, in: 0...90, step: 5)
                Stepper("예상 수면 주기 \(plan.cycle)분", value: $plan.cycle, in: 60...120, step: 5)
                Stepper("계산할 주기 \(plan.cycles)회", value: $plan.cycles, in: 3...8)
            }.careCard()
            VStack(alignment: .leading, spacing: 14) {
                Text("침대에 누울 예상 시각").font(.headline)
                let bedtime = plan.bedtime(wake: nextWake)
                Text(time(bedtime)).font(.largeTitle.bold()).foregroundStyle(Palette.purple).accessibilityIdentifier("sleep-bedtime")
                Text(koreanDate(bedtime) + " 취침 준비 → " + koreanDate(nextWake) + " " + time(nextWake) + " 기상").font(.subheadline)
                Text("수면 \(number(Double(plan.cycle * plan.cycles) / 60))시간 + 잠드는 시간 \(plan.latency)분").font(.caption).foregroundStyle(.secondary)
                if bedtime < Date() { Text("계산한 취침 시각이 이미 지났어요. 기상 계획이나 계산 조건을 바꿔보세요.").font(.caption).foregroundStyle(.secondary) }
                CareButton(title: "이 수면 루틴 저장", color: Palette.purple, id: "sleep-plan-save") { do { try plan.save(); message = "수면 루틴을 저장했어요. 알람은 설정하지 않았어요." } catch { message = "루틴을 저장하지 못했어요." } }
            }.careCard()
            VStack(alignment: .leading, spacing: 12) {
                Text("다른 주기 수로 비교").font(.headline)
                ForEach([4,5,6], id: \.self) { count in HStack { Text("\(count)회 · \(number(Double(count * plan.cycle) / 60))시간"); Spacer(); Text(time(plan.bedtime(wake: nextWake, count: count))).fontWeight(.semibold) } }
                Text("주기 길이는 사람과 밤마다 달라요. 기본 90분은 계산용 가정이며, 실제 수면 단계 측정이나 개운한 기상을 보장하지 않아요. 충분한 수면 시간을 먼저 고려하세요.").font(.caption).foregroundStyle(.secondary)
            }.careCard()
        }
    }
    var logger: some View {
        VStack(alignment: .leading, spacing: 16) {
            trackingCard
            VStack(alignment: .leading, spacing: 14) {
                Text("지난 수면을 시각으로 기록해요").font(.headline)
                VStack(alignment: .leading, spacing: 8) { Text("잠든 시각"); DatePicker("잠든 시각", selection: $start, in: Date(timeIntervalSince1970: 1)...Date()).labelsHidden() }
                VStack(alignment: .leading, spacing: 8) { Text("깬 시각"); DatePicker("깬 시각", selection: $end, in: Date(timeIntervalSince1970: 1)...Date()).labelsHidden() }
                HStack { Text("중간에 깨어 있던 분"); TextField("0", text: $awake).keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityIdentifier("sleep-awake") }
                Text(measured.map { "계산된 수면 " + number($0) + "시간" } ?? "깬 시각은 잠든 시각보다 뒤여야 해요. 깨어 있던 시간과 24시간 이내의 기록을 확인해주세요.").font(.subheadline).foregroundStyle(measured == nil ? .secondary : Palette.purple).accessibilityIdentifier("sleep-measured")
                CareButton(title: "계산한 수면 기록하기", color: Palette.purple, filled: true, id: "sleep-measured-save") {
                    guard let hours = measured, let awake = awakeMinutes else { return }
                    let entry = Entry(date: end, kind: "수면", value: hours, bedTime: start, wakeTime: end, awakeMinutes: awake)
                    if journal.save(entry) { message = "수면 " + number(hours) + "시간을 기록했어요." } else { message = "기록하지 못했어요. 입력값과 저장 공간을 확인해주세요." }
                }.disabled(measured == nil)
                Text("깬 시각 − 잠든 시각 − 깨어 있던 시간으로 계산합니다. 직접 입력한 추정이며 자동 센서 측정이 아니에요. 같은 수면을 Health Connect에서 이미 가져왔다면 중복으로 기록하지 마세요.").font(.caption).foregroundStyle(.secondary)
            }.careCard()
        }
    }

    var trackingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("취침부터 기상까지 기록").font(.headline)
            if let session = tracking.session {
                Text("취침 시작: " + koreanDate(session.startedAt) + " " + time(session.startedAt)).font(.subheadline).accessibilityIdentifier("sleep-tracking-state")
                if session.finishedAt != nil { Text("기상 시각을 고정했어요. 저장을 다시 시도해주세요.").font(.caption).foregroundStyle(.secondary)
                    Text("잠드는 시간 " + number(session.latency ?? 0) + "분 · 깨어 있던 시간 " + number(session.awake ?? 0) + "분").font(.caption)
                } else {
                HStack { Text("잠드는 데 걸린 분"); TextField("15", text: $trackingLatency).keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityIdentifier("sleep-tracking-latency") }
                HStack { Text("중간에 깨어 있던 분"); TextField("0", text: $trackingAwake).keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityIdentifier("sleep-tracking-awake") }
                }
                CareButton(title: "기상 완료 · 수면 저장", color: Palette.purple, filled: true, id: "sleep-tracking-finish") {
                    performTracking {
                        if session.finishedAt != nil || tracking.hasSavedRecord(in: journal) {
                            trackingMessage = try tracking.finish(in: journal, latency: 0, awake: 0)
                        } else {
                            guard let latency = inputNumber(trackingLatency), let awake = trackingAwake.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : inputNumber(trackingAwake) else { throw SleepTrackingError.invalid }
                            trackingMessage = try tracking.finish(in: journal, latency: latency, awake: awake)
                        }
                    }
                }.disabled(tracking.issue != nil && !tracking.hasSavedRecord(in: journal))
                Button("취침 기록 초기화", role: .destructive) { confirmingReset = true }.accessibilityIdentifier("sleep-tracking-reset")
            } else {
                CareButton(title: "취침 기록 시작", color: Palette.purple, filled: true, id: "sleep-tracking-start") { performTracking { try tracking.start(); trackingLatency = String(plan.latency); trackingMessage = "취침 시각을 저장했어요. 아침에 기상 완료를 눌러주세요." } }.disabled(tracking.issue != nil)
            }
            if !trackingMessage.isEmpty { Text(trackingMessage).font(.subheadline).foregroundStyle(Palette.purple).accessibilityIdentifier("sleep-tracking-message") }
            if let issue = tracking.issue { Text(issue).font(.caption).foregroundStyle(.secondary); if tracking.session == nil { Button("취침 상태 초기화", role: .destructive) { confirmingReset = true } } }
            Text("앱을 닫아도 시작 시각을 복구해요. 기상 완료 시 잠드는 시간과 깨어 있던 분을 빼서 추정합니다. 움직임·소리·수면 단계를 자동 측정하거나 알람을 울리지 않아요.").font(.caption).foregroundStyle(.secondary)
        }.careCard()
    }
    func performTracking(_ action: () throws -> Void) {
        do { try action() } catch { trackingMessage = (error as? SleepTrackingError)?.message ?? SleepTrackingError.unreadable.message }
    }
}
