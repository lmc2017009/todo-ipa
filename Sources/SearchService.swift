import Foundation

/// 联网检索（无需密钥）：DuckDuckGo 优先，Bing 兜底
struct SearchService {
    static let shared = SearchService()

    func search(query: String, limit: Int = 5) async -> [SearchSource] {
        if let results = await duck(query: query, limit: limit), !results.isEmpty {
            return results
        }
        if let results = await bing(query: query, limit: limit), !results.isEmpty {
            return results
        }
        return []
    }

    /// 把检索结果拼成给模型看的上下文
    static func contextBlock(for sources: [SearchSource]) -> String {
        var lines: [String] = ["以下是刚刚联网检索到的实时结果（回答时可引用编号）："]
        for (index, source) in sources.enumerated() {
            let snippet = source.snippet.isEmpty ? "（无摘要）" : source.snippet
            lines.append("[\(index + 1)] \(source.title)\n\(source.url)\n\(snippet)")
        }
        lines.append("请优先依据以上结果作答；如果结果不足或与问题无关，请说明后再补充你自己的知识。")
        return lines.joined(separator: "\n\n")
    }

    // MARK: - 引擎

    private func duck(query: String, limit: Int) async -> [SearchSource]? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
            return nil
        }

        guard let html = await fetch(url) else { return nil }

        let titles = matches("<a[^>]*class=\"result__a\"[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>", in: html)
        let snippets = matches("<a[^>]*class=\"result__snippet\"[^>]*>(.*?)</a>", in: html)

        var results: [SearchSource] = []
        for (index, item) in titles.enumerated() {
            guard index < limit else { break }
            guard item.count >= 2 else { continue }
            let link = decodeDuckLink(item[0])
            let title = Self.clean(item[1])
            guard !title.isEmpty, link.hasPrefix("http") else { continue }
            let snippet = index < snippets.count ? Self.clean(snippets[index][0]) : ""
            results.append(SearchSource(title: title, url: link, snippet: snippet))
        }
        return results
    }

    private func bing(query: String, limit: Int) async -> [SearchSource]? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.bing.com/search?q=\(encoded)&setlang=zh-CN") else {
            return nil
        }

        guard let html = await fetch(url) else { return nil }

        let blocks = matches("<li class=\"b_algo\".*?</li>", in: html)
        var results: [SearchSource] = []

        for block in blocks {
            guard results.count < limit else { break }
            let content = block[0]
            let link = matches("<h2>\\s*<a[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>", in: content)
            guard let first = link.first, first.count >= 2 else { continue }
            let title = Self.clean(first[1])
            guard !title.isEmpty, first[0].hasPrefix("http") else { continue }
            let snippetMatch = matches("<p[^>]*>(.*?)</p>", in: content)
            let snippet = snippetMatch.first.map { Self.clean($0[0]) } ?? ""
            results.append(SearchSource(title: title, url: first[0], snippet: snippet))
        }
        return results
    }

    private func fetch(_ url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200 else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                   options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return []
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.matches(in: text, range: range).map { match in
            (0..<match.numberOfRanges).map { index in
                let result = match.range(at: index)
                return result.location == NSNotFound ? "" : (text as NSString).substring(with: result)
            }
        }
    }

    private func decodeDuckLink(_ raw: String) -> String {
        guard let components = URLComponents(string: "https://duckduckgo.com" + (raw.hasPrefix("http") ? "" : raw)),
              let target = components.queryItems?.first(where: { $0.name == "uddg" })?.value,
              let decoded = target.removingPercentEncoding else {
            return raw.hasPrefix("http") ? raw : ""
        }
        return decoded
    }

    private static func clean(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
                        "&#39;": "'", "&#x27;": "'", "&nbsp;": " "]
        for (key, value) in entities {
            text = text.replacingOccurrences(of: key, with: value)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}