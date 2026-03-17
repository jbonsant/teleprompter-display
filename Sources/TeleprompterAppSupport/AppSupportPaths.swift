import Foundation

public enum AppSupportPaths {
    public static var applicationSupportDirectory: URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: fileManager.currentDirectoryPath)
        return base.appendingPathComponent("TeleprompterDisplay", isDirectory: true)
    }

    public static var bundleCacheDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("BundleCache", isDirectory: true)
    }

    public static var modelsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Models", isDirectory: true)
    }

    public static var logsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Logs", isDirectory: true)
    }

    public static var reportsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Reports", isDirectory: true)
    }

    @discardableResult
    public static func ensureDirectoriesExist() throws -> URL {
        let fileManager = FileManager.default
        for directory in [applicationSupportDirectory, bundleCacheDirectory, modelsDirectory, logsDirectory, reportsDirectory] {
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }
        return applicationSupportDirectory
    }
}
