import Foundation
import SwiftUI

struct LegalLinks: View {
    var body: some View {
        Section("アプリについて") {
            ForEach(LegalDocument.allCases, id: \.self) { document in
                if let url = document.publicURL {
                    Link(destination: url) {
                        Text(document.title).frame(minHeight: 44)
                    }
                } else {
                    NavigationLink {
                        BundledLegalPage(document: document)
                    } label: {
                        Text(document.title).frame(minHeight: 44)
                    }
                }
            }
        }
    }
}

private enum LegalDocument: String, CaseIterable {
    case privacy
    case terms

    var title: String {
        switch self {
        case .privacy: "プライバシーポリシー"
        case .terms: "利用規約"
        }
    }

    var publicURL: URL? {
        guard let base = Bundle.main.object(forInfoDictionaryKey: "LedgerLegalBaseURL") as? String,
              let url = URL(string: base), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, url.query == nil, url.fragment == nil else { return nil }
        return url.appendingPathComponent(rawValue).appendingPathExtension("html")
    }

    var bundledText: String? {
        guard let url = Bundle.main.url(forResource: rawValue, withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        // The bundled Markdown is also a Jekyll page. Hide its front matter.
        let parts = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "---\n")
        let body = parts.count >= 3 && parts[0].isEmpty ? parts.dropFirst(2).joined(separator: "---\n") : markdown
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct BundledLegalPage: View {
    let document: LegalDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let content = document.bundledText {
                    ForEach(Array(content.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, block in
                        let paragraph = block.trimmingCharacters(in: .whitespacesAndNewlines)
                        if paragraph.hasPrefix("## ") {
                            Text(String(paragraph.dropFirst(3)))
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                        } else if !paragraph.hasPrefix("# "), !paragraph.isEmpty {
                            let parsed = try? AttributedString(
                                markdown: paragraph,
                                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                            )
                            Text(parsed ?? AttributedString(paragraph))
                        }
                    }
                } else {
                    Text("文書を表示できません。App Store の「Appサポート」をご確認ください。")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
