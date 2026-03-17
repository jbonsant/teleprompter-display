import Foundation
import XCTest
@testable import ScriptCompiler
@testable import TeleprompterDomain

final class ScriptCompilerTests: XCTestCase {
    private let generatedAt = Date(timeIntervalSince1970: 1_700_000_000)

    func testPresentationScriptMatchesGoldenFixture() throws {
        try assertCompiledBundleMatchesFixture(
            sourceFileName: "presentation-script.md",
            fixtureFileName: "script-compiler-presentation.json"
        )
    }

    func testPresentationScriptOpusMatchesGoldenFixture() throws {
        try assertCompiledBundleMatchesFixture(
            sourceFileName: "presentation-script-opus.md",
            fixtureFileName: "script-compiler-presentation-opus.json"
        )
    }

    func testCompilerGeneratesStableIDsAndQuestionBookmarks() throws {
        let markdown = """
        ## Ouverture

        Merci de nous recevoir.

        [MONTRER: demo-slide]

        - Le GPSN commence par le métier notarial
        - L'alignement suit le texte confirmé

        #### Q1. Pourquoi garder le projet local?

        - Parce que l'outil doit fonctionner hors ligne
        - Parce que le contrôle manuel reste prioritaire
        """

        let compiler = ScriptCompiler()
        let firstBundle = compiler.compile(markdown: markdown, source: "inline-test.md", generatedAt: generatedAt)
        let secondBundle = compiler.compile(markdown: markdown, source: "inline-test.md", generatedAt: generatedAt)

        XCTAssertEqual(firstBundle, secondBundle)
        XCTAssertEqual(firstBundle.sections.count, 1)
        XCTAssertEqual(firstBundle.slideMarkers.count, 1)
        XCTAssertEqual(firstBundle.bookmarks.count, 2)
        XCTAssertEqual(firstBundle.bookmarks.last?.title, "Q1. Pourquoi garder le projet local?")
        XCTAssertTrue(firstBundle.anchorPhrases.count >= firstBundle.spokenSegments.count * 2)
        XCTAssertEqual(Set(firstBundle.spokenSegments.map { $0.id }).count, firstBundle.spokenSegments.count)
    }
}

private extension ScriptCompilerTests {
    var repoRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    var referencesURL: URL {
        repoRootURL.appendingPathComponent("references", isDirectory: true)
    }

    var fixturesURL: URL {
        repoRootURL.appendingPathComponent("Tests/Fixtures", isDirectory: true)
    }

    var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    var shouldUpdateFixtures: Bool {
        ProcessInfo.processInfo.environment["UPDATE_SCRIPT_COMPILER_FIXTURES"] == "1"
    }

    func assertCompiledBundleMatchesFixture(sourceFileName: String, fixtureFileName: String) throws {
        let markdownURL = referencesURL.appendingPathComponent(sourceFileName)
        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
        let bundle = ScriptCompiler().compile(
            markdown: markdown,
            source: sourceFileName,
            generatedAt: generatedAt
        )
        let actualData = try encoder.encode(bundle)
        let fixtureURL = fixturesURL.appendingPathComponent(fixtureFileName)

        if shouldUpdateFixtures {
            try FileManager.default.createDirectory(at: fixturesURL, withIntermediateDirectories: true)
            try actualData.write(to: fixtureURL)
        }

        let expectedData = try Data(contentsOf: fixtureURL)
        let expectedBundle = try decoder.decode(PresentationBundle.self, from: expectedData)
        let actualBundle = try decoder.decode(PresentationBundle.self, from: actualData)

        XCTAssertEqual(actualBundle, expectedBundle)
        XCTAssertEqual(String(decoding: actualData, as: UTF8.self), String(decoding: expectedData, as: UTF8.self))
        XCTAssertFalse(actualBundle.slideMarkers.isEmpty)
        XCTAssertFalse(actualBundle.bookmarks.isEmpty)
        XCTAssertFalse(actualBundle.anchorPhrases.isEmpty)
    }
}
