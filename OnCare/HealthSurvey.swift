import SwiftUI
struct HealthSurveyResponse: Codable, Identifiable {
    var id = UUID().uuidString
    var date = Date()
    var answers: [Int]
    static let questions = ["잠을 자고 충분히 쉬었다고 느낀 날", "내 상황에 맞게 몸을 움직인 날", "마음이 편안하다고 느낀 날", "처방받은 복용 일정을 확인한 날"]
    static let choices = ["없음", "1~2일", "3~4일", "5~6일", "매일", "투약 해당 없음"]
    var valid: Bool { UUID(uuidString: id) != nil && date.timeIntervalSince1970 > 0 && date <= Date().addingTimeInterval(1) && answers.count == 4 && answers.enumerated().allSatisfy { (0...($0.offset == 3 ? 5 : 4)).contains($0.element) } }
}
struct HealthSurveyView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("health-survey-draft") private var draft = "-1,-1,-1,-1"
    @AppStorage("health-survey-history") private var history = "[]"
    @State private var message = ""
    private var answers: [Int] { let a = draft.split(separator: ",").compactMap { Int($0) }; return a.count == 4 ? a : [-1,-1,-1,-1] }
    private var responses: [HealthSurveyResponse]? { guard let data = history.data(using: .utf8), let list = try? JSONDecoder().decode([HealthSurveyResponse].self, from: data), list.count <= 12, list.allSatisfy({ $0.valid }), Set(list.map(\.id)).count == list.count else { return nil }; return list }
    var body: some View {
        NavigationStack { Form {
            Section { Text("최근 7일을 돌아보는 생활 점검 설문이에요. 의료 진단·검증된 선별검사가 아니며 종합 건강점수를 만들지 않습니다. 답변은 이 기기에만 저장하고 건강 동기화에 포함하지 않아요.").font(.subheadline).foregroundStyle(.secondary); Text("\(answers.filter { $0 >= 0 }.count) / 4개 응답 · 작성 중 답변도 보관해요").font(.caption) }
            ForEach(0..<4, id: \.self) { i in Section(HealthSurveyResponse.questions[i]) {
                Picker("최근 7일", selection: Binding(get: { answers[i] }, set: { value in var a = answers; a[i] = value; draft = a.map(String.init).joined(separator: ",") })) { Text("선택해주세요").tag(-1); ForEach(0..<(i == 3 ? 6 : 5), id: \.self) { Text(HealthSurveyResponse.choices[$0]).tag($0) } }.accessibilityIdentifier("survey-answer-\(i)")
            } }
            Section { Button("설문 완료 · 응답 저장") { save() }.disabled(!HealthSurveyResponse(answers: answers).valid || responses == nil).accessibilityIdentifier("survey-save"); if !message.isEmpty { Text(message).font(.caption) }; if responses == nil { Text("이전 응답을 읽지 못해 저장을 멈췄어요. 기존 데이터는 유지합니다.").foregroundStyle(Palette.coral) } }
            if let list = responses, let latest = list.first {
                Section("최근 응답 · 이전과 비교") { ForEach(0..<4, id: \.self) { i in VStack(alignment: .leading, spacing: 6) { Text(HealthSurveyResponse.questions[i]).font(.subheadline); Text(HealthSurveyResponse.choices[latest.answers[i]]).font(.headline); if list.count > 1 { Text("이전: " + HealthSurveyResponse.choices[list[1].answers[i]]).font(.caption).foregroundStyle(.secondary) } } } }
                Section("보관한 설문 · 최근 12회") { ForEach(list) { item in VStack(alignment: .leading, spacing: 6) { Text(item.date, format: .dateTime.year().month().day().hour().minute()).font(.headline); ForEach(0..<4, id: \.self) { i in Text(HealthSurveyResponse.questions[i] + " · " + HealthSurveyResponse.choices[item.answers[i]]).font(.caption).foregroundStyle(.secondary) } } } }
            }
        }.navigationTitle("건강 생활 설문").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("닫기") { dismiss() } } }
        }
    }
    private func save() { let response = HealthSurveyResponse(answers: answers); guard response.valid, var list = responses else { return }; list.insert(response, at: 0); list = Array(list.prefix(12)); guard let data = try? JSONEncoder().encode(list), let text = String(data: data, encoding: .utf8) else { message = "저장하지 못했어요."; return }; history = text; draft = "-1,-1,-1,-1"; message = "응답을 저장했어요. 아래에서 이전 응답과 비교할 수 있어요." }
}
