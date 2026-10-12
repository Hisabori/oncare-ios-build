import SwiftUI
struct SleepStageChart: View {
    let entry: Entry
    private let levels: [SleepStageType] = [.awake, .rem, .light, .deep]
    private func color(_ type: SleepStageType) -> Color { switch type { case .awake: return Palette.coral; case .rem: return Palette.purple; case .light: return Palette.blue; case .deep: return .indigo; default: return .gray } }
    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) { ForEach(levels, id: \.rawValue) { type in Text(type.title).font(.caption2).foregroundStyle(.secondary).frame(height: 30) } }.frame(width: 62, alignment: .leading)
                Canvas { context, size in
                    guard let start = entry.bedTime, let end = entry.wakeTime, end > start else { return }
                    let duration = end.timeIntervalSince(start)
                    for (row, type) in levels.enumerated() {
                        let y = CGFloat(row) * 30 + 5
                        context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 20)), with: .color(Color.gray.opacity(0.08)))
                        for stage in entry.sleep?.stages ?? [] where stage.type == type {
                            let x = max(0, stage.start.timeIntervalSince(start) / duration) * size.width
                            let right = min(1, stage.end.timeIntervalSince(start) / duration) * size.width
                            context.fill(Path(roundedRect: CGRect(x: x, y: y, width: max(1, right - x), height: 20), cornerRadius: 4), with: .color(color(type)))
                        }
                    }
                }.frame(height: 120)
            }
            if let start = entry.bedTime, let end = entry.wakeTime { HStack { Text(start.formatted(date: .omitted, time: .shortened)); Spacer(); Text(end.formatted(date: .omitted, time: .shortened)) }.font(.caption2).foregroundStyle(.secondary) }
        }.accessibilityElement(children: .ignore).accessibilityLabel("깨어 있음, REM, 얕은 수면, 깊은 수면의 원본 시간표. 각 단계의 총 시간은 아래 목록에서 확인할 수 있어요.").accessibilityIdentifier("sleep-stage-chart")
    }
}
