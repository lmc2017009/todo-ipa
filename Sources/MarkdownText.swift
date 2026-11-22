import SwiftUI

struct MarkdownText: View {
    let text: String

    private enum Block {
        case paragraph(String)
        case code(String, String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let content):
                    Text(Self.attributed(content))
                        .font(.body)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                case .code(let code, let language):
                    VStack(alignment: .leading, spacing: 6) {
                        if !language.isEmpty {
                            Text(language.uppercased())
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(code)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var buffer: [String] = []
        var codeLines: [String] = []
        var inCode = false
        var language = ""

        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCode {
                    result.append(.code(codeLines.joined(separator: "\n"), language))
                    codeLines = []
                    inCode = false
                    language = ""
                } else {
                    if !buffer.isEmpty {
                        result.append(.paragraph(buffer.joined(separator: "\n")))
                        buffer = []
                    }
                    inCode = true
                    language = line.trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: "```", with: "")
                }
                continue
            }

            if inCode {
                codeLines.append(line)
            } else {
                buffer.append(line)
            }
        }

        if !codeLines.isEmpty {
            result.append(.code(codeLines.joined(separator: "\n"), language))
        }
        if !buffer.isEmpty {
            result.append(.paragraph(buffer.joined(separator: "\n")))
        }
        return result
    }

    private static func attributed(_ string: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: string, options: options)) ?? AttributedString(string)
    }
}