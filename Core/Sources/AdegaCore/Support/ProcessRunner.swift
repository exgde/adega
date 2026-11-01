import Foundation

public struct ProcessResult: Sendable, Equatable {
    public let exitCode: Int32
    /// stdout + stderr combinados.
    public let output: String

    public init(exitCode: Int32, output: String) {
        self.exitCode = exitCode
        self.output = output
    }

    public var succeeded: Bool { exitCode == 0 }

    /// Últimas linhas da saída, para mensagens de erro.
    public func tail(lines: Int = 20) -> String {
        output.split(separator: "\n", omittingEmptySubsequences: false).suffix(lines).joined(separator: "\n")
    }
}

/// Processo iniciado em segundo plano (ex.: um jogo).
public final class SpawnedProcess: @unchecked Sendable {
    private let process: Process
    public let logURL: URL?

    init(process: Process, logURL: URL?) {
        self.process = process
        self.logURL = logURL
    }

    public var pid: Int32 { process.processIdentifier }
    public var isRunning: Bool { process.isRunning }
    public var exitCode: Int32? { process.isRunning ? nil : process.terminationStatus }

    public func waitUntilExit() { process.waitUntilExit() }
    public func terminate() { process.terminate() }
}

public protocol ProcessRunning: Sendable {
    /// Executa e espera terminar.
    func run(executable: URL, arguments: [String], environment: [String: String], currentDirectory: URL?) async throws -> ProcessResult

    /// Inicia sem esperar; saída vai (em append) para `logFile`.
    func spawn(executable: URL, arguments: [String], environment: [String: String], currentDirectory: URL?, logFile: URL?, onExit: (@Sendable (Int32) -> Void)?) throws -> SpawnedProcess
}

public extension ProcessRunning {
    func run(executable: URL, arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment) async throws -> ProcessResult {
        try await run(executable: executable, arguments: arguments, environment: environment, currentDirectory: nil)
    }

    /// Executa e lança erro se o código de saída for diferente de zero.
    @discardableResult
    func runChecked(executable: URL, arguments: [String], environment: [String: String], currentDirectory: URL? = nil) async throws -> ProcessResult {
        let result = try await run(executable: executable, arguments: arguments, environment: environment, currentDirectory: currentDirectory)
        guard result.succeeded else {
            let command = ([executable.lastPathComponent] + arguments).joined(separator: " ")
            throw AdegaError.processFailed(command: command, exitCode: result.exitCode, outputTail: result.tail())
        }
        return result
    }
}

/// Implementação real com `Foundation.Process`.
///
/// A saída vai para arquivos (não `Pipe`): o `wineserver` herda os descritores e
/// continua vivo depois que o `wine` termina, o que travaria a leitura de um pipe.
public struct SystemProcessRunner: ProcessRunning {
    public init() {}

    public func run(executable: URL, arguments: [String], environment: [String: String], currentDirectory: URL?) async throws -> ProcessResult {
        let fm = FileManager.default
        let outputURL = fm.temporaryDirectory.appendingPathComponent("adega-\(UUID().uuidString).out")
        _ = fm.createFile(atPath: outputURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: outputURL)
        defer {
            try? handle.close()
            try? fm.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = handle

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        let data = (try? Data(contentsOf: outputURL)) ?? Data()
        return ProcessResult(exitCode: status, output: String(decoding: data, as: UTF8.self))
    }

    public func spawn(executable: URL, arguments: [String], environment: [String: String], currentDirectory: URL?, logFile: URL?, onExit: (@Sendable (Int32) -> Void)?) throws -> SpawnedProcess {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        process.standardInput = FileHandle.nullDevice

        let logHandle: FileHandle?
        if let logFile {
            let fm = FileManager.default
            try fm.createDirectory(at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: logFile.path) { _ = fm.createFile(atPath: logFile.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: logFile)
            handle.seekToEndOfFile()
            process.standardOutput = handle
            process.standardError = handle
            logHandle = handle
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            logHandle = nil
        }

        process.terminationHandler = { finished in
            try? logHandle?.close()
            onExit?(finished.terminationStatus)
        }
        do {
            try process.run()
        } catch {
            try? logHandle?.close()
            throw error
        }
        return SpawnedProcess(process: process, logURL: logFile)
    }
}
