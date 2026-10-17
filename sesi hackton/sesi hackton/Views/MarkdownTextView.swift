//
//  MarkdownTextView.swift
//  sesi hackton
//
//  Created by Claude on 17/10/26.
//

import SwiftUI

/// Renderer Markdown dengan komponen native SwiftUI.
/// Mendukung heading (#–######), bullet (-, *, +, •), list bernomor, kutipan (>),
/// garis pemisah (---), blok kode (```), serta format inline (**bold**, *italic*, `code`, link).
struct MarkdownTextView: View {
    private let blocks: [MarkdownBlock]

    init(_ markdown: String) {
        self.blocks = MarkdownBlock.parse(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(Self.inline(text))
                .font(Self.headingFont(for: level))
                .padding(.top, level <= 3 ? 6 : 2)
                .accessibilityAddTraits(.isHeader)

        case .paragraph(let text):
            Text(Self.inline(text))
                .font(.body)
                .lineSpacing(3)

        case .bullet(let level, let text):
            listRow(marker: Text("•").fontWeight(.bold), level: level, text: text)

        case .numbered(let level, let number, let text):
            listRow(marker: Text("\(number).").monospacedDigit(), level: level, text: text)

        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.tint)
                    .frame(width: 3)
                Text(Self.inline(text))
                    .italic()
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .divider:
            Divider()
                .padding(.vertical, 4)

        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(Color(uiColor: .tertiarySystemFill), in: .rect(cornerRadius: 8))
        }
    }

    private func listRow(marker: Text, level: Int, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            marker
                .foregroundStyle(.secondary)
                .frame(minWidth: 14, alignment: .leading)
            Text(Self.inline(text))
                .font(.body)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(level) * 16)
    }

    private static func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return .title2.bold()
        case 2: return .title3.bold()
        case 3: return .headline
        default: return .subheadline.weight(.semibold)
        }
    }

    /// Format inline (**bold**, *italic*, `code`, link) via parser Markdown bawaan Foundation
    private static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )) ?? AttributedString(text)
    }
}

// MARK: - Parser Blok Markdown

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(level: Int, text: String)
    case numbered(level: Int, number: String, text: String)
    case quote(String)
    case divider
    case code(String)

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []
        var codeLines: [String]?

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(.paragraph(paragraphLines.joined(separator: " ")))
            paragraphLines.removeAll()
        }

        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            // Blok kode ``` ... ```
            if trimmed.hasPrefix("```") {
                if let collected = codeLines {
                    blocks.append(.code(collected.joined(separator: "\n")))
                    codeLines = nil
                } else {
                    flushParagraph()
                    codeLines = []
                }
                continue
            }
            if codeLines != nil {
                codeLines?.append(rawLine)
                continue
            }

            // Baris kosong = akhir paragraf
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            // Tiap 2 spasi (atau 1 tab) di awal baris = 1 level indentasi list
            let leadingWidth = rawLine.prefix { $0 == " " || $0 == "\t" }
                .reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            let indentLevel = min(leadingWidth / 2, 3)

            if let heading = parseHeading(trimmed) {
                flushParagraph()
                blocks.append(heading)
            } else if isDivider(trimmed) {
                // Dicek sebelum bullet supaya "* * *" / "---" tidak terbaca sebagai list
                flushParagraph()
                blocks.append(.divider)
            } else if trimmed.hasPrefix(">") {
                flushParagraph()
                blocks.append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else if let text = parseBullet(trimmed) {
                flushParagraph()
                blocks.append(.bullet(level: indentLevel, text: text))
            } else if let (number, text) = parseNumbered(trimmed) {
                flushParagraph()
                blocks.append(.numbered(level: indentLevel, number: number, text: text))
            } else {
                paragraphLines.append(trimmed)
            }
        }

        // Blok kode yang tidak ditutup tetap ditampilkan
        if let collected = codeLines {
            blocks.append(.code(collected.joined(separator: "\n")))
        }
        flushParagraph()
        return blocks
    }

    private static func parseHeading(_ line: String) -> MarkdownBlock? {
        let hashCount = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashCount) else { return nil }
        let rest = line.dropFirst(hashCount)
        guard rest.first == " " else { return nil }  // "#tag" bukan heading
        let text = rest
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))  // heading gaya "## Judul ##"
            .trimmingCharacters(in: .whitespaces)
        return .heading(level: hashCount, text: text)
    }

    private static func isDivider(_ line: String) -> Bool {
        let compact = line.filter { $0 != " " }
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func parseBullet(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func parseNumbered(_ line: String) -> (String, String)? {
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard let separator = rest.first, separator == "." || separator == ")" else { return nil }
        let afterSeparator = rest.dropFirst()
        guard afterSeparator.first == " " else { return nil }
        return (String(digits), afterSeparator.trimmingCharacters(in: .whitespaces))
    }
}

#Preview {
    ScrollView {
        MarkdownTextView("""
            ### Analisis Pola Hidup

            Jerawat berkaitan dengan **lonjakan insulin** dan *peradangan*.

            ---

            #### 1. Protokol Nutrisi
            * **Sayuran Hijau:** Bayam, brokoli, dan `pakcoy`.
              - Rebus atau kukus, jangan digoreng.
            * **Buah Rendah Glikemik:** Pepaya dan apel.

            1. Minum air 2.5 liter
            2. Tidur sebelum 22:00

            > Konsisten 2 minggu untuk melihat hasil.
            """)
        .padding()
    }
}
