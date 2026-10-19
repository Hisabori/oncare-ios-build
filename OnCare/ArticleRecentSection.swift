import SwiftUI

struct ArticleRecentSection: View {
    @EnvironmentObject private var library: ArticleLibrary
    let open: (HealthArticle) -> Void
    var body: some View {
        DisclosureGroup("최근 열어본 글 · \(library.recent.count)편") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("최근 목록 저장", isOn: $library.keepRecent)
                Text("앱 안의 큐레이션 글을 최근 순서로 최대 10편 저장해요. 공공 자료·외부 원문은 포함하지 않습니다. 끄면 최근 목록을 지우며, 저장한 글과 읽음 표시는 유지돼요.").font(.caption).foregroundStyle(.secondary)
                if library.recent.isEmpty { Text(library.keepRecent ? "글을 열면 여기에 표시돼요." : "최근 목록 저장이 꺼져 있어요.").font(.subheadline).foregroundStyle(.secondary) }
                ForEach(library.recent, id: \.self) { id in
                    if let article = HealthArticle.catalog.first(where: { $0.id == id }) {
                        Button { open(article) } label: { HStack { Image(systemName: article.topic.symbol).foregroundStyle(article.topic.color); Text(article.title).multilineTextAlignment(.leading); Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary) }.frame(minHeight: 44) }.accessibilityIdentifier("recent-article-" + id)
                    }
                }
                if !library.recent.isEmpty { Button("최근 목록 지우기", role: .destructive) { library.clearRecent() }.frame(minHeight: 44).accessibilityIdentifier("articles-clear-recent") }
            }.padding(.top, 12)
        }.careCard().accessibilityIdentifier("articles-recent")
    }
}
