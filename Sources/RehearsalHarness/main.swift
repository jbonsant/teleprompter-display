import Darwin
import Foundation
import SpeechAlignment
import TeleprompterDomain

@main
struct RehearsalHarnessMain {
    static func main() async {
        do {
            let options = try CLIOptions(arguments: CommandLine.arguments)
            try await RehearsalHarnessRunner(options: options).run()
        } catch CLIOptionsError.helpRequested {
            print(CLIOptions.usage)
            return
        } catch let error as CLIOptionsError {
            fputs("Error: \(error.localizedDescription)\n\n", stderr)
            fputs(CLIOptions.usage, stderr)
            Darwin.exit(1)
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            Darwin.exit(1)
        }
    }
}

private struct RehearsalHarnessRunner {
    let options: CLIOptions

    func run() async throws {
        let service = RehearsalTranscriptionService(
            configuration: ASRConfiguration(),
            modelName: options.modelName,
            modelDirectory: options.modelDirectory
        )

        if options.downloadModel {
            let modelPath = try await service.downloadModel()
            print("Downloaded model \(service.modelName) to \(modelPath.path)")

            if options.bundleURL == nil && options.audioURL == nil {
                return
            }
        }

        let bundleURL = try options.requireBundleURL()
        let audioURL = try options.requireAudioURL()
        let bundle = try loadBundle(from: bundleURL)
        let startedAt = Date()
        let transcription = try await service.transcribe(
            audioFileAt: audioURL,
            allowDownload: !options.downloadModel
        )

        var sessionLog = SessionLog(startedAt: startedAt)
        var aligner = ForwardAligner(bundle: bundle)

        print("Bundle: \(bundleURL.path)")
        print("Audio: \(audioURL.path)")
        print("Model: \(transcription.modelName)")
        print("Replay speed: \(options.speed.rawValue)")
        print("Frames:")

        var previousChunk: ASROutput?
        for chunk in transcription.chunks {
            if let previousChunk {
                let replayDelay = max(0.0, chunk.audioStartSeconds - previousChunk.audioStartSeconds) / options.speed.multiplier
                if replayDelay > 0 {
                    try await Task.sleep(for: .seconds(replayDelay))
                }
            }

            let update = aligner.ingestConfirmedChunk(chunk)
            let timestampLabel = formatTimestamp(chunk.audioEndSeconds)
            let positionLabel = bundle.spokenSegments.isEmpty
                ? "0/0"
                : "\(update.segmentIndex + 1)/\(bundle.spokenSegments.count)"
            let segmentLabel = update.segmentID ?? "n/a"
            let candidateSummary = update.frame.candidateScores
                .map { "\($0.segmentID)=\(String(format: "%.2f", $0.score))" }
                .joined(separator: ", ")
            print("[\(timestampLabel)] segment \(positionLabel) \(segmentLabel) conf \(String(format: "%.2f", update.confidence)) | \(chunk.confirmedText)")
            if !candidateSummary.isEmpty {
                print("  candidates: \(candidateSummary)")
            }

            sessionLog.append(
                DiagnosticEvent(
                    timestamp: Date(),
                    eventType: .asrChunk,
                    payload: [
                        "audioTimestamp": timestampLabel,
                        "confirmedText": chunk.confirmedText,
                        "segmentIndex": String(update.segmentIndex),
                        "segmentID": segmentLabel,
                        "confidence": String(format: "%.2f", update.confidence),
                    ]
                )
            )
            previousChunk = chunk
        }

        let elapsedTime = Date().timeIntervalSince(startedAt)
        let finalSegmentIndex = aligner.currentSegmentIndex
        let finalSegmentID = aligner.currentSegmentID
        let segmentsTraversed = bundle.spokenSegments.isEmpty ? 0 : finalSegmentIndex + 1
        sessionLog.append(
            DiagnosticEvent(
                timestamp: Date(),
                eventType: .stateTransition,
                payload: [
                    "segmentsTraversed": String(segmentsTraversed),
                    "finalSegmentIndex": String(finalSegmentIndex),
                    "finalSegmentID": finalSegmentID ?? "n/a",
                    "elapsedSeconds": String(format: "%.2f", elapsedTime),
                ]
            )
        )

        let eventLogURL = options.eventLogURL ?? defaultEventLogURL(for: bundleURL)
        try writeEventLog(sessionLog, to: eventLogURL)

        print("")
        print("Summary:")
        print("- segments traversed: \(segmentsTraversed)")
        let finalPositionLabel = bundle.spokenSegments.isEmpty
            ? "0/0"
            : "\(finalSegmentIndex + 1)/\(bundle.spokenSegments.count)"
        print("- final position: \(finalPositionLabel) \(finalSegmentID ?? "n/a")")
        print(String(format: "- elapsed time: %.2fs", elapsedTime))
        print("- event log: \(eventLogURL.path)")
        print("- model cache: \(transcription.modelDirectory.path)")
    }

    private func loadBundle(from url: URL) throws -> PresentationBundle {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PresentationBundle.self, from: data)
    }

    private func writeEventLog(_ log: SessionLog, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(log)
        try data.write(to: url, options: .atomic)
    }

    private func defaultEventLogURL(for bundleURL: URL) -> URL {
        let fileName = bundleURL.deletingPathExtension().lastPathComponent + "-rehearsal-log.json"
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(fileName)
    }

    private func formatTimestamp(_ timestamp: TimeInterval) -> String {
        let minutes = Int(timestamp / 60)
        let seconds = timestamp.truncatingRemainder(dividingBy: 60)
        return String(format: "%02d:%05.2f", minutes, seconds)
    }
}

private struct CLIOptions {
    let bundleURL: URL?
    let audioURL: URL?
    let speed: ReplaySpeed
    let eventLogURL: URL?
    let modelName: String?
    let modelDirectory: URL?
    let downloadModel: Bool

    static let usage = """
    Usage:
      swift run teleprompter-rehearsal --bundle <bundle.json> --audio <audio-file> [options]
      swift run teleprompter-rehearsal --download-model [--model <model-name>] [--model-dir <path>]

    Options:
      --bundle <path>        Path to a PresentationBundle JSON file.
      --audio <path>         Path to an audio file for rehearsal.
      --speed <1x|2x|4x>     Replay speed for frame emission. Default: 1x.
      --event-log <path>     Path for JSON SessionLog output.
      --model <name>         WhisperKit model variant. Default: recommended model.
      --model-dir <path>     Directory for downloaded/cached WhisperKit models.
      --download-model       Download/cache the model before running. If used alone, exits after download.
      --help                 Show this usage text.
    """

    init(arguments: [String]) throws {
        var bundleURL: URL?
        var audioURL: URL?
        var speed: ReplaySpeed = .realtime
        var eventLogURL: URL?
        var modelName: String?
        var modelDirectory: URL?
        var downloadModel = false

        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--bundle":
                index += 1
                bundleURL = URL(fileURLWithPath: try Self.value(after: argument, at: index, in: arguments))
            case "--audio":
                index += 1
                audioURL = URL(fileURLWithPath: try Self.value(after: argument, at: index, in: arguments))
            case "--speed":
                index += 1
                speed = try ReplaySpeed(argument: try Self.value(after: argument, at: index, in: arguments))
            case "--event-log":
                index += 1
                eventLogURL = URL(fileURLWithPath: try Self.value(after: argument, at: index, in: arguments))
            case "--model":
                index += 1
                modelName = try Self.value(after: argument, at: index, in: arguments)
            case "--model-dir":
                index += 1
                modelDirectory = URL(fileURLWithPath: try Self.value(after: argument, at: index, in: arguments))
            case "--download-model":
                downloadModel = true
            case "--help", "-h":
                throw CLIOptionsError.helpRequested
            default:
                throw CLIOptionsError.invalidOption(argument)
            }
            index += 1
        }

        self.bundleURL = bundleURL
        self.audioURL = audioURL
        self.speed = speed
        self.eventLogURL = eventLogURL
        self.modelName = modelName
        self.modelDirectory = modelDirectory
        self.downloadModel = downloadModel
    }

    func requireBundleURL() throws -> URL {
        guard let bundleURL else {
            throw CLIOptionsError.missingRequiredOption("--bundle")
        }
        guard FileManager.default.fileExists(atPath: bundleURL.path) else {
            throw CLIOptionsError.missingFile(bundleURL.path)
        }
        return bundleURL
    }

    func requireAudioURL() throws -> URL {
        guard let audioURL else {
            throw CLIOptionsError.missingRequiredOption("--audio")
        }
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw CLIOptionsError.missingFile(audioURL.path)
        }
        return audioURL
    }

    private static func value(after option: String, at index: Int, in arguments: [String]) throws -> String {
        guard index < arguments.count else {
            throw CLIOptionsError.missingValue(option)
        }
        return arguments[index]
    }
}

private enum ReplaySpeed: String {
    case realtime = "1x"
    case double = "2x"
    case quadruple = "4x"

    var multiplier: Double {
        switch self {
        case .realtime:
            1
        case .double:
            2
        case .quadruple:
            4
        }
    }

    init(argument: String) throws {
        switch argument.lowercased() {
        case "1", "1x":
            self = .realtime
        case "2", "2x":
            self = .double
        case "4", "4x":
            self = .quadruple
        default:
            throw CLIOptionsError.invalidSpeed(argument)
        }
    }
}

private enum CLIOptionsError: LocalizedError {
    case helpRequested
    case invalidOption(String)
    case invalidSpeed(String)
    case missingRequiredOption(String)
    case missingValue(String)
    case missingFile(String)

    var errorDescription: String? {
        switch self {
        case .helpRequested:
            return CLIOptions.usage
        case .invalidOption(let option):
            return "Unknown option \(option)."
        case .invalidSpeed(let speed):
            return "Unsupported speed \(speed). Use 1x, 2x, or 4x."
        case .missingRequiredOption(let option):
            return "Missing required option \(option)."
        case .missingValue(let option):
            return "Missing value for \(option)."
        case .missingFile(let path):
            return "File not found at \(path)."
        }
    }
}
