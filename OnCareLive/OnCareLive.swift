import SwiftUI
import WidgetKit
import ActivityKit

struct OnCareLive: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CareSyncAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: context.state.syncing ? "arrow.triangle.2.circlepath" : "checkmark.circle").font(.title2).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) { Text(context.attributes.title).font(.headline); Text(context.state.message).font(.subheadline); if let count = context.state.count { Text("\(count)개 기록 확인").font(.caption).foregroundStyle(.secondary) } }
                Spacer()
                if context.state.syncing { ProgressView() }
            }.padding(18).widgetURL(CareDestination.connect.url).activityBackgroundTint(Color(.secondarySystemBackground)).activitySystemActionForegroundColor(.blue)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.blue) }
                DynamicIslandExpandedRegion(.trailing) { if context.state.syncing { ProgressView() } else { Image(systemName: "checkmark.circle") } }
                DynamicIslandExpandedRegion(.bottom) { VStack(spacing: 5) { Text("온케어 · Android 건강 연결").font(.headline); Text(context.state.message).font(.caption); Text("앱을 열어 두면 자동 동기화").font(.caption2).foregroundStyle(.secondary) } }
            } compactLeading: { Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.blue) }
              compactTrailing: { if context.state.syncing { ProgressView() } else { Image(systemName: "checkmark") } }
              minimal: { Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.blue) }
              .widgetURL(CareDestination.connect.url)
              .keylineTint(.blue)
        }
    }
}
