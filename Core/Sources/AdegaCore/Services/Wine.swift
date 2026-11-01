import Foundation

/// Operações do Wine sobre uma bottle, usando um runtime específico.
public struct Wine: Sendable {
    public let runtime: InstalledRuntime
    public let runner: ProcessRunning
    public var baseEnvironment: [String: String]

    public init(runtime: InstalledRuntime, runner: ProcessRunning, baseEnvironment: [String: String] = ProcessInfo.processInfo.environment) {
        self.runtime = runtime
        self.runner = runner
        self.baseEnvironment = baseEnvironment
    }

    public func environment(for bottle: Bottle, extra: [String: String] = [:]) -> [String: String] {
        var env = WineEnvironment.build(config: bottle.config, bottleURL: bottle.url, runtime: runtime, base: baseEnvironment)
        env.merge(extra) { _, new in new }
        return env
    }

    /// `wine <args>` esperando terminar. Não lança erro se o código de saída for != 0.
    public func run(_ arguments: [String], in bottle: Bottle, extraEnvironment: [String: String] = [:]) async throws -> ProcessResult {
        try await runner.run(
            executable: try runtime.wineBinary(),
            arguments: arguments,
            environment: environment(for: bottle, extra: extraEnvironment),
            currentDirectory: bottle.url
        )
    }

    @discardableResult
    public func runChecked(_ arguments: [String], in bottle: Bottle) async throws -> ProcessResult {
        try await runner.runChecked(
            executable: try runtime.wineBinary(),
            arguments: arguments,
            environment: environment(for: bottle),
            currentDirectory: bottle.url
        )
    }

    /// Cria/atualiza o prefixo (drive_c, registro, DLLs embutidas).
    public func initializePrefix(_ bottle: Bottle) async throws {
        try await runChecked(["wineboot", "--init"], in: bottle)
        try await waitForServer(bottle)
    }

    public func setWindowsVersion(_ version: WindowsVersion, in bottle: Bottle) async throws {
        try await runChecked(["winecfg", "-v", version.rawValue], in: bottle)
    }

    public func setRetinaMode(_ enabled: Bool, in bottle: Bottle) async throws {
        try await runChecked([
            "reg", "add", #"HKCU\Software\Wine\Mac Driver"#,
            "/v", "RetinaMode", "/t", "REG_SZ", "/d", enabled ? "y" : "n", "/f",
        ], in: bottle)
    }

    /// Encerra todos os processos Windows da bottle.
    public func killAll(in bottle: Bottle) async throws {
        _ = try await runner.run(executable: runtime.wineserver, arguments: ["-k"], environment: environment(for: bottle), currentDirectory: bottle.url)
    }

    /// Espera o wineserver da bottle terminar (garante que o registro foi gravado).
    public func waitForServer(_ bottle: Bottle) async throws {
        _ = try await runner.run(executable: runtime.wineserver, arguments: ["-w"], environment: environment(for: bottle), currentDirectory: bottle.url)
    }

    /// Inicia um programa sem esperar. A saída vai para `logFile`.
    public func launch(program: URL, arguments: [String] = [], in bottle: Bottle, logFile: URL?, onExit: (@Sendable (Int32) -> Void)? = nil) throws -> SpawnedProcess {
        try runner.spawn(
            executable: try runtime.wineBinary(),
            arguments: try WineCommand.arguments(forProgram: program, extraArguments: arguments),
            environment: environment(for: bottle),
            currentDirectory: WineCommand.workingDirectory(forProgram: program, bottle: bottle),
            logFile: logFile,
            onExit: onExit
        )
    }
}
