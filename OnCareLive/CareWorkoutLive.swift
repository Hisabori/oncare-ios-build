import SwiftUI
import WidgetKit
import ActivityKit

struct CareWorkoutLive: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CareWorkoutAttributes.self) { context in
            HStack(spacing: 16) {
                Image(systemName: context.state.running ? "figure.walk" : "pause.circle.fill").font(.title).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 5) { Text("온케어 · 운동 타이머").font(.headline); Text(context.state.running ? "진행 중 · 목표 \(context.attributes.goalMinutes)분" : "일시정지").font(.caption); timer(context.state).font(.title2.bold()).monospacedDigit() }
                Spacer(); Image(systemName: "chevron.right")
            }.padding(18).widgetURL(CareDestination.workout.url).activityBackgroundTint(Color(.secondarySystemBackground))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "figure.walk").foregroundStyle(.teal) }
                DynamicIslandExpandedRegion(.trailing) { Text(context.state.running ? "운동 중" : "일시정지").font(.caption) }
                DynamicIslandExpandedRegion(.bottom) { VStack(spacing: 6) { timer(context.state).font(.title2.bold()).monospacedDigit(); Text("목표 \(context.attributes.goalMinutes)분 · 눌러서 앱에서 이어가기").font(.caption) } }
            } compactLeading: { Image(systemName: context.state.running ? "figure.walk" : "pause.fill").foregroundStyle(.teal) }
            compactTrailing: { timer(context.state).monospacedDigit().frame(maxWidth: 58) }
            minimal: { Image(systemName: context.state.running ? "figure.walk" : "pause.fill").foregroundStyle(.teal) }
            .widgetURL(CareDestination.workout.url).keylineTint(.teal)
        }
    }
    @ViewBuilder private func timer(_ state: CareWorkoutAttributes.ContentState) -> some View {
        if state.running { Text(timerInterval: state.timerStart...state.timerEnd, countsDown: false) }
        else { Text(String(format: "%02d:%02d", state.elapsedSeconds / 60, state.elapsedSeconds % 60)) }
    }
}
