import SwiftUI
import WidgetKit

@main struct OnCareWidgets: WidgetBundle {
    var body: some Widget {
        CareHomeShortcutsWidget()
        CareSleepShortcutWidget()
        CareWorkoutShortcutWidget()
        CareMoodShortcutWidget()
        CareConnectionShortcutWidget()
        OnCareLive()
    }
}

struct CareShortcutEntry: TimelineEntry { let date: Date }
struct CareShortcutTimeline: TimelineProvider {
    func placeholder(in context: Context) -> CareShortcutEntry { CareShortcutEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (CareShortcutEntry) -> Void) { completion(CareShortcutEntry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CareShortcutEntry>) -> Void) {
        completion(Timeline(entries: [CareShortcutEntry(date: Date())], policy: .never))
    }
}

extension View {
    @ViewBuilder func careWidgetSurface() -> some View {
        if #available(iOS 17.0, *) { containerBackground(for: .widget) { Color(.secondarySystemBackground) } }
        else { background(Color(.secondarySystemBackground)) }
    }
}

/// Home screen shortcuts contain no health record, shared-container file or account credential.
struct CareHomeShortcutsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OnCare.quick-actions", provider: CareShortcutTimeline()) { _ in CareHomeShortcutView() }
            .configurationDisplayName("온케어 바로가기")
            .description("수면·운동·마음·건강 연결 화면을 빠르게 열어요.")
            .supportedFamilies([.systemMedium])
    }
}
struct CareHomeShortcutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("ONCARE").font(.caption.bold()).foregroundStyle(.blue); Spacer(); Text("나를 돌보는 바로가기").font(.caption2).foregroundStyle(.secondary) }
            HStack(spacing: 10) { shortcut(.sleep); shortcut(.workout) }
            HStack(spacing: 10) { shortcut(.mood); shortcut(.connect) }
        }.widgetURL(CareDestination.sleep.url).careWidgetSurface()
    }
    func shortcut(_ destination: CareDestination) -> some View {
        Link(destination: destination.url) {
            HStack(spacing: 8) {
                Image(systemName: destination.symbol).font(.body).frame(width: 22)
                Text(destination.title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }.foregroundStyle(.blue).padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity).background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        }.accessibilityLabel(destination.title + " 열기")
    }
}

struct CareRouteShortcutView: View {
    @Environment(\.widgetFamily) private var family
    let destination: CareDestination
    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack { AccessoryWidgetBackground(); Image(systemName: destination.symbol).font(.title2) }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 3) { Label(destination.title, systemImage: destination.symbol).font(.headline); Text("온케어에서 열기").font(.caption) }
            case .accessoryInline:
                Label("온케어 · " + destination.title, systemImage: destination.symbol)
            default:
                VStack(alignment: .leading, spacing: 10) {
                    Text("ONCARE").font(.caption.bold()).foregroundStyle(.blue)
                    Spacer(minLength: 0)
                    Image(systemName: destination.symbol).font(.system(size: 32, weight: .medium)).foregroundStyle(.blue).widgetAccentable()
                    Text(destination.title).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                    Text("앱에서 이어가기").font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }.widgetURL(destination.url).accessibilityElement(children: .ignore).accessibilityLabel(destination.title + " 열기").careWidgetSurface()
    }
}
@MainActor func careRouteWidget(_ destination: CareDestination) -> some WidgetConfiguration {
    StaticConfiguration(kind: "OnCare.shortcut." + destination.rawValue, provider: CareShortcutTimeline()) { _ in CareRouteShortcutView(destination: destination) }
        .configurationDisplayName(Text(destination.title + " 바로가기"))
        .description(Text("눌러서 온케어의 " + destination.title + " 화면을 열어요. 건강 수치는 표시하지 않아요."))
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
}
struct CareSleepShortcutWidget: Widget { var body: some WidgetConfiguration { careRouteWidget(.sleep) } }
struct CareWorkoutShortcutWidget: Widget { var body: some WidgetConfiguration { careRouteWidget(.workout) } }
struct CareMoodShortcutWidget: Widget { var body: some WidgetConfiguration { careRouteWidget(.mood) } }
struct CareConnectionShortcutWidget: Widget { var body: some WidgetConfiguration { careRouteWidget(.connect) } }
