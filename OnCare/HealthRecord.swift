import Foundation
import SwiftUI
indirect enum HealthValue: Codable, Equatable {
    case number(Double), text(String), bool(Bool), object([String: HealthValue]), array([HealthValue]), null
    init(from decoder: Decoder) throws { let c = try decoder.singleValueContainer(); if c.decodeNil() { self = .null } else if let v = try? c.decode(Bool.self) { self = .bool(v) } else if let v = try? c.decode(Double.self) { self = .number(v) } else if let v = try? c.decode(String.self) { self = .text(v) } else if let v = try? c.decode([String: HealthValue].self) { self = .object(v) } else { self = .array(try c.decode([HealthValue].self)) } }
    func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); switch self { case .null: try c.encodeNil(); case .number(let v): try c.encode(v); case .text(let v): try c.encode(v); case .bool(let v): try c.encode(v); case .object(let v): try c.encode(v); case .array(let v): try c.encode(v) } }
    func validate(depth: Int = 0, nodes: inout Int) throws { nodes += 1; guard depth <= 12, nodes <= 100000 else { throw CareError.invalid }; switch self { case .number(let v): guard v.isFinite else { throw CareError.invalid }; case .text(let v): guard v.count <= 100000 else { throw CareError.invalid }; case .object(let v): for (key, child) in v { guard key.count <= 100 else { throw CareError.invalid }; try child.validate(depth: depth + 1, nodes: &nodes) }; case .array(let v): for child in v { try child.validate(depth: depth + 1, nodes: &nodes) }; default: break } }
    var display: String { switch self { case .number(let v): return rawNumber(v); case .text(let v): return v; case .bool(let v): return v ? "예" : "아니요"; case .null: return "제공 없음"; case .array(let v): return "측정값 \(v.count)개"; case .object: return "상세 값" } }
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
enum HealthBrowserQuery {
    static func source(_ record: HealthRecord) -> String {
        var values = [record.source ?? ""]
        if case .object(let metadata)? = record.fields["metadata"] {
            if case .object(let origin)? = metadata["dataOrigin"], case .text(let app)? = origin["packageName"] { values.append(app == "com.sec.android.app.shealth" ? "삼성 헬스 · " + app : app) }
            if case .object(let device)? = metadata["device"] { for key in ["manufacturer", "model"] { if case .text(let value)? = device[key] { values.append(value) } } }
        }
        return values.filter { !$0.isEmpty }.joined(separator: " · ")
    }
    static func filtered(_ records: [HealthRecord], category: String, days: Int, query: String, favorites: Set<String>, onlyFavorites: Bool, now: Date = Date()) -> [HealthRecord] {
        let start = days > 0 ? dayOffset(1 - days, from: now) : Date(timeIntervalSince1970: 0)
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return records.filter { record in record.date >= start && record.date <= now && (category == "전체" || record.category == category) && (!onlyFavorites || favorites.contains(record.recordType)) && (needle.isEmpty || (record.title + " " + record.category + " " + source(record)).localizedCaseInsensitiveContains(needle)) }.sorted { $0.date == $1.date ? $0.id > $1.id : $0.date > $1.date }
    }
}
struct HealthRecordsView: View {
    @EnvironmentObject var journal: Journal
    @State private var category = "전체"
    @State private var search = ""
    @State private var days = 0
    @State private var onlyFavorites = false
    @AppStorage("health-favorites-v1") private var encodedFavorites = ""
    private var favorites: Set<String> { Set(encodedFavorites.split(separator: ",").map(String.init)).intersection(HealthRecord.types) }
    private var records: [HealthRecord] { HealthBrowserQuery.filtered(journal.state.healthRecords ?? [], category: category, days: days, query: search, favorites: favorites, onlyFavorites: onlyFavorites) }
    private var types: [String] { let grouped = Dictionary(grouping: records, by: \.recordType); return grouped.keys.sorted { a, b in if favorites.contains(a) != favorites.contains(b) { return favorites.contains(a) }; return (grouped[a]?.first?.title ?? a) < (grouped[b]?.first?.title ?? b) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("연결된 건강 정보").font(.largeTitle.bold())
                Text("원본의 측정값과 출처를 함께 확인해요. 여러 앱의 같은 기록을 합계로 더하지 않아요.").font(.subheadline).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(["전체", "생체", "활동", "신체", "영양", "수면", "주기", "마음", "의료"], id: \.self) { item in Button(item) { category = item }.buttonStyle(.bordered).tint(category == item ? Palette.blue : .gray) } } }
                Picker("조회 기간", selection: $days) { Text("전체").tag(0); Text("7일").tag(7); Text("30일").tag(30) }.pickerStyle(.segmented).accessibilityIdentifier("health-period-filter")
                Toggle("즐겨찾기만 보기", isOn: $onlyFavorites).accessibilityIdentifier("health-favorites-only")
                if records.isEmpty { Label("표시할 기록이 없어요. Android에서 권한과 원본 데이터 공유를 확인해주세요.", systemImage: "heart.text.square").careCard(); Text("검색·기간·즐겨찾기 조건도 확인해보세요.").font(.caption).foregroundStyle(.secondary) }
                ForEach(types, id: \.self) { key in
                    let selected = records.filter { $0.recordType == key }
                    if let latest = selected.first {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                NavigationLink { HealthRecordList(records: selected) } label: { HStack { VStack(alignment: .leading, spacing: 8) { Text(latest.title).font(.headline); Text(latest.summaryValue).font(.title2.bold()).foregroundStyle(Palette.blue); Text("\(selected.count)개 기록 · " + latest.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary) }.contentShape(Rectangle()) }.buttonStyle(.plain)
                                Button { var next = favorites; if next.contains(key) { next.remove(key) } else { next.insert(key) }; encodedFavorites = next.sorted().joined(separator: ",") } label: { Image(systemName: favorites.contains(key) ? "star.fill" : "star").font(.title3).frame(width: 44, height: 44) }.accessibilityLabel(favorites.contains(key) ? "즐겨찾기 해제" : "즐겨찾기 추가").accessibilityIdentifier("health-favorite-" + key)
                            }
                            Text(HealthBrowserQuery.source(latest).isEmpty ? "원본 출처 정보 없음" : HealthBrowserQuery.source(latest)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }.careCard()
                    }
                }
                Text("의료 문서는 가져온 시각으로 기간을 조회해요. 실제 진료 날짜는 원문에서 확인합니다.").font(.caption).foregroundStyle(.secondary)
                if let availability = journal.state.healthAvailability { DisclosureGroup("항목별 연결 상태") { ForEach(availability) { item in HStack { Text(item.title); Spacer(); Text(item.statusTitle).font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 5) } }.careCard() }
            }.padding(22)
        }.background(Color(.systemGroupedBackground)).navigationTitle("건강 데이터").searchable(text: $search, prompt: "항목·원본 앱·기기 검색")
    }
}
struct HealthRecordList: View {
    let records: [HealthRecord]
    var body: some View { List(records) { record in NavigationLink { List { Section("원본 기록") { Text((record.category == "의료" ? "가져온 시각: " : "측정 시각: ") + record.date.formatted(date: .complete, time: .shortened)); if record.category == "의료" { Text("실제 진료·검사 날짜는 원문 안에서 확인해요. 의료 문서로 복용 일정이나 처방을 자동 변경하지 않아요.").font(.caption) }; Text(record.title) }; HealthFieldsView(fields: record.fields) }.navigationTitle(record.title) } label: { VStack(alignment: .leading) { Text(record.date.formatted(date: .abbreviated, time: .shortened)); Text(record.summaryValue).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.blue) } } }.navigationTitle(records.first?.title ?? "측정 기록") }
}
struct HealthFieldsView: View {
    let fields: [String: HealthValue]
    static let labels = ["capturedAt": "가져온 시각", "fhir": "의료 원문", "fhirVersion": "문서 규격", "dataSourceId": "의료 자료 출처", "protein": "단백질", "totalCarbohydrate": "탄수화물", "totalFat": "지방", "saturatedFat": "포화 지방", "unsaturatedFat": "불포화 지방", "dietaryFiber": "식이 섬유", "sugar": "당류", "caffeine": "카페인", "sodium": "나트륨", "potassium": "칼륨", "calcium": "칼슘", "iron": "철", "magnesium": "마그네슘", "cholesterol": "콜레스테롤", "energy": "열량", "energyFromFat": "지방 열량", "mealName": "식사 이름", "mealType": "식사 유형 · 원본 코드", "baseline": "기준 피부 온도", "deltas": "피부 온도 변화", "route": "동의한 운동 경로", "segments": "운동 구간", "laps": "운동 랩", "duration": "기간 · ms", "startZoneOffset": "시작 시차 · 초", "endZoneOffset": "종료 시차 · 초", "zoneOffset": "시차 · 초", "systolic": "수축기 혈압", "diastolic": "이완기 혈압", "inMillimetersOfMercury": "mmHg", "inGrams": "g", "inKilograms": "kg", "inMeters": "m", "inMetersPerSecond": "m/s", "inCelsius": "℃", "inWatts": "W", "inCalories": "cal", "inKilocalories": "kcal", "inLiters": "L", "beatsPerMinute": "심박 · bpm", "samples": "시간별 측정값", "metadata": "기록 출처", "device": "측정 기기", "manufacturer": "제조사", "model": "모델", "dataOrigin": "원본 앱", "packageName": "앱 이름", "time": "측정 시각", "startTime": "시작 시각", "endTime": "종료 시각", "stages": "수면 단계", "percentage": "%", "count": "개수", "rate": "호흡 · 회/분", "heartRateVariabilityMillis": "심박 변이도 · ms"]
    var body: some View { ForEach(fields.keys.sorted(), id: \.self) { key in if let value = fields[key] { row(key, value) } } }
    @ViewBuilder private func row(_ key: String, _ value: HealthValue) -> some View {
        let label = Self.labels[key] ?? key
        switch value {
        case .object(let object): DisclosureGroup(label) { HealthFieldsView(fields: object) }
        case .array(let array): DisclosureGroup(label + " · \(array.count)개") { ForEach(Array(array.prefix(100).enumerated()), id: \.offset) { item in if case .object(let object) = item.element { DisclosureGroup("측정 \(item.offset + 1)") { HealthFieldsView(fields: object) } } else { Text(item.element.display) } }; if array.count > 100 { Text("화면은 첫 100개를 표시해요. 전체 값은 백업에 보존돼요.").font(.caption) } }
        case .number(let timestamp) where key == "time" || key == "startTime" || key == "endTime" || key == "lastModifiedTime" || key == "capturedAt": LabeledContent(label, value: Date(timeIntervalSince1970: timestamp / 1000).formatted(date: .abbreviated, time: .standard))
        default: LabeledContent(label, value: value.display)
        }
    }
}

extension HealthRecord {
    private func scalar(_ value: HealthValue?) -> Double? { if case .number(let n) = value { return n }; return nil }
    private func measure(_ key: String, _ unit: String? = nil) -> Double? { guard let value = fields[key] else { return nil }; if let unit, case .object(let object) = value { return scalar(object[unit]) }; return scalar(value) }
    private func metric(_ key: String, _ property: String? = nil, factor: Double = 1, unit: String) -> String? { measure(key, property).map { number($0 * factor) + " " + unit } }
    var summaryValue: String {
        if category == "의료" { return "원본 의료 문서" }
        if recordType == "BloodPressureRecord", let systolic = measure("systolic", "inMillimetersOfMercury"), let diastolic = measure("diastolic", "inMillimetersOfMercury") { return number(systolic) + " / " + number(diastolic) + " mmHg" }
        let value: String?
        switch recordType {
        case "WeightRecord": value = metric("weight", "inGrams", factor: 0.001, unit: "kg")
        case "BodyWaterMassRecord", "BoneMassRecord", "LeanBodyMassRecord": value = metric("mass", "inGrams", factor: 0.001, unit: "kg")
        case "HeightRecord": value = metric("height", "inMeters", factor: 100, unit: "cm")
        case "BloodGlucoseRecord": value = metric("level", "inMillimolesPerLiter", unit: "mmol/L")
        case "BodyTemperatureRecord", "BasalBodyTemperatureRecord": value = metric("temperature", "inCelsius", unit: "℃")
        case "OxygenSaturationRecord", "BodyFatRecord": value = metric("percentage", "value", unit: "%")
        case "RestingHeartRateRecord": value = metric("beatsPerMinute", unit: "bpm")
        case "HeartRateVariabilityRmssdRecord": value = metric("heartRateVariabilityMillis", unit: "ms")
        case "RespiratoryRateRecord": value = metric("rate", unit: "회/분")
        case "DistanceRecord": value = metric("distance", "inMeters", factor: 0.001, unit: "km")
        case "ElevationGainedRecord": value = metric("elevation", "inMeters", unit: "m")
        case "FloorsClimbedRecord": value = metric("floors", unit: "층")
        case "StepsRecord": value = metric("count", unit: "걸음")
        case "WheelchairPushesRecord": value = metric("count", unit: "회")
        case "ActiveCaloriesBurnedRecord", "TotalCaloriesBurnedRecord", "NutritionRecord": value = metric("energy", "inCalories", factor: 0.001, unit: "kcal")
        case "HydrationRecord": value = metric("volume", "inLiters", factor: 1000, unit: "ml")
        case "BasalMetabolicRateRecord": value = metric("basalMetabolicRate", "inWatts", unit: "W")
        case "Vo2MaxRecord": value = metric("vo2MillilitersPerMinuteKilogram", unit: "ml/kg/min")
        case "HeartRateRecord":
            if case .array(let samples) = fields["samples"] { let latest = samples.compactMap { sample -> [String: HealthValue]? in if case .object(let object) = sample { return object }; return nil }.max { (scalar($0["time"]) ?? 0) < (scalar($1["time"]) ?? 0) }; value = latest.flatMap { scalar($0["beatsPerMinute"]) }.map { "최근 샘플 " + number($0) + " bpm" } } else { value = nil }
        default: value = nil
        }
        return value ?? "원본 상세 보기"
    }
}
