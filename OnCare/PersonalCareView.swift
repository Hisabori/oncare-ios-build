import SwiftUI

struct PersonalCareCard: View {
    @AppStorage("care-focus") private var focus = "마음"
    @AppStorage("care-display-name") private var name = ""
    @State private var editing = false
    @State private var support = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text(name.isEmpty ? "나에게 맞춘 오늘" : name + "님의 오늘").font(.title3.bold()); Spacer(); Button("맞춤 설정") { editing = true }.accessibilityIdentifier("personalize-open") }
            Label("지금 챙기고 싶은 것 · " + focus, systemImage: "heart.circle").font(.subheadline)
            Text(focus == "수면" ? "오늘의 수면 기록을 돌아보고 나에게 맞는 취침 시간을 정해보세요." : focus == "운동" ? "무리하지 않는 목표로 실천 센터의 운동 타이머를 시작해보세요." : focus == "투약" ? "투약 관리에서 오늘 예정된 약과 직접 확인한 기록을 살펴보세요." : "잠깐 멈춰 지금의 마음을 기록해보세요. 필요할 때 도움을 요청할 수 있어요.").font(.subheadline).foregroundStyle(.secondary)
            Button { support = true } label: { Label("지금 도움이 필요해요", systemImage: "lifepreserver").frame(minHeight: 44) }.accessibilityIdentifier("crisis-support-open")
        }.careCard().sheet(isPresented: $editing) { PersonalCareSettingsView() }.sheet(isPresented: $support) { CrisisSupportView() }
    }
}
struct PersonalCareSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("care-focus") private var focus = "마음"
    @AppStorage("care-display-name") private var name = ""
    @AppStorage("care-workout-minutes") private var minutes = 20
    var body: some View {
        NavigationStack { Form {
            Section("내 생활에 맞추기") {
                TextField("부르고 싶은 이름 (선택)", text: $name).accessibilityIdentifier("personalize-name")
                    .onChange(of: name) { name = String(name.filter { $0.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) } }.prefix(30)) }
                Picker("지금 관심 있는 분야", selection: $focus) { ForEach(["마음", "수면", "운동", "투약"], id: \.self) { Text($0) } }
                Picker("기본 운동 목표", selection: $minutes) { ForEach([10,20,30,60], id: \.self) { Text("\($0)분").tag($0) } }
            }
            Section { Text("직접 고른 관심 분야로 홈 안내를 바꿔요. 기기 안에만 보관하며 건강 상태나 위기 수준을 추정하지 않습니다. 이름은 잠금화면에 표시하지 않아요.").font(.caption).foregroundStyle(.secondary); Button("개인화 초기화") { name = ""; focus = "마음"; minutes = 20 } }
        }.navigationTitle("나에게 맞추기").toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } } }
    }
}
struct CrisisSupportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var failed = false
    var body: some View {
        NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 20) {
            Text("혼자 감당하지 않아도 괜찮아요").font(.title2.bold())
            Text("대한민국에서 이용할 수 있는 도움 안내입니다. 생명이나 신체에 즉각적인 위험이 있다면 긴급 신고를 이용하세요. 안전한 곳으로 이동하고 가까운 사람에게 함께 있어 달라고 요청할 수 있어요.").lineSpacing(5)
            resource("자살예방상담전화", number: "109", detail: "전화 상담과 전문 지원 연결 안내", url: "tel:+82109?oai_link_source=model_response_hotline")
            resource("긴급 구조·구급", number: "119", detail: "응급 구조와 구급이 필요한 상황", url: "tel:119")
            resource("경찰 긴급 신고", number: "112", detail: "범죄·폭력 등 즉각적인 위험", url: "tel:112")
            Text("전화를 자동으로 걸거나 현재 위치·건강 기록을 전송하지 않아요. 번호를 눌러 전화 화면에서 직접 진행하세요. 해외에서는 현지 긴급 연락처를 확인하세요.").font(.caption).foregroundStyle(.secondary)
            Link("상담 안내 · 보건복지상담센터", destination: URL(string: "https://www.129.go.kr/109?oai_link_source=model_response_hotline")!)
            Link("긴급 신고 안내 · 국민재난안전포털", destination: URL(string: "https://safekorea.go.kr/idsiSFK/neo/main_m/nat/downpour.html?menuTab=1")!)
            Text("확인일 2026.10.15 · 안내는 오프라인에서도 볼 수 있어요. 전화와 웹 연결은 기기·통신 상태에 따라 달라요.").font(.caption).foregroundStyle(.secondary)
        }.padding(22) }.background(Color(.systemGroupedBackground)).navigationTitle("도움과 위기지원").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }.alert("전화 화면을 열지 못했어요", isPresented: $failed) { Button("확인", role: .cancel) {} } message: { Text("안내된 번호를 전화 앱에 직접 입력해주세요.") } }
    }
    private func resource(_ title: String, number: String, detail: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 10) { Text(title).font(.headline); Text(detail).foregroundStyle(.secondary); Button { openURL(URL(string:url)!) { accepted in if !accepted { failed = true } } } label: { Label(number + " · 전화 화면 열기", systemImage: "phone.fill").font(.title3.bold()).frame(minHeight: 48) } }.careCard()
    }
}
