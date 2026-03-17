import Foundation
import ScriptCompiler
import SpeechAlignment

@main
struct RehearsalHarnessMain {
    static func main() throws {
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let referencesDirectory = currentDirectory.appendingPathComponent("references")
        let scriptURL = referencesDirectory.appendingPathComponent("presentation-script.md")

        print("Teleprompter rehearsal harness scaffold")
        print("References: \(referencesDirectory.path)")
        print("Alignment bootstrap: \(SpeechAlignmentBootstrap.guidance)")

        if FileManager.default.fileExists(atPath: scriptURL.path) {
            let markdown = try String(contentsOf: scriptURL, encoding: .utf8)
            let bundle = ScriptCompiler().compile(markdown: markdown, source: scriptURL.lastPathComponent)
            print("Compiled stub bundle with \(bundle.sections.count) section(s) and \(bundle.slideMarkers.count) slide marker(s).")
        } else {
            print("No presentation script found yet. Add references/presentation-script.md before compiler work.")
        }
    }
}
