import Foundation
import Markdown
import TeleprompterDomain

public struct ScriptCompiler: Sendable {
    public static let compilerVersion = "0.3.0"

    public init() {}

    public func compile(markdown: String, source: String, generatedAt: Date = .now) -> PresentationBundle {
        let pipeline = ScriptCompilerPipeline(
            source: source,
            markdown: markdown,
            generatedAt: generatedAt,
            compilerVersion: Self.compilerVersion
        )
        return pipeline.compile()
    }
}
