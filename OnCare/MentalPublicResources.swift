import SwiftUI
import Foundation

struct MentalNewsItem: Codable, Identifiable {
    var title: String
    var link: String
    var date: String
    var summary: String?
    var id: String { link }
}

final class MentalNewsParser: NSObject, XMLParserDelegate {
    var items: [MentalNewsItem] = []
    var hasFeed = false
    private var entry = false
    private var field = ""
    private var title = "", link = "", date = "", summary = ""
    static func allowed(_ value: String) -> Bool {
        guard let u = URL(string: value), u.scheme == "https", u.host == "www.nimh.nih.gov", u.user == nil, u.password == nil else { return false }
        return (u.port == nil || u.port == 443) && u.path.hasPrefix("/news/")
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if name == "feed" { hasFeed = true }
        if name == "entry" { entry = true; title = ""; link = ""; date = ""; summary = "" }
        field = name
        if entry && name == "link" && attributes["rel"] == "alternate" { link = attributes["href"] ?? "" }
    }
    func parser(_ parser: XMLParser, foundCharacters value: String) {
        guard entry else { return }
        if field == "title" { title += value }
        if field == "published" { date += value }
        if field == "updated" && date.isEmpty { date += value }
        if field == "summary", summary.count < 6000 { summary += value }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "entry" {
            if Self.allowed(link), !title.isEmpty, title.count <= 500, items.count < 30, !items.contains(where: { $0.link == link }) {
                items.append(MentalNewsItem(title: title, link: link, date: date, summary: summary))
            }
            entry = false
        }
        field = ""
    }
}

@MainActor final class MentalPublicFeed: ObservableObject {
    @Published var items: [MentalNewsItem] = []
    @Published var message = "공식 정신건강 소식 · 영어 원문"
    @Published var loading = false
    private let defaults = UserDefaults.standard
    init() {
        if let data = defaults.data(forKey: "mental-public-feed-v1"), data.count <= 200_000,
           let saved = try? JSONDecoder().decode([MentalNewsItem].self, from: data) {
            items = Array(saved.filter { MentalNewsParser.allowed($0.link) }.prefix(30))
        }
    }
    func refresh(force: Bool = false) async {
        guard !loading else { return }
        let previous = defaults.double(forKey: "mental-public-feed-updated")
        if !force && previous > 0 && Date().timeIntervalSince1970 - previous < 3600 {
            message = "마지막 확인 " + Date(timeIntervalSince1970: previous).formatted(date: .abbreviated, time: .shortened); return
        }
        loading = true; defer { loading = false }
        do {
            let url = URL(string: "https://www.nimh.nih.gov/site-info/index-rss.atom")!
            var request = URLRequest(url: url); request.timeoutInterval = 15
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.url?.host == url.host, http.url?.scheme == "https" else { throw URLError(.badServerResponse) }
            var data = Data()
            for try await byte in bytes { guard data.count < 1_000_000 else { throw URLError(.dataLengthExceedsMaximum) }; data.append(byte) }
            let delegate = MentalNewsParser(), parser = XMLParser(data: data)
            parser.shouldResolveExternalEntities = false; parser.delegate = delegate
            guard parser.parse(), delegate.hasFeed else { throw URLError(.cannotParseResponse) }
            items = delegate.items
            defaults.set(try JSONEncoder().encode(items), forKey: "mental-public-feed-v1")
            let now = Date(); defaults.set(now.timeIntervalSince1970, forKey: "mental-public-feed-updated")
            message = "마지막 확인 " + now.formatted(date: .abbreviated, time: .shortened)
        } catch { message = "새 소식을 가져오지 못했어요. 저장된 자료와 지원 안내는 계속 볼 수 있어요." }
    }
}

struct MentalPublicResourcesView: View {
    @StateObject private var feed = MentalPublicFeed()
    @State private var resource: MentalResource?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("마음을 위한 지원과 자료").font(.title3.bold())
            ForEach(MentalResource.support) { item in
                Button { resource = item } label: { HStack { Image(systemName: "heart.text.square"); VStack(alignment: .leading, spacing: 5) { Text(item.title).font(.headline); Text(item.source).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right") }.padding(.vertical, 10) }.buttonStyle(.plain)
            }
            Divider()
            HStack { Text("공식 정신건강 소식").font(.headline); Spacer(); Button("새로고침") { Task { await feed.refresh(force: true) } }.disabled(feed.loading) }
            Text("NIMH · 영어 원문 · 연구 소식은 개인 치료 지침이 아니에요.").font(.caption).foregroundStyle(.secondary)
            Text(feed.message).font(.caption).foregroundStyle(.secondary)
            if feed.loading { ProgressView() }
            if feed.items.isEmpty && !feed.loading { Text("새로 등록된 소식이 없어요.").font(.subheadline) }
            ForEach(feed.items.prefix(8)) { item in
                if let url = URL(string: item.link) {
                    Button { resource = MentalResource(id: item.id, title: item.title, source: "NIMH · " + String(item.date.prefix(10)) + " · 영어 원문", body: item.summary?.isEmpty == false ? item.summary! : "이 소식은 제공된 본문 요약이 없어요. 공식 원문에서 내용을 확인할 수 있습니다.", url: url, aiAllowed: item.summary?.isEmpty == false) } label: { VStack(alignment: .leading, spacing: 4) { Text(item.title); if !item.date.isEmpty { Text(String(item.date.prefix(10))).font(.caption).foregroundStyle(.secondary) } }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8) }.buttonStyle(.plain)
                }
            }
        }.padding(20).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
            .task { await feed.refresh() }
            .sheet(item: $resource) { NativeMentalResourceDetail(resource: $0) }
    }
}
