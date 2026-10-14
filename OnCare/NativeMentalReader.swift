import SwiftUI
import PDFKit

struct MentalResource: Identifiable {
    let id: String
    let title: String
    let source: String
    let body: String
    let url: URL
    var aiAllowed = false
    static let support: [MentalResource] = [
        .init(id: "local", title: "내 지역에서 마음건강 도움 찾기", source: "국가정신건강정보포털 · 온케어 안내", body: "지역 정신건강복지센터는 지역사회 정신건강 서비스를 제공합니다.\n\n먼저 거주 지역의 기관을 찾아 상담 가능한 서비스와 이용 방법을 문의해보세요. 센터별 운영 시간과 제공 서비스는 다를 수 있습니다.\n\n문의 전에 준비해요\n• 거주 지역\n• 도움이 필요한 내용\n• 이용하고 싶은 상담·치료\n\n예약 여부, 필요한 서류, 비용은 해당 기관에서 확인하세요.", url: URL(string: "https://www.mentalhealth.go.kr/portal/health/fac/PotalHealthFacListTab1.do")!),
        .init(id: "voucher", title: "심리상담 바우처 알아보기", source: "화성시 보건소 · 2026 변경 안내 · 온케어 정리", body: "정신건강 심리상담 바우처사업은 전문 심리상담 이용을 지원하는 사업입니다. 기존 ‘전국민 마음투자 지원사업’의 명칭이 변경되었습니다.\n\n신청 전 확인할 것\n• 현재 신청 가능한지\n• 대상 확인을 위한 의뢰서 등 필요한 서류\n• 본인부담금과 이용 가능한 제공기관\n\n이 안내의 출처는 화성시 보건소입니다. 다른 지역에서는 거주지 주민센터나 담당기관에 현재 기준을 확인하세요. 앱에서는 지원 자격을 판단하거나 신청하지 않습니다.", url: URL(string: "https://www.hscity.go.kr/health/user/bbs/BD_selectBbs.do?q_bbsCode=1001&q_bbscttSn=20251223150332050")!),
        .init(id: "care", title: "작은 마음 돌봄부터 시작해요", source: "NIMH · Caring for Your Mental Health · 한국어 정리", body: "나를 돌보는 방법은 사람마다 다를 수 있어요. 작고 지속 가능한 활동을 찾아보세요.\n\n• 내 상황에 맞게 조금씩 움직이기\n• 규칙적인 식사와 수면을 챙기기\n• 편안한 호흡이나 좋아하는 취미로 쉬기\n• 지금 할 일과 나중에 할 일을 구분하기\n• 도움을 주고받을 수 있는 사람과 연결하기\n\n불편한 증상이 지속되거나 일상에 어려움이 있다면 전문가와 상의할 수 있어요. 이 글은 일반 정보이며 개인의 진단이나 치료 지침이 아닙니다.", url: URL(string: "https://www.nimh.nih.gov/health/topics/caring-for-your-mental-health")!, aiAllowed: true)
    ]
}

struct NativeMentalResourceDetail: View {
    let resource: MentalResource
    @Environment(\.dismiss) private var dismiss
    @State private var source = false
    var body: some View {
        NavigationStack {
            ScrollView { VStack(alignment: .leading, spacing: 20) {
                Label("마음을 위한 자료", systemImage: "heart.text.square.fill").foregroundStyle(Palette.teal)
                Text(resource.title).font(.largeTitle.bold())
                Text(resource.source).font(.caption).foregroundStyle(.secondary)
                Text(resource.body).font(.body).lineSpacing(7).textSelection(.enabled)
                if resource.aiAllowed { ArticleIntelligencePanel(text: resource.body) }
                Button("공식 원문 · 앱 안에서 열기") { source = true }.frame(minHeight: 44)
            }.padding(24) }.background(Color(.systemGroupedBackground))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
                .sheet(isPresented: $source) { ArticleSourceView(url: resource.url).ignoresSafeArea() }
        }
    }
}

struct NCMHPublication: Codable, Identifiable {
    let title: String
    let path: String
    var id: String { path }
    var registeredMonth: String { String(path.prefix(8).dropFirst()).replacingOccurrences(of: "/", with: ".") }
    var url: URL? {
        guard Self.validPath(path) else { return nil }
        var u = URLComponents(string: "https://www.ncmh.go.kr/static/jsp/viewHtmlDownload.jsp")!
        u.queryItems = [URLQueryItem(name: "filePath", value: path), URLQueryItem(name: "filename", value: "mental-health.pdf")]
        return u.url
    }
    static func validPath(_ value: String) -> Bool { value.range(of: "^/[0-9]{4}/[0-9]{2}/[0-9_]+\\.pdf$", options: .regularExpression) != nil }
    static func parse(_ html: String) throws -> [NCMHPublication] {
        guard html.utf8.count <= 1_000_000, html.contains("web_ttl"), html.contains("공공누리") else { throw CareError.unreadable }
        let regex = try NSRegularExpression(pattern: "(?s)<span\\s+class=\"web_ttl\">([^<]{1,300})</span>.*?fn_fileDown\\('([^']{1,300})','(/[^']{1,200}\\.pdf)','[0-9]+'\\)")
        let ns = html as NSString
        var paths = Set<String>()
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let title = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let path = ns.substring(with: match.range(at: 3))
            guard validPath(path), paths.insert(path).inserted else { return nil }
            return NCMHPublication(title: title, path: path)
        }.prefix(12).map { $0 }
    }
}

@MainActor final class NCMHLibrary: ObservableObject {
    @Published var items: [NCMHPublication] = []
    @Published var status = "국립정신건강센터 · 마음로그人"
    @Published var loading = false
    private let defaults = UserDefaults.standard
    init() { if let data = defaults.data(forKey: "ncmh-library-v1"), data.count < 100_000, let saved = try? JSONDecoder().decode([NCMHPublication].self, from: data) { items = Array(saved.filter { NCMHPublication.validPath($0.path) }.prefix(12)) } }
    func refresh(force: Bool = false) async {
        guard !loading else { return }
        let previous = defaults.double(forKey: "ncmh-library-updated")
        if !force && previous > 0 && Date().timeIntervalSince1970 - previous < 3600 { status = "마지막 확인 " + Date(timeIntervalSince1970: previous).formatted(date: .abbreviated, time: .shortened); return }
        loading = true; defer { loading = false }
        do {
            var request = URLRequest(url: URL(string: "https://www.ncmh.go.kr/ncmh/board/webzineList.do?fno=50&menu_cd=04_05")!); request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url?.host == "www.ncmh.go.kr", http.url?.scheme == "https", let html = String(data: data, encoding: .utf8) else { throw CareError.unreadable }
            let result = try NCMHPublication.parse(html)
            guard !result.isEmpty else { throw CareError.unreadable }
            items = result; defaults.set(try JSONEncoder().encode(items), forKey: "ncmh-library-v1")
            let now = Date(); defaults.set(now.timeIntervalSince1970, forKey: "ncmh-library-updated")
            status = "마지막 확인 " + now.formatted(date: .abbreviated, time: .shortened)
        } catch { status = "자료 목록을 갱신하지 못했어요. 이전 자료를 유지합니다." }
    }
}

struct NCMHLibraryView: View {
    @StateObject private var library = NCMHLibrary()
    @State private var selected: NCMHPublication?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("국립정신건강센터 소식지").font(.title3.bold()); Spacer(); Button("갱신") { Task { await library.refresh(force: true) } }.disabled(library.loading) }
            Text(library.status).font(.caption).foregroundStyle(.secondary)
            Text("마음로그人 · 원문 PDF · 공공누리 제4유형: 출처표시, 비영리, 변경금지").font(.caption).foregroundStyle(.secondary)
            if library.loading { ProgressView() }
            ForEach(library.items) { item in
                Button { selected = item } label: { VStack(alignment: .leading, spacing: 8) {
                    Label("NCMH · 정신건강 소식지", systemImage: "book.closed.fill").font(.caption).foregroundStyle(Palette.teal)
                    Text(item.title).font(.title3.bold()).foregroundStyle(.primary)
                    Text("자료 등록월 " + item.registeredMonth + " · 앱에서 읽기").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26)) }.buttonStyle(.plain)
            }
        }.task { await library.refresh() }.sheet(item: $selected) { NCMHPDFReader(publication: $0) }
    }
}

struct NCMHPDFSurface: UIViewRepresentable {
    let document: PDFDocument
    func makeUIView(context: Context) -> PDFView { let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous; view.displayDirection = .vertical; view.document = document; return view }
    func updateUIView(_ view: PDFView, context: Context) { if view.document !== document { view.document = document } }
}
struct NCMHPDFReader: View {
    let publication: NCMHPublication
    @Environment(\.dismiss) private var dismiss
    @State private var document: PDFDocument?
    @State private var error = ""
    @State private var request = 0
    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Text("국립정신건강센터 · " + publication.title + " · 자료 등록월 " + publication.registeredMonth).font(.caption).padding(.horizontal)
                Text("공공누리 제4유형 · 출처표시 · 비영리 · 변경금지 · 원문 유지").font(.caption2).foregroundStyle(.secondary)
                if let document { NCMHPDFSurface(document: document) }
                else if !error.isEmpty { Text(error).padding(); Button("다시 시도") { request += 1 } }
                else { Spacer(); ProgressView("원문을 가져오는 중…"); Text("문서 크기에 따라 데이터와 시간이 필요해요.").font(.caption); Spacer() }
            }.navigationTitle("정신건강 소식지").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
                .task(id: request) {
                    error = ""
                    do {
                        guard let url = publication.url else { throw CareError.unreadable }
                        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ncmh-" + (publication.path as NSString).lastPathComponent)
                        if let saved = PDFDocument(url: cache), saved.pageCount > 0 { document = saved; return }
                        var r = URLRequest(url: url); r.timeoutInterval = 60
                        let (file, response) = try await URLSession.shared.download(for: r)
                        defer { try? FileManager.default.removeItem(at: file) }
                        guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url?.host == "www.ncmh.go.kr", http.url?.scheme == "https", let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 50_000_000 else { throw CareError.unreadable }
                        try Task.checkCancellation()
                        guard let pdf = PDFDocument(url: file), pdf.pageCount > 0 else { throw CareError.unreadable }
                        try? FileManager.default.removeItem(at: cache); try FileManager.default.copyItem(at: file, to: cache)
                        document = PDFDocument(url: cache)
                    } catch is CancellationError { } catch { if !Task.isCancelled { error = "원문을 불러오지 못했어요. 연결 상태를 확인해주세요." } }
                }
        }
    }
}
