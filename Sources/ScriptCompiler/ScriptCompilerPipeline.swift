import CryptoKit
import Foundation
import Markdown
import NaturalLanguage
import TeleprompterDomain

struct ScriptCompilerPipeline {
    let source: String
    let markdown: String
    let generatedAt: Date
    let compilerVersion: String

    func compile() -> PresentationBundle {
        let preprocessed = Preprocessor.preprocess(markdown)
        let document = Document(parsing: preprocessed.sanitizedMarkdown)
        var collector = MarkdownEventCollector(slideTokens: Set(preprocessed.slideDirectives.map(\.token)))
        collector.visit(document)

        let builder = BundleBuilder(
            source: source,
            rawMarkdown: markdown,
            generatedAt: generatedAt,
            compilerVersion: compilerVersion,
            events: collector.events,
            slideDirectives: preprocessed.slideDirectives
        )
        return builder.build()
    }
}

private struct Preprocessor {
    struct SlideDirective {
        let index: Int
        let label: String
        let token: String
    }

    struct Result {
        let sanitizedMarkdown: String
        let slideDirectives: [SlideDirective]
    }

    static func preprocess(_ markdown: String) -> Result {
        let pattern = #"\[\s*MONTRER\s*:\s*([^\]]+)\]"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let matches = regex?.matches(
            in: markdown,
            range: NSRange(location: 0, length: markdown.utf16.count)
        ) ?? []

        var directives: [SlideDirective] = []
        var sanitized = markdown

        for (offset, match) in matches.enumerated().reversed() {
            let index = offset + 1
            let token = "SLIDE_MARKER_TOKEN_\(index)"
            let labelRange = Range(match.range(at: 1), in: markdown)!
            let label = markdown[labelRange].trimmingCharacters(in: .whitespacesAndNewlines)
            let fullRange = Range(match.range(at: 0), in: sanitized)!
            sanitized.replaceSubrange(fullRange, with: token)
            directives.insert(SlideDirective(index: index, label: label, token: token), at: 0)
        }

        return Result(sanitizedMarkdown: sanitized, slideDirectives: directives)
    }
}

private enum MarkdownEvent {
    case heading(level: Int, title: String)
    case paragraph(String)
    case list([String])
    case blockQuote(String)
    case thematicBreak
}

private struct MarkdownEventCollector: MarkupWalker {
    let slideTokens: Set<String>
    var events: [MarkdownEvent] = []

    mutating func visitDocument(_ document: Document) {
        descendInto(document)
    }

    mutating func visitHeading(_ heading: Heading) {
        let title = normalizeWhitespace(heading.plainText)
        guard !title.isEmpty else { return }
        events.append(.heading(level: heading.level, title: title))
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        let text = normalizeWhitespace(paragraph.plainText)
        guard !text.isEmpty else { return }
        events.append(.paragraph(text))
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        let items = listItems(from: unorderedList)
        guard !items.isEmpty else { return }
        events.append(.list(items))
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) {
        let items = listItems(from: orderedList)
        guard !items.isEmpty else { return }
        events.append(.list(items))
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        let text = normalizeWhitespace(recursivePlainText(from: blockQuote))
        guard !text.isEmpty else { return }
        events.append(.blockQuote(text))
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        events.append(.thematicBreak)
    }

    mutating func visitListItem(_ listItem: ListItem) {
        _ = listItem
    }

    private func listItems(from markup: Markup) -> [String] {
        markup.children.compactMap { child in
            guard let listItem = child as? ListItem else { return nil }
            let text = normalizeWhitespace(recursivePlainText(from: listItem))
            return text.isEmpty ? nil : text
        }
    }

    private func recursivePlainText(from markup: Markup) -> String {
        if let plain = markup as? any PlainTextConvertibleMarkup {
            return plain.plainText
        }

        return markup.children
            .map(recursivePlainText)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private struct BundleBuilder {
    struct SectionState {
        let id: String
        let title: String
        var segmentIDs: [String] = []
    }

    struct PendingBookmark {
        let id: String
        let title: String
        let sectionID: String
    }

    struct HeadingContext {
        let level: Int
        let title: String
    }

    struct SegmentPayload {
        let displayText: String
        let spokenText: String
    }

    enum Classification {
        case spoken(SegmentPayload)
        case nonSpoken
    }

    let source: String
    let rawMarkdown: String
    let generatedAt: Date
    let compilerVersion: String
    let events: [MarkdownEvent]
    let slideDirectives: [Preprocessor.SlideDirective]

    func build() -> PresentationBundle {
        let sourceHash = PresentationBundle.hash(rawMarkdown)
        let directiveByToken = Dictionary(uniqueKeysWithValues: slideDirectives.map { ($0.token, $0) })

        var sections: [PresentationSection] = []
        var displayBlocks: [DisplayBlock] = []
        var spokenSegments: [SpokenSegment] = []
        var slideMarkers: [SlideMarker] = []
        var bookmarks: [Bookmark] = []
        var anchorPhrases: [AnchorPhrase] = []

        var currentSection: SectionState?
        var headingPath: [HeadingContext] = []
        var pendingBookmarks: [PendingBookmark] = []
        var pendingSlideDirectives: [Preprocessor.SlideDirective] = []

        func finalizeSection() {
            guard let currentSection else { return }
            sections.append(
                PresentationSection(
                    id: currentSection.id,
                    title: currentSection.title,
                    segmentIDs: currentSection.segmentIDs
                )
            )
        }

        func updateHeadingPath(level: Int, title: String) {
            headingPath.removeAll { $0.level >= level }
            headingPath.append(HeadingContext(level: level, title: title))
        }

        func appendSegment(_ payload: SegmentPayload) {
            guard var sectionState = currentSection else { return }

            let scope = headingPath.map(\.title).joined(separator: "|")
            let segmentID = stableID(prefix: "segment", components: [source, sectionState.id, scope, payload.spokenText])
            let displayID = stableID(prefix: "display", components: [source, sectionState.id, scope, payload.displayText])

            spokenSegments.append(
                SpokenSegment(
                    id: segmentID,
                    text: payload.spokenText,
                    sectionID: sectionState.id
                )
            )
            displayBlocks.append(
                DisplayBlock(
                    id: displayID,
                    text: payload.displayText,
                    segmentID: segmentID,
                    sectionID: sectionState.id
                )
            )

            sectionState.segmentIDs.append(segmentID)
            currentSection = sectionState

            while let pendingBookmark = pendingBookmarks.first {
                bookmarks.append(
                    Bookmark(
                        id: pendingBookmark.id,
                        title: pendingBookmark.title,
                        targetSegmentID: segmentID,
                        sectionID: pendingBookmark.sectionID
                    )
                )
                pendingBookmarks.removeFirst()
            }

            while let directive = pendingSlideDirectives.first {
                slideMarkers.append(
                    SlideMarker(
                        id: stableID(
                            prefix: "slide",
                            components: [source, String(directive.index), directive.label, segmentID]
                        ),
                        index: directive.index,
                        targetSegmentID: segmentID,
                        sectionID: sectionState.id,
                        label: "SLIDE"
                    )
                )
                pendingSlideDirectives.removeFirst()
            }

            for phrase in AnchorPhraseExtractor().extract(from: payload.spokenText) {
                anchorPhrases.append(
                    AnchorPhrase(
                        id: stableID(prefix: "anchor", components: [segmentID, phrase]),
                        segmentID: segmentID,
                        sectionID: sectionState.id,
                        text: phrase
                    )
                )
            }
        }

        for event in events {
            switch event {
            case let .heading(level, title):
                updateHeadingPath(level: level, title: title)

                if level == 2 {
                    finalizeSection()
                    currentSection = SectionState(
                        id: stableID(prefix: "section", components: [source, title]),
                        title: title
                    )
                    if let currentSection {
                        pendingBookmarks.append(
                            PendingBookmark(
                                id: stableID(prefix: "bookmark", components: [source, "section", title]),
                                title: title,
                                sectionID: currentSection.id
                            )
                        )
                    }
                    continue
                }

                if let currentSection, isQuestionHeading(title) {
                    pendingBookmarks.append(
                        PendingBookmark(
                            id: stableID(prefix: "bookmark", components: [source, "qa", currentSection.id, title]),
                            title: title,
                            sectionID: currentSection.id
                        )
                    )
                }

            case let .paragraph(text):
                if let directive = directiveByToken[text] {
                    pendingSlideDirectives.append(directive)
                    continue
                }

                switch classify(text: text, currentSectionTitle: currentSection?.title, headingPath: headingPath) {
                case let .spoken(payload):
                    appendSegment(payload)
                case .nonSpoken:
                    continue
                }

            case let .list(items):
                for chunk in chunkListItems(items) {
                    switch classify(text: chunk, currentSectionTitle: currentSection?.title, headingPath: headingPath) {
                    case let .spoken(payload):
                        appendSegment(payload)
                    case .nonSpoken:
                        continue
                    }
                }

            case .blockQuote, .thematicBreak:
                continue
            }
        }

        finalizeSection()

        return PresentationBundle(
            bundleID: stableUUID(from: [source, sourceHash, compilerVersion]),
            compilerVersion: compilerVersion,
            sourceHash: sourceHash,
            generatedAt: generatedAt,
            sections: sections,
            displayBlocks: displayBlocks,
            spokenSegments: spokenSegments,
            slideMarkers: slideMarkers,
            bookmarks: bookmarks,
            anchorPhrases: anchorPhrases
        )
    }

    private func classify(text: String, currentSectionTitle: String?, headingPath: [HeadingContext]) -> Classification {
        let normalized = normalizeWhitespace(text)
        guard !normalized.isEmpty else { return .nonSpoken }

        let lowercasedText = normalized.lowercased()
        let headingTrail = headingPath.map { $0.title.lowercased() }.joined(separator: " / ")
        let sectionTitle = currentSectionTitle?.lowercased() ?? ""

        if sectionTitle.contains("notes présentateur")
            || headingTrail.contains("notes présentateur")
            || headingTrail.contains("notes pour la gestion des questions")
            || headingTrail.contains("notes de rythme")
            || headingTrail.contains("discipline cryptoguard")
            || headingTrail.contains("si les questions se calment")
        {
            return .nonSpoken
        }

        if lowercasedText.hasPrefix("[⏱")
            || lowercasedText.hasPrefix("si on doit couper")
            || lowercasedText.hasPrefix("phrase à dire")
        {
            return .nonSpoken
        }

        let displayText = normalized.replacingOccurrences(of: "`", with: "")
        let spokenText = normalizeWhitespace(displayText.replacingOccurrences(of: "—", with: " "))

        guard !displayText.isEmpty, !spokenText.isEmpty else {
            return .nonSpoken
        }

        return .spoken(SegmentPayload(displayText: displayText, spokenText: spokenText))
    }

    private func chunkListItems(_ items: [String]) -> [String] {
        var chunks: [String] = []
        var buffer: [String] = []
        var currentLength = 0

        func flush() {
            guard !buffer.isEmpty else { return }
            chunks.append(buffer.joined(separator: " "))
            buffer.removeAll(keepingCapacity: true)
            currentLength = 0
        }

        for item in items {
            let projectedLength = currentLength + item.count + (buffer.isEmpty ? 0 : 1)
            if !buffer.isEmpty && (buffer.count >= 3 || projectedLength > 220) {
                flush()
            }
            buffer.append(item)
            currentLength = projectedLength
        }

        flush()
        return chunks
    }
}

private struct AnchorPhraseExtractor: Sendable {
    private static let stopWords: Set<String> = [
        "a", "ai", "ainsi", "alors", "au", "aucun", "aussi", "autre", "avant", "avec",
        "avoir", "ce", "cela", "ces", "cet", "cette", "comme", "comment", "dans", "de",
        "des", "du", "elle", "elles", "en", "entre", "est", "et", "eux", "faire", "fait",
        "ici", "il", "ils", "je", "la", "le", "les", "leur", "leurs", "lui", "mais", "me",
        "meme", "merci", "moins", "mon", "ne", "nos", "notre", "nous", "on", "ou", "par",
        "pas", "plus", "pour", "pourquoi", "que", "quel", "quelle", "quelles", "quels",
        "qui", "sa", "sans", "se", "ses", "si", "son", "sur", "tes", "toi", "ton", "tous",
        "tout", "tres", "une", "vos", "votre", "vous", "y"
    ]

    func extract(from text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.setLanguage(.french)

        var filteredTokens: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = text[range]
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_CA"))
                .trimmingCharacters(in: .punctuationCharacters.union(.symbols))

            guard token.count > 2 else { return true }
            guard !Self.stopWords.contains(token) else { return true }
            filteredTokens.append(token)
            return true
        }

        struct Candidate {
            let text: String
            let score: Int
            let startIndex: Int
        }

        var candidates: [Candidate] = []
        for size in stride(from: 3, through: 2, by: -1) {
            guard filteredTokens.count >= size else { continue }

            for index in 0...(filteredTokens.count - size) {
                let slice = filteredTokens[index..<(index + size)]
                let phrase = slice.joined(separator: " ")
                let score = phrase.count + (Set(slice).count * 5)
                candidates.append(Candidate(text: phrase, score: score, startIndex: index))
            }
        }

        if candidates.isEmpty {
            return Array(filteredTokens.prefix(3))
        }

        var seen: Set<String> = []
        let ranked = candidates.sorted {
            if $0.score == $1.score {
                return $0.startIndex < $1.startIndex
            }
            return $0.score > $1.score
        }

        return ranked.compactMap { (candidate: Candidate) -> Candidate? in
            guard !seen.contains(candidate.text) else { return nil }
            seen.insert(candidate.text)
            return candidate
        }
        .prefix(3)
        .sorted { $0.startIndex < $1.startIndex }
        .map(\.text)
    }
}

private func isQuestionHeading(_ title: String) -> Bool {
    normalizeWhitespace(title).lowercased().hasPrefix("q")
}

private func stableID(prefix: String, components: [String]) -> String {
    let digest = SHA256.hash(data: Data(components.joined(separator: "|").utf8))
    let suffix = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    return "\(prefix)-\(suffix)"
}

private func stableUUID(from components: [String]) -> UUID {
    let digest = SHA256.hash(data: Data(components.joined(separator: "|").utf8))
    let bytes = Array(digest.prefix(16))
    return UUID(uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3],
        bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11],
        bytes[12], bytes[13], bytes[14], bytes[15]
    ))
}

private func normalizeWhitespace(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\u{00A0}", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
