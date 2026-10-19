import SwiftUI
import SafariServices

extension ArticleTopic {
    var color: Color { self == .sleep ? Palette.purple : self == .mind ? Palette.teal : self == .movement ? Palette.blue : Palette.coral }
}
struct ArticleArtwork: View {
    let topic: ArticleTopic
    var body: some View {
        ZStack {
            LinearGradient(colors: [topic.color.opacity(0.18), topic.color.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(topic.color.opacity(0.08)).frame(width: 150, height: 150).offset(x: 90, y: 40)
            Circle().stroke(topic.color.opacity(0.14), lineWidth: 1).frame(width: 190, height: 190).offset(x: -80, y: -40)
            Image(systemName: topic.symbol).font(.system(size: 55, weight: .light)).foregroundStyle(topic.color)
        }.frame(height: 150).clipped().accessibilityHidden(true)
    }
}
struct ArticleTile: View {
    @EnvironmentObject private var library: ArticleLibrary
    let recommendation: ArticleRecommendation
    var article: HealthArticle { recommendation.article }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ArticleArtwork(topic: article.topic)
            VStack(alignment: .leading, spacing: 9) {
                HStack { Text(article.topic.rawValue).foregroundStyle(article.topic.color); Spacer(); if library.saved.contains(article.id) { Image(systemName: "bookmark.fill").accessibilityLabel("저장됨") } }.font(.caption.weight(.semibold))
                Text(article.title).font(.title3.bold()).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                Text(article.subtitle).font(.subheadline).foregroundStyle(.secondary)
                Text(recommendation.reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack { Text("NHS · 한국어 요약"); Spacer(); if library.read.contains(article.id) { Text("읽음") }; Text("1분 읽기") }.font(.caption2).foregroundStyle(.secondary)
            }.padding(18)
        }.background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26)).clipShape(RoundedRectangle(cornerRadius: 26))
    }
}
struct ArticleRecommendationsSection: View {
    @EnvironmentObject private var journal: Journal
    @EnvironmentObject private var library: ArticleLibrary
    @State private var selected: HealthArticle?
    @State private var showLibrary = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("나를 위한 읽을거리").font(.title2.bold()); Spacer(); Button("모두 보기") { showLibrary = true }.font(.subheadline).accessibilityIdentifier("articles-all") }
            Text("오늘의 작은 변화에 도움이 되는 이야기").font(.subheadline).foregroundStyle(.secondary)
            if let recommendation = library.recommendations(entries: journal.entries).first {
                Button { selected = recommendation.article } label: { ArticleTile(recommendation: recommendation) }.buttonStyle(.plain).accessibilityIdentifier("article-featured")
            }
        }.sheet(item: $selected) { ArticleDetailView(article: $0) }
            .sheet(isPresented: $showLibrary) { ArticleLibraryView(isSheet: true) }
    }
}
struct ArticleLibraryView: View {
    @EnvironmentObject private var journal: Journal
    @EnvironmentObject private var library: ArticleLibrary
    @Environment(\.dismiss) private var dismiss
    var isSheet = false
    @State private var selected: HealthArticle?
    @State private var savedOnly = false
    @State private var unreadOnly = false
    @State private var search = ""
    @State private var showPublic = false
    @State private var showPreferences = false
    private var recommendations: [ArticleRecommendation] {
        library.recommendations(entries: journal.entries).filter {
            (!savedOnly || library.saved.contains($0.id)) && (!unreadOnly || !library.read.contains($0.id)) && ArticleSearch.matches($0.article, query: search)
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) { Text("나를 알아가는 시간").font(.largeTitle.bold()); Text("믿을 수 있는 자료, 일상에 닿는 이야기.").font(.subheadline).foregroundStyle(.secondary) }
                    ArticleRecentSection { selected = $0 }
                    Button { showPublic = true } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "books.vertical.fill").font(.title2).foregroundStyle(Palette.teal)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("마음건강 공공 자료").font(.headline).foregroundStyle(.primary)
                                Text("지원 안내 · NIMH 소식 · 국립정신건강센터").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }.careCard()
                    }.buttonStyle(.plain).accessibilityIdentifier("articles-public")
                    Button { withAnimation { showPreferences.toggle() } } label: {
                        HStack { Label("추천 설정", systemImage: "slider.horizontal.3"); Spacer(); Image(systemName: showPreferences ? "chevron.up" : "chevron.down") }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    }.accessibilityIdentifier("articles-preferences").accessibilityValue(showPreferences ? "펼쳐짐" : "접힘")
                    if showPreferences { preferences }
                    Picker("읽을거리", selection: $savedOnly) { Text("추천").tag(false); Text("저장한 글").tag(true) }.pickerStyle(.segmented).accessibilityIdentifier("articles-filter")
                    Toggle("아직 안 읽은 글만", isOn: $unreadOnly).font(.subheadline).accessibilityIdentifier("articles-unread")
                    HStack {
                        Text("\(recommendations.count)편" + (savedOnly ? " · 저장한 글" : " · 추천 글")).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("articles-result-count")
                        Spacer()
                        if !search.isEmpty || savedOnly || unreadOnly { Button("필터 초기화") { search = ""; savedOnly = false; unreadOnly = false }.font(.caption).frame(minHeight: 44).accessibilityIdentifier("articles-clear-filters") }
                    }
                    if recommendations.isEmpty {
                        VStack(spacing: 12) { Image(systemName: savedOnly ? "bookmark" : "magnifyingglass").font(.largeTitle).foregroundStyle(Palette.purple); Text(!search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || unreadOnly ? "검색어나 필터를 바꿔보세요" : savedOnly ? "간직하고 싶은 글을 저장해보세요" : "다른 단어로 찾아보세요").font(.headline) }.frame(maxWidth: .infinity).padding(.vertical, 28).accessibilityIdentifier("articles-empty")
                    }
                    ForEach(recommendations) { recommendation in
                        Button { selected = recommendation.article } label: { ArticleTile(recommendation: recommendation) }.buttonStyle(.plain).accessibilityIdentifier("article-" + recommendation.id)
                    }
                    Text("공공 의료기관 NHS 자료를 온케어가 한국어로 정리한 \(HealthArticle.catalog.count)편의 큐레이션이에요. 원문은 영어이며, 일반적인 건강 정보입니다. 자동으로 최신 글을 가져오지는 않아요.").font(.caption).foregroundStyle(.secondary)
                }.padding(22)
            }.background(Color(.systemGroupedBackground)).navigationTitle("읽을거리").navigationBarTitleDisplayMode(.inline)
                .searchable(text: $search, prompt: "제목·본문 검색 (예: 수면 카페인)")
                .toolbar { if isSheet { ToolbarItem(placement: .navigationBarTrailing) { Button("닫기") { dismiss() } } } }
                .sheet(item: $selected) { ArticleDetailView(article: $0) }
                .sheet(isPresented: $showPublic) { PublicArticleLibraryView() }
        }
    }
    private var preferences: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("요즘, 관심 있는 주제").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 10) {
                ForEach(ArticleTopic.allCases) { topic in
                    Button { library.toggleInterest(topic) } label: {
                        Label(topic.rawValue, systemImage: library.interests.contains(topic) ? "checkmark.circle.fill" : topic.symbol)
                            .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity).padding(12).foregroundStyle(topic.color)
                            .background(topic.color.opacity(library.interests.contains(topic) ? 0.18 : 0.06), in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain).accessibilityIdentifier("interest-" + topic.id).accessibilityValue(library.interests.contains(topic) ? "선택됨" : "선택 안 됨")
                }
            }
            Toggle("최근 기록 주제로도 추천", isOn: $library.useRecords).font(.subheadline).accessibilityIdentifier("articles-use-records")
            Text("켜면 최근 7일에 기록한 항목의 종류만 참고해요. 수치·메모를 분석하거나 외부로 보내지 않아요. 관심 주제와 읽지 않은 글을 먼저 보여줘요.").font(.caption).foregroundStyle(.secondary)
        }.careCard()
    }
}
struct ArticleDetailView: View {
    @EnvironmentObject private var library: ArticleLibrary
    @Environment(\.dismiss) private var dismiss
    let article: HealthArticle
    @State private var showSource = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ArticleArtwork(topic: article.topic).clipShape(RoundedRectangle(cornerRadius: 28))
                    VStack(alignment: .leading, spacing: 10) {
                        Text(article.topic.rawValue + " · 1분 읽기").font(.caption.weight(.semibold)).foregroundStyle(article.topic.color)
                        Text(article.title).font(.largeTitle.bold()).accessibilityIdentifier("article-title")
                        Text(article.subtitle).font(.title3).foregroundStyle(.secondary)
                    }
                    Text(article.summary).font(.body).lineSpacing(6).textSelection(.enabled)
                    VStack(alignment: .leading, spacing: 16) {
                        Text("기억해두면 좋은 것").font(.title3.bold())
                        ForEach(Array(article.takeaways.enumerated()), id: \.offset) { index, takeaway in
                            HStack(alignment: .top, spacing: 12) { Text(String(index + 1)).font(.caption.bold()).foregroundStyle(article.topic.color).padding(7).background(article.topic.color.opacity(0.10), in: Circle()); Text(takeaway).font(.body).lineSpacing(4) }
                        }
                    }.careCard()
                    VStack(alignment: .leading, spacing: 10) { Label("오늘, 하나만", systemImage: "sparkle").font(.headline).foregroundStyle(article.topic.color); Text(article.action).lineSpacing(4) }.careCard()
                    ArticleIntelligencePanel(text: article.summary + "\n" + article.takeaways.joined(separator: "\n"))
                    Button("나중에 다시 읽기 · 읽지 않음으로 표시") { library.markUnread(article.id); dismiss() }.frame(minHeight: 44).accessibilityIdentifier("article-mark-unread")
                    sourceCard
                }.padding(22)
            }.background(Color(.systemGroupedBackground)).navigationTitle("건강 이야기").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) { Button("닫기") { dismiss() }.accessibilityIdentifier("article-close") }
                    ToolbarItem(placement: .navigationBarTrailing) { Button { library.toggleSaved(article.id) } label: { Image(systemName: library.saved.contains(article.id) ? "bookmark.fill" : "bookmark") }.accessibilityLabel(library.saved.contains(article.id) ? "저장 취소" : "글 저장").accessibilityIdentifier("article-save") }
                }.onAppear { library.recordOpened(article.id); library.markRead(article.id) }
                .sheet(isPresented: $showSource) { if let url = article.sourceURL { ArticleSourceView(url: url).ignoresSafeArea() } }
        }
    }
    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("자료 출처").font(.headline)
            Text("NHS · 영국 공공 의료기관").font(.subheadline.weight(.medium))
            Text(article.sourceTitle).font(.caption).foregroundStyle(.secondary)
            Text("한국어 요약: 온케어 · 링크 확인: 2026.10.12\n원문은 영어로 열리며 인터넷 연결이 필요해요. 개인 진단이나 치료를 위한 글은 아닙니다.").font(.caption).foregroundStyle(.secondary)
            Button { showSource = true } label: { Label("NHS 원문 읽기 · 영어", systemImage: "safari").font(.subheadline.weight(.semibold)).frame(minHeight: 44) }.disabled(article.sourceURL == nil).accessibilityIdentifier("article-source")
        }.careCard()
    }
}
struct ArticleSourceView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

struct PublicArticleLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("도움이 필요할 때, 믿을 수 있는 곳에서").font(.title2.bold())
                    Text("지원 안내와 기관에서 공개한 소식·자료를 모았어요. 새 자료를 가져오려면 인터넷 연결이 필요해요.").font(.subheadline).foregroundStyle(.secondary)
                    MentalPublicResourcesView()
                    NCMHLibraryView()
                }.padding(22)
            }.background(Color(.systemGroupedBackground)).navigationTitle("마음건강 공공 자료")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
    }
}

