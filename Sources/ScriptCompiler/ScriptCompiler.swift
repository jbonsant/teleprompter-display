import Foundation
import Markdown
import TeleprompterDomain

public struct ScriptCompiler: Sendable {
    public init() {}

    public func compile(markdown: String, source: String) -> PresentationBundle {
        _ = Document(parsing: markdown)
        return PresentationBundle.stub(source: source, rawScript: markdown)
    }
}
