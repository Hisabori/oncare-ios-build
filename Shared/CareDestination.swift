import Foundation

/// Fixed navigation destinations shared by the app and its widgets. No personal data goes in a URL.
enum CareDestination: String, CaseIterable, Identifiable, Equatable {
    case sleep = "sleep", workout = "workout", mood = "mood", connect = "connect", medication = "medication", articles = "articles", intelligence = "intelligence"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sleep: return "수면 루틴"
        case .workout: return "운동 타이머"
        case .mood: return "마음 기록"
        case .connect: return "건강 연결"
        case .medication: return "투약 확인"
        case .articles: return "마음 읽을거리"
        case .intelligence: return "기록 인사이트"
        }
    }
    var symbol: String {
        switch self {
        case .sleep: return "moon.zzz.fill"
        case .workout: return "figure.walk"
        case .mood: return "heart.text.square.fill"
        case .connect: return "arrow.triangle.2.circlepath"
        case .medication: return "pills.fill"
        case .articles: return "book.closed.fill"
        case .intelligence: return "sparkles"
        }
    }
    var url: URL { URL(string: "oncare://open/" + rawValue)! }
    var quickActionType: String { "app.oncare.open." + rawValue }

    static func parse(_ url: URL) -> CareDestination? {
        guard url.absoluteString.count <= 128,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "oncare", components.host?.lowercased() == "open",
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil else { return nil }
        // Reject escaped paths, extra segments and trailing slashes rather than normalizing user input.
        return allCases.first { components.percentEncodedPath == "/" + $0.rawValue }
    }
    static func parse(quickActionType: String) -> CareDestination? {
        allCases.first { $0.quickActionType == quickActionType }
    }
}

struct CareRouteRequest: Equatable {
    let id: UUID
    let destination: CareDestination
    init(destination: CareDestination) { id = UUID(); self.destination = destination }
}
