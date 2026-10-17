import SwiftUI

enum CareUpgrade {
    static func moodContext(_ entries: [Entry], now: Date = Date(), calendar: Calendar = .current) -> (days: Int, latest: Double?) {
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))!
        let recent = entries.filter { $0.kind == "마음" && $0.date >= start && $0.date <= now && $0.value.isFinite && (1...5).contains($0.value) }
        let days = Set(recent.map { calendar.startOfDay(for: $0.date) }).count
        return (days, recent.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }.first?.value)
    }
    static func medicationPhase(hour: Int, minute: Int, checked: Bool, now: Date, calendar: Calendar = .current) -> String {
        if checked { return "확인 완료" }
        let current = calendar.component(.hour, from: now)*60 + calendar.component(.minute, from: now)
        return hour*60+minute <= current ? "시간 지남 · 확인 전" : "예정 · 확인 전"
    }
    static func coverage(analyzed: Int, measuredSeconds: Double) -> Double? {
        guard analyzed >= 0, measuredSeconds.isFinite, measuredSeconds >= 30 else { return nil }
        return min(1, max(0, Double(analyzed)*30/measuredSeconds))
    }
}

struct MindRecoveryCard: View {
    let entries: [Entry]
    let breathe: () -> Void
    let write: () -> Void
    @AppStorage("app-recovery-style") private var preference = 0
    @State private var noticing = false
    var body: some View {
        let context = CareUpgrade.moodContext(entries)
        return VStack(alignment: .leading, spacing: 12) {
            Label("나에게 맞는 작은 실천", systemImage: "leaf.fill").font(.headline).foregroundStyle(Palette.purple)
            Text(context.days == 0 ? "아직 이번 주 마음 기록이 없어요. 점수와 관계없이 편한 방법을 골라요." : "최근 7일 중 \(context.days)일 기록했어요. 기록하지 않은 날은 평가하지 않아요.").font(.subheadline)
            if let value = context.latest, value <= 2 { Text("최근 기록에서 힘든 마음을 남겼네요. 지금 할 수 있는 작은 한 가지만 골라도 괜찮아요.").font(.caption).foregroundStyle(.secondary) }
            Picker("선호하는 실천", selection: $preference) { Text("쉼").tag(0); Text("쓰기").tag(1); Text("감각").tag(2) }.pickerStyle(.segmented).accessibilityIdentifier("recovery-preference")
            Text(preference == 1 ? "마음에 남은 일과 지금 필요한 한 가지를 적어봐요." : preference == 2 ? "주변에서 편안한 색, 닿는 감촉, 들리는 소리를 하나씩 살펴봐요." : "익숙한 1분 호흡 화면으로 이동해요. 불편하면 언제든 멈추세요.").font(.subheadline).foregroundStyle(.secondary)
            CareButton(title: "선택한 실천 시작", color: Palette.purple, id: "recovery-start") { if preference == 1 { write() } else if preference == 2 { noticing = true } else { breathe() } }
            Text("선택은 이 기기에 저장돼요. 진단이나 치료 추천이 아닙니다.").font(.caption).foregroundStyle(.secondary)
        }.careCard().onAppear { if !(0...2).contains(preference) { preference = 0 } }
        .alert("잠깐, 주변에 머물러요", isPresented: $noticing) { Button("마음 기록하기", action: write); Button("닫기", role: .cancel) {} } message: { Text("편안한 색 하나 → 손끝에 닿는 감촉 하나 → 지금 들리는 소리 하나. 정답 없이 천천히 살펴봐요. 불편하면 멈춰도 괜찮아요.") }
    }
}

struct SleepSoundReviewCard: View {
    let sessions: [SleepSoundSession]
    var body: some View {
        let completed = sessions.filter { $0.ended != nil && $0.measuredMinutes > 0 }
        return VStack(alignment: .leading, spacing: 12) {
            Label("측정 돌아보기", systemImage: "waveform.path").font(.headline).foregroundStyle(Palette.teal)
            if let latest = completed.first {
                Text("최근 측정 \(Int(latest.measuredMinutes))분").font(.title3.bold())
                if completed.count > 1 { Text("그 이전 측정 \(Int(completed[1].measuredMinutes))분 · 측정한 길이를 비교해요.").font(.subheadline) }
                if let research = latest.research, let ratio = CareUpgrade.coverage(analyzed: research.analyzed, measuredSeconds: latest.measuredMinutes*60) {
                    Text("모델 처리 비율 \(Int(ratio*100))%").font(.headline)
                    ProgressView(value: ratio).tint(Palette.teal)
                    Text("분석 \(research.analyzed)구간 · 보류 \(research.skipped)회. 매우 작은 소리·클리핑·실행 지연·중단은 분석에서 제외될 수 있어요.").font(.caption).foregroundStyle(.secondary)
                }
            } else { Text("측정을 한 번 마치면 분석 범위와 이전 측정 비교가 표시돼요.").font(.subheadline) }
            Text("처리 비율은 정확도나 수면 점수가 아니며, 측정 시간은 실제 수면 시간이 아닙니다.").font(.caption).foregroundStyle(.secondary)
        }.careCard().accessibilityIdentifier("sleep-sound-review")
    }
}
