import Foundation

/// Inicia programas numa bottle, com um arquivo de log por execução em `Logs/<bottle>/`.
public final class Launcher: @unchecked Sendable {
    public let paths: AdegaPaths
    let runner: ProcessRunning

    public init(paths: AdegaPaths, runner: ProcessRunning = SystemProcessRunner()) {
        self.paths = paths
        self.runner = runner
    }

    public func logDirectory(for bottle: Bottle) -> URL {
        paths.logs.appendingPathComponent(bottle.id, isDirectory: true)
    }

    public func launch(program: URL, arguments: [String] = [], in bottle: Bottle, runtime: InstalledRuntime, onExit: (@Sendable (Int32) -> Void)? = nil) throws -> SpawnedProcess {
        let wine = Wine(runtime: runtime, runner: runner)
        let logURL = makeLogURL(for: program, bottle: bottle)
        try writeHeader(to: logURL, program: program, arguments: arguments, bottle: bottle, runtime: runtime, environment: wine.environment(for: bottle))
        return try wine.launch(program: program, arguments: arguments, in: bottle, logFile: logURL, onExit: onExit)
    }

    public func logFiles(for bottle: Bottle) -> [URL] {
        let dir = logDirectory(for: bottle)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        // Nomes começam com timestamp ordenável → ordem decrescente = mais recente primeiro.
        return files.filter { $0.pathExtension == "log" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    public func readLog(_ url: URL, maxBytes: Int = 256 * 1024) -> String {
        FileOps.readTail(of: url, maxBytes: maxBytes)
    }

    func makeLogURL(for program: URL, bottle: Bottle) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let name = (try? NameSanitizer.identifier(from: program.deletingPathExtension().lastPathComponent)) ?? "programa"
        return logDirectory(for: bottle).appendingPathComponent("\(stamp)-\(name).log")
    }

    private func writeHeader(to url: URL, program: URL, arguments: [String], bottle: Bottle, runtime: InstalledRuntime, environment: [String: String]) throws {
        let interesting = environment
            .filter { $0.key.hasPrefix("WINE") || $0.key.hasPrefix("DXVK") || $0.key.hasPrefix("MTL_") || $0.key.hasPrefix("ROSETTA") }
            .sorted { $0.key < $1.key }
            .map { "  \($0.key)=\($0.value)" }
            .joined(separator: "\n")
        let header = """
        === Adega — \(ISO8601DateFormatter().string(from: Date())) ===
        Programa: \(program.path) \(arguments.joined(separator: " "))
        Bottle:   \(bottle.config.displayName) (\(bottle.url.path))
        Runtime:  \(runtime.displayName) [\(runtime.version)] — \(runtime.wineRootPath)
        Backend:  \(bottle.config.graphicsBackend.displayName)
        Ambiente:
        \(interesting)
        =====================================================

        """
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(header.utf8).write(to: url)
    }
}

/// Execução "sem interface" usada pelos atalhos .app gerados:
/// `<executável> --adega-run --bottle <id> -- <programa> [args...]`
public enum HeadlessLaunch {
    public static let flag = "--adega-run"

    public struct Request: Equatable, Sendable {
        public var bottleID: String
        public var program: String
        public var arguments: [String]

        public init(bottleID: String, program: String, arguments: [String] = []) {
            self.bottleID = bottleID
            self.program = program
            self.arguments = arguments
        }
    }

    /// `arguments` sem o argv[0].
    public static func parse(_ arguments: [String]) -> Request? {
        guard let flagIndex = arguments.firstIndex(of: flag) else { return nil }
        var rest = Array(arguments[(flagIndex + 1)...])
        var bottleID: String?
        while let first = rest.first, first != "--", first.hasPrefix("--") {
            rest.removeFirst()
            if first == "--bottle", let value = rest.first {
                bottleID = value
                rest.removeFirst()
            }
        }
        if rest.first == "--" { rest.removeFirst() }
        guard let bottleID, let program = rest.first else { return nil }
        return Request(bottleID: bottleID, program: program, arguments: Array(rest.dropFirst()))
    }

    public static func arguments(for request: Request) -> [String] {
        [flag, "--bottle", request.bottleID, "--", request.program] + request.arguments
    }

    public static func perform(_ request: Request, paths: AdegaPaths = .default, runner: ProcessRunning = SystemProcessRunner()) throws -> SpawnedProcess {
        let bottle = try BottleManager(paths: paths, runner: runner).bottle(id: request.bottleID)
        let runtime = try RuntimeManager(paths: paths, runner: runner).runtime(id: bottle.config.runtimeID)
        return try Launcher(paths: paths, runner: runner).launch(
            program: URL(fileURLWithPath: request.program),
            arguments: request.arguments,
            in: bottle,
            runtime: runtime
        )
    }
}
