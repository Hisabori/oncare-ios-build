import SwiftUI
import FoundationModels

struct CareControlSurface: ViewModifier {
    var color: Color
    var filled: Bool
    var reduceTransparency: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular.tint(color.opacity(filled ? 0.9 : 0.12)).interactive(), in: RoundedRectangle(cornerRadius: 18))
        } else {
            content.background(filled ? color : color.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
        }
    }
}

enum IntelligenceContext {
    @MainActor static func snapshot(_ journal: Journal, now: Date = Date(), days requestedDays: Int = 7) -> String {
        let period = IntelligencePolicy.period(requestedDays)
        let start = dayOffset(1 - period, from: now)
        let end = now.addingTimeInterval(0.001)
        let entries = journal.entries.filter { $0.date >= start && $0.date < end }
        let days = Set(entries.map { dateKey($0.date) }).count
        let mood = journal.mean("마음", from: start, to: end).map(number) ?? "기록 없음"
        let sleep = journal.mean("수면", from: start, to: end).map(number) ?? "기록 없음"
        // Free text, notes, routine titles and exercise names never enter the model prompt.
        return """
        최근 \(period)일의 실제 기록 통계:
        기록한 날: \(days)/\(period)일
        운동 합계: \(number(journal.sum("운동", from: start, to: end)))분
        마음 평균: \(mood)/5 (하루 마지막 기록, \(journal.daily("마음", from: start, to: end).count)일)
        수면 평균: \(sleep)시간 (하루 마지막 기록, \(journal.daily("수면", from: start, to: end).count)일)
        수분 기록 합계: \(number(journal.sum("물", from: start, to: end)))ml (\(period)일 합계)
        루틴 완료 횟수: \((0..<period).reduce(0) { count, offset in count + journal.routines.filter { journal.checked($0.id, date: dayOffset(offset, from: start)) }.count })
        기록이 없는 날의 실제 활동과 상태는 알 수 없음.
        """
    }
}

struct IntelligenceView: View {
    @EnvironmentObject var journal: Journal
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
            if #available(iOS 26.0, *) {
                IntelligenceContent().environmentObject(journal)
            } else {
                ScrollView { VStack(spacing: 20) {
                    Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(Palette.purple)
                    Text("iOS 26 이상에서 사용할 수 있어요").font(.title3.bold())
                    Text("Apple Intelligence 지원 기기에서 기능을 켜면, 기기 안에서 기록을 돌아볼 수 있어요. 기존 기록과 리포트는 계속 사용할 수 있어요.").foregroundStyle(.secondary)
                    Text("실제 기록 통계 · AI 생성 아님").font(.headline)
                    Text(IntelligenceContext.snapshot(journal)).textSelection(.enabled)
                }.padding(28) }
            }
            }.toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
    }
}

@available(iOS 26.0, *)
struct IntelligenceContent: View {
    @EnvironmentObject var journal: Journal
    @Environment(\.scenePhase) private var scenePhase
    @State private var days = 7
    @State private var focus = "균형 있게"
    @State private var request = 0
    @State private var context = ""
    @State private var result = ""
    @State private var failure = ""
    @State private var generating = false
    @State private var available = false
    @State private var status = "지원 상태 확인 중"
    var preview: String { IntelligenceContext.snapshot(journal, days: days) }
    var hasRecords: Bool { let now = Date(); return journal.entries.contains { $0.date >= dayOffset(1 - days, from: now) && $0.date <= now } }
    func invalidate() { generating = false; request += 1; result = ""; failure = ""; context = "" }
    func refreshAvailability() {
        switch SystemLanguageModel.default.availability {
        case .available:
            available = SystemLanguageModel.default.supportsLocale(Locale(identifier: "ko_KR"))
            status = available ? "기기 안에서 처리 · Apple Intelligence" : "현재 모델이 한국어를 지원하지 않아요. iOS와 모델을 업데이트해주세요."
        case .unavailable(let reason):
            available = false
            switch reason {
            case .deviceNotEligible: status = "이 기기는 Apple Intelligence를 지원하지 않아요."
            case .appleIntelligenceNotEnabled: status = "설정에서 Apple Intelligence를 켜주세요."
            case .modelNotReady: status = "기기 내 모델 준비 중이에요. 다운로드가 끝나면 다시 확인해주세요."
            @unknown default: status = "현재 언어·지역 또는 기기 설정에서 사용할 수 없어요."
            }
        @unknown default: available = false; status = "현재 Apple Intelligence를 사용할 수 없어요."
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "sparkles").font(.system(size: 36)).foregroundStyle(LinearGradient(colors: [Palette.blue, Palette.purple, Palette.coral], startPoint: .leading, endPoint: .trailing))
                Text("기록에서 발견하는 나").font(.largeTitle.bold())
                Text("내가 고른 기간과 방식으로 기록을 돌아봐요.").foregroundStyle(.secondary)
                Label(status, systemImage: available ? "iphone" : "info.circle").font(.subheadline).accessibilityIdentifier("intelligence-status")
                VStack(alignment: .leading, spacing: 12) {
                    Text("숫자 기록만 사용해요").font(.headline)
                    Text("운동·마음·수면·수분·루틴의 집계만 기기 내 모델에 전달합니다. 메모와 루틴 이름은 보내지 않아요. 생성 내용은 기록이나 목표를 자동으로 바꾸지 않습니다.").font(.subheadline).foregroundStyle(.secondary)
                }.careCard()
                Picker("돌아볼 기간", selection: $days) { Text("7일").tag(7); Text("30일").tag(30) }.pickerStyle(.segmented)
                Picker("회고 방향", selection: $focus) { ForEach(IntelligencePolicy.focuses, id: \.self) { Text($0) } }
                DisclosureGroup("사용할 통계 미리보기 · AI 생성 아님") { Text(preview).font(.subheadline.monospacedDigit()).textSelection(.enabled).padding(.top, 8) }.careCard()
                if !available { Text("AI를 사용할 수 없어도 위 통계와 기존 리포트는 볼 수 있어요.").font(.caption).foregroundStyle(.secondary) }
                if !hasRecords { Text("선택한 기간의 기록을 먼저 남겨주세요.").foregroundStyle(.secondary) }
                if generating { HStack { ProgressView(); Text("기록을 돌아보고 있어요…") }.accessibilityIdentifier("intelligence-progress") }
                CareButton(title: generating ? "생성 중" : result.isEmpty ? "나의 기록 회고 만들기" : "다시 만들기", color: Palette.purple, filled: true, id: "intelligence-generate") {
                    refreshAvailability()
                    guard available, hasRecords, !generating else { return }
                    context = preview + "\n회고 방향: " + focus; result = ""; failure = ""; generating = true; request += 1
                }.disabled(!available || !hasRecords || generating)
                if generating { Button("생성 취소") { generating = false; request += 1 }.accessibilityIdentifier("intelligence-cancel") }
                if !available { Button("지원 상태 다시 확인") { refreshAvailability() }.accessibilityIdentifier("intelligence-refresh") }
                if !result.isEmpty { Button("생성 결과 지우기") { invalidate() } }
                if !failure.isEmpty { Text(failure).foregroundStyle(.secondary).accessibilityIdentifier("intelligence-error") }
                if !result.isEmpty {
                    VStack(alignment: .leading, spacing: 14) { Label("Apple Intelligence 생성", systemImage: "sparkles").font(.headline); Text(result).textSelection(.enabled) }.careCard().accessibilityIdentifier("intelligence-result")
                }
                Text("AI가 만든 내용은 틀릴 수 있어요. 진단·치료·체중 감량 처방이 아닌 기록 회고이며, 실제 기록과 함께 확인해주세요.").font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }.background(Color(.systemGroupedBackground)).navigationTitle("나의 기록 인사이트").navigationBarTitleDisplayMode(.inline)
            .onAppear { refreshAvailability() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { refreshAvailability() } else { invalidate() } }
            .onChange(of: days) { _, _ in invalidate() }
            .onChange(of: focus) { _, _ in invalidate() }
            .onChange(of: journal.entries) { _, _ in invalidate() }
            .onChange(of: journal.checks) { _, _ in invalidate() }
            .onChange(of: journal.routines) { _, _ in invalidate() }
            .onDisappear { invalidate() }
            .task(id: request) {
                guard request > 0, generating else { return }
                let generation = request
                defer { if generation == request { generating = false } }
                do {
                    let session = LanguageModelSession(instructions: """
                    한국어 개인 기록 회고 도우미입니다. 제공된 통계와 회고 방향에 맞게 짧은 회고 2문장, 선택 가능한 작은 실천 1개, 부담 없는 질문 1개를 소제목과 함께 작성하세요. 수치는 위 통계에서 직접 확인하므로 답변에 수치를 반복하지 마세요. 600자 안에서 끝내세요.
                    기록 없는 날을 활동하지 않은 날로 해석하지 말고, 없는 수치와 추세를 만들어내지 마세요.
                    의료 진단, 치료, 질병 위험 판단, 식단이나 감량 처방, 목표 수치 추천은 하지 마세요.
                    사용자를 평가하거나 죄책감을 주지 마세요. 작은 기록, 잠깐 멈춤, 편안한 산책 같은 선택 가능한 제안만 하세요.
                    """)
                    var options = GenerationOptions(); options.maximumResponseTokens = 700
                    let response = try await session.respond(to: context, options: options)
                    try Task.checkCancellation()
                    guard generation == request else { return }
                    result = try IntelligencePolicy.validated(response.content)
                } catch is CancellationError {
                    // Leaving the screen cancels the request without changing saved data.
                } catch {
                    guard !Task.isCancelled, generation == request else { return }
                    failure = "요약을 만들지 못했어요. 모델 준비 상태를 확인하거나 나중에 다시 시도해주세요."
                    refreshAvailability()
                }
            }
    }
}
