import Foundation
import HealthKit
import Combine

enum AppleHealthMerge {
    static func merge(_ existing: [HealthRecord], incoming: [HealthRecord], replace: Set<String>, start: Date, now: Date) throws -> [HealthRecord] {
        guard replace.isSubset(of: Set(incoming.map(\.recordType))), incoming.allSatisfy({ $0.source == "apple-health" && $0.id.hasPrefix("hc:apple:") && $0.date >= start && $0.date <= now }) else { throw CareError.invalid }
        var result = existing.filter { !($0.source == "apple-health" && replace.contains($0.recordType) && $0.date >= start && $0.date <= now) }
        let ids = Set(incoming.map(\.id)); result.removeAll { ids.contains($0.id) }; result += incoming
        guard result.count <= 10000, Set(result.map(\.id)).count == result.count else { throw CareError.invalid }
        for record in result { try record.validate(now: now) }
        return result.sorted { $0.date > $1.date }
    }
}

struct AppleHealthType: Identifiable {
    let id: String, title: String, category: String
    let type: HKSampleType
    var unit: HKUnit? = nil
    var key: String = "value"
    static var all: [AppleHealthType] {
        var items: [AppleHealthType] = []
        func add(_ identifier: HKQuantityTypeIdentifier, _ id: String, _ title: String, _ category: String, _ unit: HKUnit, _ key: String) {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) { items.append(AppleHealthType(id: id, title: title, category: category, type: type, unit: unit, key: key)) }
        }
        add(.stepCount, "StepsRecord", "걸음", "활동", .count(), "count")
        add(.distanceWalkingRunning, "DistanceRecord", "걷기·달리기 거리", "활동", .meter(), "distanceMeters")
        add(.activeEnergyBurned, "ActiveCaloriesBurnedRecord", "활동 에너지", "활동", .kilocalorie(), "energyKcal")
        add(.heartRate, "HeartRateRecord", "심박", "생체", .count().unitDivided(by: .minute()), "beatsPerMinute")
        add(.restingHeartRate, "RestingHeartRateRecord", "안정 시 심박", "생체", .count().unitDivided(by: .minute()), "beatsPerMinute")
        add(.bodyMass, "WeightRecord", "체중", "신체", .gramUnit(with: .kilo), "weightKg")
        add(.bodyFatPercentage, "BodyFatRecord", "체지방", "신체", .percent(), "fraction")
        add(.height, "HeightRecord", "키", "신체", .meter(), "heightMeters")
        add(.dietaryWater, "HydrationRecord", "수분", "영양", .literUnit(with: .milli), "volumeMl")
        if let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { items.append(AppleHealthType(id: "SleepSessionRecord", title: "수면·단계", category: "수면", type: type)) }
        items.append(AppleHealthType(id: "ExerciseSessionRecord", title: "운동", category: "활동", type: HKObjectType.workoutType()))
        return items
    }
    func encode(_ sample: HKSample) throws -> HealthRecord {
        var fields: [String: HealthValue] = ["startTime": .number(sample.startDate.timeIntervalSince1970*1000), "endTime": .number(sample.endDate.timeIntervalSince1970*1000), "sourceName": .text(String(sample.sourceRevision.source.name.prefix(100))), "metadata": .object(["dataOrigin": .object(["packageName": .text(String(sample.sourceRevision.source.bundleIdentifier.prefix(100)))])])]
        if let value = sample as? HKQuantitySample, let unit {
            let amount = value.quantity.doubleValue(for: unit)
            fields[key] = .number(amount); fields["unit"] = .text(unit.unitString)
            switch id {
            case "WeightRecord": fields["weight"] = .object(["inGrams": .number(amount*1000)])
            case "HeightRecord": fields["height"] = .object(["inMeters": .number(amount)])
            case "DistanceRecord": fields["distance"] = .object(["inMeters": .number(amount)])
            case "ActiveCaloriesBurnedRecord": fields["energy"] = .object(["inCalories": .number(amount*1000)])
            case "BodyFatRecord": fields["percentage"] = .object(["value": .number(amount*100)])
            case "HydrationRecord": fields["volume"] = .object(["inLiters": .number(amount/1000)])
            case "HeartRateRecord": fields["samples"] = .array([.object(["beatsPerMinute": .number(amount), "time": .number(sample.endDate.timeIntervalSince1970*1000)])])
            default: break
            }
        }
        if let value = sample as? HKCategorySample {
            let labels = [0: "침대에 있음", 1: "수면·단계 미분류", 2: "깨어 있음", 3: "코어 수면", 4: "깊은 수면", 5: "REM 수면"]
            fields["stage"] = .text(labels[value.value] ?? "알 수 없는 단계"); fields["stageCode"] = .number(Double(value.value))
        }
        if let workout = sample as? HKWorkout { fields["durationSeconds"] = .number(workout.duration); fields["activityType"] = .number(Double(workout.workoutActivityType.rawValue)) }
        return HealthRecord(id: "hc:apple:" + sample.uuid.uuidString, recordType: id, date: sample.endDate, title: title, category: category, fields: fields, source: "apple-health")
    }
}

@MainActor final class AppleHealthStore: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var status = "항목을 고르고 Apple 건강 읽기를 허용해주세요."
    private let store = HKHealthStore()
    private var epoch = 0
    func cancel() { epoch += 1; busy = false; status = "결과 반영을 취소했어요. 기존 기록은 유지됩니다." }
    static let limit = 800
    func update(_ journal: Journal, selected: Set<String>, days: Int, authorize: Bool) async {
        guard !busy else { return }
        guard HKHealthStore.isHealthDataAvailable() else { status = "이 기기에서 Apple 건강을 사용할 수 없어요."; return }
        let types = AppleHealthType.all.filter { selected.contains($0.id) }
        guard !types.isEmpty else { status = "가져올 항목을 하나 이상 골라주세요."; return }
        epoch += 1; let request = epoch
        busy = true; defer { if epoch == request { busy = false } }
        do {
            if authorize { try await store.requestAuthorization(toShare: [], read: Set(types.map { $0.type as HKObjectType })) }
            guard epoch == request else { return }
            let now = Date(), start = dayOffset(1 - (days == 30 ? 30 : 7), from: Date())
            var records: [HealthRecord] = [], replace = Set<String>(), empty = 0, partial = 0, errors = 0
            for item in types {
                guard epoch == request else { return }
                do {
                    let samples: [HKSample] = try await withCheckedThrowingContinuation { continuation in
                        let query = HKSampleQuery(sampleType: item.type, predicate: HKQuery.predicateForSamples(withStart: start, end: now, options: [.strictStartDate, .strictEndDate]), limit: Self.limit + 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                            if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples ?? []) }
                        }
                        store.execute(query)
                    }
                    guard epoch == request else { return }
                    if samples.isEmpty { empty += 1; continue }
                    if samples.count > Self.limit { partial += 1 } else { replace.insert(item.id) }
                    records += try samples.prefix(Self.limit).map { try item.encode($0) }
                } catch { errors += 1 }
            }
            var next = journal.state
            guard epoch == request else { return }
            next.healthRecords = try AppleHealthMerge.merge(next.healthRecords ?? [], incoming: records, replace: replace, start: start, now: now)
            guard journal.persist(next) else { throw CareError.unreadable }
            status = "Apple 건강 \(records.count)개 확인 · 빈 결과 \(empty)항목 · 일부만 조회 \(partial)항목 · 오류 \(errors)항목. 빈 결과는 기록 없음과 읽기 권한 제한을 구별할 수 없어 기존 자료를 유지해요."
        } catch { if epoch == request { status = "Apple 건강을 읽거나 저장하지 못했어요. 건강 앱 권한과 HealthKit 서명 권한을 확인해주세요. 기존 기록은 유지했어요." } }
    }
}
