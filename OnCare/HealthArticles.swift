import Foundation
import Combine

enum ArticleTopic: String, CaseIterable, Codable, Identifiable {
    case sleep = "수면", mind = "마음", movement = "운동", nutrition = "식생활"
    var id: String { rawValue }
    var kind: String { self == .nutrition ? "체중" : rawValue }
    var symbol: String {
        switch self { case .sleep: return "moon.stars.fill"; case .mind: return "leaf.fill"; case .movement: return "figure.walk"; case .nutrition: return "carrot.fill" }
    }
}
struct HealthArticle: Identifiable {
    let id: String
    let topic: ArticleTopic
    let title: String
    let subtitle: String
    let summary: String
    let takeaways: [String]
    let action: String
    let sourceTitle: String
    let sourcePath: String
    // Only curated HTTPS links are opened. Reading the local summary makes no network request.
    var sourceURL: URL? { Self.validSourceURL("https://www.nhs.uk" + sourcePath) }
    static func validSourceURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), url.scheme == "https", url.host == "www.nhs.uk",
              url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil,
              url.path.hasPrefix("/"), !url.path.isEmpty else { return nil }
        return url
    }
    static let catalog: [HealthArticle] = [
        HealthArticle(id: "sleep-rhythm", topic: .sleep, title: "좋은 밤은, 낮부터 시작돼요", subtitle: "나에게 맞는 수면 리듬 만들기",
            summary: "수면은 시간뿐 아니라 낮의 컨디션과 함께 살펴볼 수 있어요. NHS는 일정한 취침·기상 시간과 잠들기 전 편안한 준비를 권합니다.",
            takeaways: ["대부분의 건강한 성인은 밤에 약 7~9시간의 수면이 필요하지만, 개인차가 있어요.", "늦은 카페인, 밝은 화면, 침실의 소음과 온도를 돌아보세요.", "수면 문제가 계속되고 일상에 영향을 준다면 의료진과 상담하세요."],
            action: "오늘은 잠들기 전 화면을 내려놓고, 편안한 준비 시간을 만들어보세요.", sourceTitle: "Sleep problems · Every Mind Matters", sourcePath: "/every-mind-matters/mental-health-issues/sleep/"),
        HealthArticle(id: "mind-five", topic: .mind, title: "마음에도, 작은 여유를", subtitle: "일상에서 실천하는 마음 돌봄",
            summary: "마음을 돌보는 습관은 거창할 필요가 없어요. NHS는 관계, 움직임, 배움, 나눔, 현재에 집중하는 시간을 마음 건강을 위한 다섯 가지 방향으로 소개합니다.",
            takeaways: ["가까운 사람과 잠깐 대화하며 연결되는 시간을 가져보세요.", "좋아하는 움직임이나 새로운 취미를 내 생활에 맞게 골라보세요.", "지금 느끼는 감정과 몸의 감각을 천천히 알아차려보세요."],
            action: "오늘 고마웠던 순간 하나를 떠올리고, 마음 기록에 남겨보세요.", sourceTitle: "5 steps to mental wellbeing", sourcePath: "/mental-health/self-help/guides-tools-and-activities/five-steps-to-mental-wellbeing/"),
        HealthArticle(id: "move-small", topic: .movement, title: "조금씩 움직여도, 쌓이니까", subtitle: "유산소와 근력 활동의 균형",
            summary: "NHS의 19~64세 성인 지침은 오래 앉아 있는 시간을 줄이고, 유산소와 근력 활동을 함께 실천하도록 안내합니다. 내 체력에 맞춰 시작해요.",
            takeaways: ["주간 목표는 중강도 활동 150분 또는 고강도 활동 75분이에요.", "주요 근육을 사용하는 근력 활동은 주 2일 이상 권장돼요.", "오랜만에 운동하거나 질환·걱정이 있다면 의료진과 강도를 상의하세요."],
            action: "오래 앉아 있었다면, 가능한 범위에서 잠깐 움직여보세요.", sourceTitle: "Physical activity guidelines for adults aged 19 to 64", sourcePath: "/live-well/exercise/physical-activity-guidelines-for-adults-aged-19-to-64/"),
        HealthArticle(id: "food-steady", topic: .nutrition, title: "숫자보다, 오래 갈 습관", subtitle: "무리하지 않는 식생활 돌아보기",
            summary: "체중 관리가 필요할 때도 모든 습관을 한꺼번에 바꿀 필요는 없어요. NHS의 생활 안내에서 지속하기 쉬운 작은 선택을 골라보세요.",
            takeaways: ["채소와 과일을 식사에 더하고, 달콤한 음료를 물로 바꾸는 선택부터 시작할 수 있어요.", "갑작스러운 다이어트나 끼니 거르기보다 꾸준한 식사 습관을 살펴보세요.", "이 글은 감량이 필요한 성인을 위한 안내이며, 모든 사람에게 감량을 권하는 것은 아니에요."],
            action: "오늘 식사에서 꾸준히 이어갈 수 있는 작은 변화 하나를 골라보세요.", sourceTitle: "Tips to help you lose weight", sourcePath: "/live-well/healthy-weight/managing-your-weight/tips-to-help-you-lose-weight/"),
        HealthArticle(id: "sleep-winddown", topic: .sleep, title: "잠들기 전, 한 템포 느리게", subtitle: "편안한 준비 시간 만들기", summary: "조용하고 어두운 환경과 일정한 리듬이 잠들기 준비에 도움을 줄 수 있어요.", takeaways: ["가능한 날에는 비슷한 시각에 자고 일어나보세요.", "잠들기 전 읽기·편안한 음악처럼 나에게 맞는 활동을 골라보세요.", "밤에 계속 깨어 있다면 억지로 잠을 청하기보다 편안한 활동 후 졸릴 때 돌아오세요."], action: "오늘 저녁 준비할 편안한 활동 하나를 정해보세요.", sourceTitle: "How to fall asleep faster and sleep better", sourcePath: "/every-mind-matters/mental-wellbeing-tips/how-to-fall-asleep-faster-and-sleep-better/"),
        HealthArticle(id: "sleep-energy", topic: .sleep, title: "쉬어도 피곤한 날에는", subtitle: "수면과 낮의 컨디션 함께 보기", summary: "피곤함은 수면·생활 리듬·스트레스 등 여러 요인과 관련될 수 있어요.", takeaways: ["규칙적인 식사와 내 체력에 맞는 움직임을 살펴보세요.", "늦은 카페인이 잠과 다음 날 컨디션에 영향을 주는지 기록해보세요.", "휴식으로 풀리지 않는 피로가 지속되면 의료진에게 상담하세요."], action: "내일 아침 컨디션과 어젯밤 수면을 함께 적어보세요.", sourceTitle: "Self-help tips to fight tiredness", sourcePath: "/live-well/sleep-and-tiredness/self-help-tips-to-fight-fatigue/"),
        HealthArticle(id: "mind-breathe", topic: .mind, title: "호흡에 잠깐 머물러요", subtitle: "억지로 깊게 쉬지 않아도 돼요", summary: "편안한 자세에서 부드럽게 숨을 들이쉬고 내쉬는 짧은 연습을 해볼 수 있어요.", takeaways: ["몸을 편안하게 두고 조이는 옷을 느슨하게 해보세요.", "내 몸에 편한 깊이로 천천히 호흡하세요.", "숫자 세기가 편하다면 들숨과 날숨에 부드럽게 맞춰보세요."], action: "편안한 호흡을 몇 분 연습해보세요. 불편하면 멈춰요.", sourceTitle: "Breathing exercises for stress", sourcePath: "/mental-health/self-help/guides-tools-and-activities/breathing-exercises-for-stress/"),
        HealthArticle(id: "move-everyday", topic: .movement, title: "오늘의 움직임을 찾아요", subtitle: "생활 속 활동도 운동의 시작", summary: "걷기와 자전거처럼 일상에 어울리는 활동은 꾸준히 움직이는 출발점이 될 수 있어요.", takeaways: ["짧은 거리에서 내 상황에 맞는 활동을 골라보세요.", "처음에는 작은 양으로 시작해 서서히 늘려보세요.", "오래 앉아 있는 시간도 돌아보고 가능한 만큼 중간에 움직여보세요."], action: "다음 쉬는 시간에 가볍게 움직일 기회를 찾아보세요.", sourceTitle: "Benefits of exercise", sourcePath: "/live-well/exercise/exercise-health-benefits/"),
        HealthArticle(id: "food-hydration", topic: .nutrition, title: "물 한 모금의 습관", subtitle: "내 상황에 맞는 수분 섭취", summary: "수분은 음료뿐 아니라 음식에서도 얻어요. 필요한 양은 더위·활동·개인 상태에 따라 달라요.", takeaways: ["하루 동안 규칙적으로 마실 기회를 만들어보세요.", "당이 많은 음료 대신 물이나 당이 적은 음료를 선택할 수 있어요.", "의료진이 수분을 제한했다면 일반 앱 목표보다 그 지침을 따르세요."], action: "자주 머무는 곳에 마실 물을 준비해보세요.", sourceTitle: "Water, drinks and hydration", sourcePath: "/live-well/eat-well/food-guidelines-and-food-labels/water-drinks-nutrition/"),
        HealthArticle(id: "food-balance", topic: .nutrition, title: "한 끼보다, 며칠의 균형", subtitle: "꾸준한 식생활 돌아보기", summary: "식품군의 균형은 매 끼니 완벽하게 맞추기보다 하루와 일주일의 식사를 함께 살펴볼 수 있어요.", takeaways: ["여러 종류의 채소·과일을 골라보세요.", "통곡물과 단백질 식품을 내 식사에 맞게 조합해보세요.", "건강 상태에 따른 식사 지침이 있다면 의료진과 맞춰보세요."], action: "이번 주 식사에서 더해볼 식품군 하나를 골라보세요.", sourceTitle: "The Eatwell Guide", sourcePath: "/live-well/eat-well/food-guidelines-and-food-labels/the-eatwell-guide/")
    ]
}
struct ArticleRecommendation: Identifiable {
    let article: HealthArticle
    let reason: String
    var id: String { article.id }
}
enum ArticleRecommender {
    private struct RankedArticle {
        let index: Int
        let article: HealthArticle
        let score: Int
    }
    static func recommendations(interests: Set<ArticleTopic>, recentKinds: Set<String>, read: Set<String>) -> [ArticleRecommendation] {
        var ranked: [RankedArticle] = []
        for (index, article) in HealthArticle.catalog.enumerated() {
            var score = interests.contains(article.topic) ? 4 : 0
            if recentKinds.contains(article.topic.kind) { score += 2 }
            if !read.contains(article.id) { score += 1 }
            ranked.append(RankedArticle(index: index, article: article, score: score))
        }
        ranked.sort { $0.score == $1.score ? $0.index < $1.index : $0.score > $1.score }
        return ranked.map { item in
            let article = item.article
            var reason = "온케어가 고른 일상 건강 읽을거리"
            if interests.contains(article.topic) { reason = "선택한 관심 주제 · \(article.topic.rawValue)" }
            else if recentKinds.contains(article.topic.kind) { reason = "최근 7일에 \(article.topic.kind) 기록이 있어요" }
            return ArticleRecommendation(article: article, reason: reason)
        }
    }
    static func recentKinds(entries: [Entry], now: Date = Date()) -> Set<String> {
        let from = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        return Set(entries.filter { $0.date >= from && $0.date <= now }.map(\.kind))
    }
}
@MainActor final class ArticleLibrary: ObservableObject {
    @Published private(set) var interests: Set<ArticleTopic>
    @Published private(set) var saved: Set<String>
    @Published private(set) var read: Set<String>
    @Published var useRecords: Bool { didSet { defaults.set(useRecords, forKey: prefix + "records") } }
    private let defaults: UserDefaults
    private let prefix = "care-articles-v1."
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        interests = Set((defaults.stringArray(forKey: "care-articles-v1.interests") ?? []).compactMap(ArticleTopic.init(rawValue:)))
        let ids = Set(HealthArticle.catalog.map(\.id))
        saved = Set(defaults.stringArray(forKey: "care-articles-v1.saved") ?? []).intersection(ids)
        read = Set(defaults.stringArray(forKey: "care-articles-v1.read") ?? []).intersection(ids)
        useRecords = defaults.object(forKey: "care-articles-v1.records") as? Bool ?? false
    }
    func toggleInterest(_ topic: ArticleTopic) {
        if interests.contains(topic) { interests.remove(topic) } else { interests.insert(topic) }
        defaults.set(interests.map(\.rawValue).sorted(), forKey: prefix + "interests")
    }
    func toggleSaved(_ id: String) {
        guard HealthArticle.catalog.contains(where: { $0.id == id }) else { return }
        if saved.contains(id) { saved.remove(id) } else { saved.insert(id) }
        defaults.set(saved.sorted(), forKey: prefix + "saved")
    }
    func markRead(_ id: String) {
        guard HealthArticle.catalog.contains(where: { $0.id == id }) else { return }
        read.insert(id); defaults.set(read.sorted(), forKey: prefix + "read")
    }
    func recommendations(entries: [Entry]) -> [ArticleRecommendation] {
        ArticleRecommender.recommendations(interests: interests, recentKinds: useRecords ? ArticleRecommender.recentKinds(entries: entries) : [], read: read)
    }
}
