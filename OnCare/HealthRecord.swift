import Foundation
import SwiftUI
indirect enum HealthValue: Codable, Equatable {
    case number(Double), text(String), bool(Bool), object([String: HealthValue]), array([HealthValue]), null
    init(from decoder: Decoder) throws { let c = try decoder.singleValueContainer(); if c.decodeNil() { self = .null } else if let v = try? c.decode(Bool.self) { self = .bool(v) } else if let v = try? c.decode(Double.self) { self = .number(v) } else if let v = try? c.decode(String.self) { self = .text(v) } else if let v = try? c.decode([String: HealthValue].self) { self = .object(v) } else { self = .array(try c.decode([HealthValue].self)) } }
    func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); switch self { case .null: try c.encodeNil(); case .number(let v): try c.encode(v); case .text(let v): try c.encode(v); case .bool(let v): try c.encode(v); case .object(let v): try c.encode(v); case .array(let v): try c.encode(v) } }
    func validate(depth: Int = 0, nodes: inout Int) throws { nodes += 1; guard depth <= 12, nodes <= 100000 else { throw CareError.invalid }; switch self { case .number(let v): guard v.isFinite else { throw CareError.invalid }; case .text(let v): guard v.count <= 100000 else { throw CareError.invalid }; case .object(let v): for (key, child) in v { guard key.count <= 100 else { throw CareError.invalid }; try child.validate(depth: depth + 1, nodes: &nodes) }; case .array(let v): for child in v { try child.validate(depth: depth + 1, nodes: &nodes) }; default: break } }
    var display: String { switch self { case .number(let v): return number(v); case .text(let v): return v; case .bool(let v): return v ? "예" : "아니요"; case .null: return "제공 없음"; case .array(let v): return "측정값 \(v.count)개"; case .object: return "상세 값" } }
}
struct HealthRecord: Codable, Identifiable, Equatable {
    var id: String
    var recordType: String
    var date: Date
    var title: String
    var category: String
    var fields: [String: HealthValue]
    var source: String? = nil
    static let types: Set<String> = ["ActiveCaloriesBurnedRecord","BasalBodyTemperatureRecord","BasalMetabolicRateRecord","BloodGlucoseRecord","BloodPressureRecord","BodyFatRecord","BodyTemperatureRecord","BodyWaterMassRecord","BoneMassRecord","CervicalMucusRecord","CyclingPedalingCadenceRecord","DistanceRecord","ElevationGainedRecord","ExerciseSessionRecord","FloorsClimbedRecord","HeartRateRecord","HeartRateVariabilityRmssdRecord","HeightRecord","HydrationRecord","IntermenstrualBleedingRecord","LeanBodyMassRecord","MenstruationFlowRecord","MenstruationPeriodRecord","NutritionRecord","OvulationTestRecord","OxygenSaturationRecord","PowerRecord","RespiratoryRateRecord","RestingHeartRateRecord","SexualActivityRecord","SleepSessionRecord","SpeedRecord","StepsCadenceRecord","StepsRecord","TotalCaloriesBurnedRecord","Vo2MaxRecord","WeightRecord","SkinTemperatureRecord","PlannedExerciseSessionRecord","MindfulnessSessionRecord","ActivityIntensityRecord", "WheelchairPushesRecord", "MedicalALLERGIES_INTOLERANCES", "MedicalCONDITIONS", "MedicalLABORATORY_RESULTS", "MedicalMEDICATIONS", "MedicalPERSONAL_DETAILS", "MedicalPRACTITIONER_DETAILS", "MedicalPREGNANCY", "MedicalPROCEDURES", "MedicalSOCIAL_HISTORY", "MedicalVACCINES", "MedicalVISITS", "MedicalVITAL_SIGNS"]
    func validate(now: Date) throws {
        guard Self.types.contains(recordType), id.hasPrefix("hc:"), id.count <= 100, date.timeIntervalSince1970 > 0, date <= now, !title.isEmpty, title.count <= 100, ["활동", "신체", "생체", "영양", "주기", "수면", "마음", "의료"].contains(category), (source?.count ?? 0) <= 100 else { throw CareError.invalid }
        var nodes = 0; try HealthValue.object(fields).validate(nodes: &nodes)
    }
}
struct HealthAvailability: Codable, Identifiable {
    var recordType: String
    var title: String
    var category: String
    var status: String
    var count: Int
    var id: String { recordType }
    func validate() throws { guard HealthRecord.types.contains(recordType), !title.isEmpty, title.count <= 100, ["활동", "신체", "생체", "영양", "주기", "수면", "마음", "의료"].contains(category), ["ready", "empty", "permission", "unsupported", "error"].contains(status), (0...10000).contains(count), status == "ready" || count == 0 else { throw CareError.invalid } }
    var statusTitle: String { switch status { case "ready": return "기록 \(count)개"; case "empty": return "최근 기록 없음"; case "permission": return "읽기 권한 필요"; case "unsupported": return "기기에서 지원 안 됨"; default: return "원본 읽기 확인 필요" } }
}
struct HealthRecordsView: View {
    @EnvironmentObject var journal: Journal
    @State private var category = "전체"
    @State private var search = ""
    private var records: [HealthRecord] { (journal.state.healthRecords ?? []).filter { (category == "전체" || $0.category == category) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) }.sorted { $0.date > $1.date } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("연결된 건강 정보").font(.largeTitle.bold())
                Text("원본의 측정값과 기록 출처를 함께 확인해요. 같은 항목의 여러 앱 기록은 각각 표시되며 합계로 더하지 않아요.").font(.subheadline).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(["전체", "생체", "활동", "신체", "영양", "수면", "주기", "마음", "의료"], id: \.self) { item in Button(item) { category = item }.buttonStyle(.bordered).tint(category == item ? Palette.blue : .gray) } } }
                if records.isEmpty { Label("표시할 기록이 없어요. Android에서 권한과 원본 데이터 공유를 확인해주세요.", systemImage: "heart.text.square").careCard() }
                ForEach(Array(Dictionary(grouping: records, by: \.recordType).keys).sorted(), id: \.self) { key in
                    if let latest = records.first(where: { $0.recordType == key }) {
                        NavigationLink { HealthRecordList(records: records.filter { $0.recordType == key }) } label: {
                            HStack { VStack(alignment: .leading, spacing: 8) { Text(latest.title).font(.headline); Text(latest.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right") }.careCard()
                        }.buttonStyle(.plain)
                    }
                }
                if let availability = journal.state.healthAvailability { DisclosureGroup("항목별 연결 상태") { ForEach(availability) { item in HStack { Text(item.title); Spacer(); Text(item.statusTitle).font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 5) } }.careCard() }
            }.padding(22)
        }.background(Color(.systemGroupedBackground)).navigationTitle("건강 데이터").searchable(text: $search, prompt: "심박·혈압·영양 등 검색")
    }
}
struct HealthRecordList: View {
    let records: [HealthRecord]
    var body: some View { List(records) { record in NavigationLink { List { Section("원본 기록") { Text((record.category == "의료" ? "가져온 시각: " : "측정 시각: ") + record.date.formatted(date: .complete, time: .shortened)); if record.category == "의료" { Text("실제 진료·검사 날짜는 원문 안에서 확인해요. 의료 문서로 복용 일정이나 처방을 자동 변경하지 않아요.").font(.caption) }; Text(record.title) }; HealthFieldsView(fields: record.fields) }.navigationTitle(record.title) } label: { VStack(alignment: .leading) { Text(record.date.formatted(date: .abbreviated, time: .shortened)); Text(record.title).font(.caption).foregroundStyle(.secondary) } } }.navigationTitle(records.first?.title ?? "측정 기록") }
}
struct HealthFieldsView: View {
    let fields: [String: HealthValue]
    static let labels = ["systolic": "수축기 혈압", "diastolic": "이완기 혈압", "inMillimetersOfMercury": "mmHg", "inGrams": "g", "inKilograms": "kg", "inMeters": "m", "inMetersPerSecond": "m/s", "inCelsius": "℃", "inWatts": "W", "inCalories": "cal", "inKilocalories": "kcal", "inLiters": "L", "beatsPerMinute": "심박 · bpm", "samples": "시간별 측정값", "metadata": "기록 출처", "device": "측정 기기", "manufacturer": "제조사", "model": "모델", "dataOrigin": "원본 앱", "packageName": "앱 이름", "time": "측정 시각", "startTime": "시작 시각", "endTime": "종료 시각", "stages": "수면 단계", "percentage": "%", "count": "개수", "rate": "호흡 · 회/분", "heartRateVariabilityMillis": "심박 변이도 · ms"]
    var body: some View { ForEach(fields.keys.sorted(), id: \.self) { key in if let value = fields[key] { row(key, value) } } }
    @ViewBuilder private func row(_ key: String, _ value: HealthValue) -> some View {
        let label = Self.labels[key] ?? key
        switch value {
        case .object(let object): DisclosureGroup(label) { HealthFieldsView(fields: object) }
        case .array(let array): DisclosureGroup(label + " · \(array.count)개") { ForEach(Array(array.prefix(100).enumerated()), id: \.offset) { item in if case .object(let object) = item.element { DisclosureGroup("측정 \(item.offset + 1)") { HealthFieldsView(fields: object) } } else { Text(item.element.display) } }; if array.count > 100 { Text("화면은 첫 100개를 표시해요. 전체 값은 백업에 보존돼요.").font(.caption) } }
        case .number(let timestamp) where key == "time" || key == "startTime" || key == "endTime" || key == "lastModifiedTime": LabeledContent(label, value: Date(timeIntervalSince1970: timestamp / 1000).formatted(date: .abbreviated, time: .standard))
        default: LabeledContent(label, value: value.display)
        }
    }
}
