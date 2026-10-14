import AppIntents

struct OpenCareMedicationIntent: AppIntent {
    static var title: LocalizedStringResource = "투약 확인 열기"
    static var description = IntentDescription("투약 계획과 오늘 확인 화면을 엽니다. 복용 여부는 직접 확인합니다.")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult { CareShortcutRouter.shared.open(.medication); return .result() }
}
struct OpenCareArticlesIntent: AppIntent {
    static var title: LocalizedStringResource = "마음 읽을거리 열기"
    static var description = IntentDescription("정신건강 아티클과 공공 지원 자료를 엽니다.")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult { CareShortcutRouter.shared.open(.articles); return .result() }
}
struct OpenCareIntelligenceIntent: AppIntent {
    static var title: LocalizedStringResource = "기록 인사이트 열기"
    static var description = IntentDescription("기기 내 Apple Intelligence 기록 회고 화면을 엽니다. 요약은 직접 요청합니다.")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult { CareShortcutRouter.shared.open(.intelligence); return .result() }
}
