import Foundation
import SpeechAlignment

@main
struct ASRBenchmarkMain {
    static func main() async {
        do {
            let options = try BenchmarkCLIOptions(arguments: CommandLine.arguments)
            try await BenchmarkRunner(options: options).run()
        } catch BenchmarkCLIError.helpRequested {
            print(BenchmarkCLIOptions.usage)
        } catch let error as BenchmarkCLIError {
            fputs("Error: \(error.localizedDescription)\n\n", stderr)
            fputs(BenchmarkCLIOptions.usage, stderr)
            Foundation.exit(EXIT_FAILURE)
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            Foundation.exit(EXIT_FAILURE)
        }
    }
}

private struct BenchmarkRunner {
    let options: BenchmarkCLIOptions

    func run() async throws {
        let service = RehearsalTranscriptionService(
            configuration: ASRConfiguration(),
            modelName: options.modelName,
            modelDirectory: options.modelDirectory
        )

        if options.downloadModel {
            _ = try await service.downloadModel()
        }

        let transcription = try await service.transcribe(
            audioFileAt: options.audioURL,
            allowDownload: false
        )

        let report = BenchmarkReport(
            modelName: transcription.modelName,
            modelDirectory: transcription.modelDirectory.path,
            chunkCount: transcription.chunks.count,
            characterCount: transcription.chunks.reduce(into: 0) { count, chunk in
                count += chunk.confirmedText.count
            },
            performance: transcription.performance
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        print(String(decoding: data, as: UTF8.self))
    }
}

private struct BenchmarkReport: Codable {
    let modelName: String
    let modelDirectory: String
    let chunkCount: Int
    let characterCount: Int
    let performance: ASRPerformanceMetrics
}

private struct BenchmarkCLIOptions {
    let audioURL: URL
    let modelName: String
    let modelDirectory: URL?
    let downloadModel: Bool

    static let usage = """
    Usage:
      swift run asr-benchmark --audio <path> --model <model-id> [options]

    Options:
      --audio <path>         Path to the benchmark audio file.
      --model <model-id>     WhisperKit model variant to benchmark.
      --model-dir <path>     Optional model cache directory.
      --download-model       Download/cache the model before benchmarking.
      --help                 Show this usage text.
    """

    init(arguments: [String]) throws {
        var audioURL: URL?
        var modelName: String?
        var modelDirectory: URL?
        var downloadModel = false

        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--audio":
                index += 1
                audioURL = URL(fileURLWithPath: try Self.value(after: argument, at: index, in: arguments))
            case "--model":
                index += 1
                modelName = try Self.value(after: argument, at: index, in: arguments)
            case "--model-dir":
                index += 1
                modelDirectory = URL(fileURLWithPath: try Self.value(after: argument, at: index, in: arguments))
            case "--download-model":
                downloadModel = true
            case "--help":
                throw BenchmarkCLIError.helpRequested
            default:
                throw BenchmarkCLIError.unknownOption(argument)
            }
            index += 1
        }

        guard let audioURL else {
            throw BenchmarkCLIError.missingRequiredOption("--audio")
        }

        guard let modelName, !modelName.isEmpty else {
            throw BenchmarkCLIError.missingRequiredOption("--model")
        }

        self.audioURL = audioURL
        self.modelName = modelName
        self.modelDirectory = modelDirectory
        self.downloadModel = downloadModel
    }

    private static func value(after option: String, at index: Int, in arguments: [String]) throws -> String {
        guard index < arguments.count else {
            throw BenchmarkCLIError.missingValue(option)
        }
        return arguments[index]
    }
}

private enum BenchmarkCLIError: LocalizedError {
    case helpRequested
    case missingRequiredOption(String)
    case missingValue(String)
    case unknownOption(String)

    var errorDescription: String? {
        switch self {
        case .helpRequested:
            return nil
        case let .missingRequiredOption(option):
            return "Missing required option \(option)."
        case let .missingValue(option):
            return "Missing value after \(option)."
        case let .unknownOption(option):
            return "Unknown option \(option)."
        }
    }
}
