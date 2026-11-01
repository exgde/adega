import Foundation

/// Onde o Adega guarda tudo. Padrão: `~/Library/Application Support/Adega`.
/// A variável de ambiente `ADEGA_HOME` substitui a raiz (útil para testes).
public struct AdegaPaths: Sendable, Equatable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static var `default`: AdegaPaths {
        if let override = ProcessInfo.processInfo.environment["ADEGA_HOME"], !override.isEmpty {
            return AdegaPaths(root: URL(fileURLWithPath: override, isDirectory: true))
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return AdegaPaths(root: base.appendingPathComponent("Adega", isDirectory: true))
    }

    public var runtimes: URL { root.appendingPathComponent("Runtimes", isDirectory: true) }
    public var bottles: URL { root.appendingPathComponent("Bottles", isDirectory: true) }
    public var components: URL { root.appendingPathComponent("Components", isDirectory: true) }
    public var logs: URL { root.appendingPathComponent("Logs", isDirectory: true) }
    public var cache: URL { root.appendingPathComponent("Cache", isDirectory: true) }
    public var settingsFile: URL { root.appendingPathComponent("settings.json") }

    public func ensureDirectories(fileManager: FileManager = .default) throws {
        for dir in [root, runtimes, bottles, components, logs, cache] {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
