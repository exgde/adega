import Foundation

/// Instala, registra e lista builds do Wine em `Runtimes/<id>/`.
public final class RuntimeManager: @unchecked Sendable {
    public static let metadataFileName = "runtime.json"

    public let paths: AdegaPaths
    let downloader: Downloading
    let runner: ProcessRunning
    let fileManager: FileManager

    public init(paths: AdegaPaths, downloader: Downloading = URLSessionDownloader(), runner: ProcessRunning = SystemProcessRunner(), fileManager: FileManager = .default) {
        self.paths = paths
        self.downloader = downloader
        self.runner = runner
        self.fileManager = fileManager
    }

    func directory(for id: String) -> URL {
        paths.runtimes.appendingPathComponent(id, isDirectory: true)
    }

    public func installedRuntimes() -> [InstalledRuntime] {
        guard let entries = try? fileManager.contentsOfDirectory(at: paths.runtimes, includingPropertiesForKeys: nil) else { return [] }
        return entries
            .compactMap { try? JSONStore.read(InstalledRuntime.self, from: $0.appendingPathComponent(Self.metadataFileName)) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    public func runtime(id: String) throws -> InstalledRuntime {
        let url = directory(for: id).appendingPathComponent(Self.metadataFileName)
        guard fileManager.fileExists(atPath: url.path) else { throw AdegaError.runtimeNotFound(id) }
        return try JSONStore.read(InstalledRuntime.self, from: url)
    }

    public func save(_ runtime: InstalledRuntime) throws {
        try JSONStore.write(runtime, to: directory(for: runtime.id).appendingPathComponent(Self.metadataFileName))
    }

    /// Baixa, confere o SHA-256 e extrai um runtime do manifesto.
    public func install(_ descriptor: RuntimeDescriptor, progress: (@Sendable (Double) -> Void)? = nil) async throws -> InstalledRuntime {
        let id = try NameSanitizer.identifier(from: descriptor.id)
        let finalDir = directory(for: id)
        guard !fileManager.fileExists(atPath: finalDir.path) else { throw AdegaError.runtimeAlreadyInstalled(id) }

        try paths.ensureDirectories(fileManager: fileManager)
        let staging = paths.runtimes.appendingPathComponent(".\(id).partial", isDirectory: true)
        try FileOps.removeIfPresent(staging, fileManager: fileManager)
        do {
            let filesDir = staging.appendingPathComponent("files", isDirectory: true)
            try await PackageInstaller(paths: paths, downloader: downloader, runner: runner)
                .downloadVerifyExtract(url: descriptor.url, sha256: descriptor.sha256, into: filesDir, progress: progress)

            let wineRootInStaging = filesDir.appendingPathComponent(descriptor.wineRoot, isDirectory: true)
            _ = try InstalledRuntime.locateWineBinary(in: wineRootInStaging.appendingPathComponent("bin"), fileManager: fileManager)

            try fileManager.moveItem(at: staging, to: finalDir)
            let runtime = InstalledRuntime(
                id: id,
                displayName: descriptor.displayName,
                version: descriptor.version,
                wineRootPath: finalDir.appendingPathComponent("files", isDirectory: true).appendingPathComponent(descriptor.wineRoot, isDirectory: true).path,
                isExternal: false
            )
            try save(runtime)
            return runtime
        } catch {
            try? FileOps.removeIfPresent(staging, fileManager: fileManager)
            throw error
        }
    }

    /// Registra um Wine já instalado (ex.: `/Applications/Wine Crossover.app` do Homebrew).
    /// Com `copy: true` os arquivos são copiados para dentro do Adega, o que permite
    /// instalar componentes (DXMT, D3DMetal) sem tocar na instalação original.
    public func registerExternal(name: String, location: URL, version: String = "externo", copy: Bool) async throws -> InstalledRuntime {
        let id = try NameSanitizer.identifier(from: name)
        let finalDir = directory(for: id)
        guard !fileManager.fileExists(atPath: finalDir.path) else { throw AdegaError.runtimeAlreadyInstalled(id) }

        let wineRoot = InstalledRuntime.normalizeWineRoot(location, fileManager: fileManager)
        _ = try InstalledRuntime.locateWineBinary(in: wineRoot.appendingPathComponent("bin"), fileManager: fileManager)

        try paths.ensureDirectories(fileManager: fileManager)
        var rootPath = wineRoot.path
        if copy {
            let staging = paths.runtimes.appendingPathComponent(".\(id).partial", isDirectory: true)
            try FileOps.removeIfPresent(staging, fileManager: fileManager)
            do {
                let target = staging.appendingPathComponent("files/wine", isDirectory: true)
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                // `cp -a` preserva links simbólicos, permissões e atributos (macOS e Linux).
                try await runner.runChecked(
                    executable: URL(fileURLWithPath: "/bin/cp"),
                    arguments: ["-a", wineRoot.path, target.path],
                    environment: ProcessInfo.processInfo.environment
                )
                try fileManager.moveItem(at: staging, to: finalDir)
            } catch {
                try? FileOps.removeIfPresent(staging, fileManager: fileManager)
                throw error
            }
            rootPath = finalDir.appendingPathComponent("files/wine", isDirectory: true).path
        } else {
            try fileManager.createDirectory(at: finalDir, withIntermediateDirectories: true)
        }

        let runtime = InstalledRuntime(id: id, displayName: name, version: version, wineRootPath: rootPath, isExternal: !copy)
        try save(runtime)
        return runtime
    }

    /// Remove o runtime do Adega. Instalações externas (sem cópia) nunca são apagadas.
    public func remove(id: String) throws {
        let dir = directory(for: id)
        guard fileManager.fileExists(atPath: dir.path) else { throw AdegaError.runtimeNotFound(id) }
        try fileManager.removeItem(at: dir)
    }

    /// Tenta descobrir a versão rodando `wine --version`.
    public func detectVersion(of runtime: InstalledRuntime) async -> String? {
        guard let wine = try? runtime.wineBinary(fileManager: fileManager),
              let result = try? await runner.run(executable: wine, arguments: ["--version"], environment: ProcessInfo.processInfo.environment, currentDirectory: nil),
              result.succeeded else { return nil }
        let version = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? nil : version
    }
}
