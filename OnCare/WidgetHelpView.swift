import SwiftUI
import WidgetKit

enum CareWidgetInstallation {
    static func extensions(in directory: URL?) -> [URL] {
        guard let directory, let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { url in
            guard url.pathExtension == "appex", let bundle = Bundle(url: url), let info = bundle.infoDictionary,
                  let declaration = info["NSExtension"] as? [String: Any] else { return false }
            return declaration["NSExtensionPointIdentifier"] as? String == "com.apple.widgetkit-extension"
        }
    }
}
struct WidgetHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var configured = 0
    @State private var queryFailed = false
    private var included: Bool { !CareWidgetInstallation.extensions(in: Bundle.main.builtInPlugInsURL).isEmpty }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("위젯이 보이지 않나요?").font(.largeTitle.bold())
                    VStack(alignment: .leading, spacing: 12) {
                        Label(included ? "위젯 확장이 설치되어 있어요" : "위젯 확장이 설치에서 빠졌어요", systemImage: included ? "checkmark.circle" : "exclamationmark.triangle").font(.headline).accessibilityIdentifier("widget-install-status")
                        Text(included ? "확장 파일의 포함 여부를 확인했습니다. 서명 유효성이나 위젯 목록 등록까지 보장하는 검사는 아닙니다." : "AltStore/SideStore에서 IPA를 다시 가져올 때 앱 확장을 유지하는 선택을 해주세요. 앱과 확장 모두 서명되어야 위젯을 사용할 수 있습니다.").font(.subheadline).foregroundStyle(.secondary)
                        Text(queryFailed ? "추가된 위젯을 조회하지 못했어요." : "현재 추가된 온케어 위젯: \(configured)개").font(.caption).foregroundStyle(.secondary)
                        Text("0개는 아직 위젯을 추가하지 않았다는 뜻일 수도 있어요. 위젯 목록에서 제공되는지 판별하는 수치는 아닙니다.").font(.caption).foregroundStyle(.secondary)
                    }.careCard()
                    VStack(alignment: .leading, spacing: 14) {
                        Text("위젯 목록에 온케어가 없을 때").font(.title3.bold())
                        Text("1. 기존 건강 기록을 먼저 백업하세요.\n\n2. 설치 도구에서 앱 확장을 유지한 채 이 IPA로 업데이트하세요. 앱을 먼저 삭제하지 마세요.\n\n3. 온케어를 한 번 열고 홈 화면으로 돌아가세요.\n\n4. 홈 화면 길게 누르기 → 편집 → 위젯 추가에서 ‘온케어’를 검색하세요.\n\n5. 확장이 포함되어도 계속 보이지 않으면 iPhone을 재시동하고 확장 서명 상태를 설치 도구에서 확인하세요.").font(.body).lineSpacing(4)
                    }.careCard()
                    CareButton(title: "추가된 위젯 새로고침", id: "widget-reload") { WidgetCenter.shared.reloadAllTimelines(); query() }
                    Text("새로고침은 이미 추가한 위젯의 내용을 갱신합니다. 빠진 확장을 설치하거나 위젯 목록을 강제로 등록하는 기능은 아닙니다.").font(.caption).foregroundStyle(.secondary)
                }.padding(22)
            }.background(Color(.systemGroupedBackground)).navigationTitle("위젯 설치 확인").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("닫기") { dismiss() } } }.onAppear { query() }
        }
    }
    private func query() {
        WidgetCenter.shared.getCurrentConfigurations { result in
            DispatchQueue.main.async { switch result { case .success(let widgets): configured = widgets.count; queryFailed = false; case .failure: queryFailed = true } }
        }
    }
}
