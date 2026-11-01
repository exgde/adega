import Foundation

/// Cria, lista, salva e apaga bottles em `Bottles/<id>/`.
public final class BottleManager: @unchecked Sendable {
    public let paths: AdegaPaths
    let runner: ProcessRunning
    let fileManager: FileManager

    public init(paths: AdegaPaths, runner: ProcessRunning = SystemProcessRunner(), fileManager: FileManager = .default) {
        self.paths = paths
        self.runner = runner
        self.fileManager = fileManager
    }

    public func bottles() -> [Bottle] {
        guard let entries = try? fileManager.contentsOfDirectory(at: paths.bottles, includingPropertiesForKeys: nil) else { return [] }
        return entries
            .compactMap { try? load(from: $0) }
            .sorted { $0.config.displayName.localizedStandardCompare($1.config.displayName) == .orderedAscending }
    }

    public func bottle(id: String) throws -> Bottle {
        let url = paths.bottles.appendingPathComponent(id, isDirectory: true)
        guard fileManager.fileExists(atPath: url.appendingPathComponent(Bottle.configFileName).path) else {
            throw AdegaError.bottleNotFound(id)
        }
        return try load(from: url)
    }

    /// Procura por id (nome da pasta) ou pelo nome exibido.
    public func find(_ nameOrID: String) throws -> Bottle {
        if let bottle = try? bottle(id: nameOrID) { return bottle }
        if let bottle = bottles().first(where: { $0.config.displayName.caseInsensitiveCompare(nameOrID) == .orderedSame }) {
            return bottle
        }
        throw AdegaError.bottleNotFound(nameOrID)
    }

    func load(from url: URL) throws -> Bottle {
        let config = try JSONStore.read(BottleConfig.self, from: url.appendingPathComponent(Bottle.configFileName))
        return Bottle(id: url.lastPathComponent, url: url, config: config)
    }

    public func save(_ bottle: Bottle) throws {
        try JSONStore.write(bottle.config, to: bottle.configURL)
    }

    /// Cria a pasta e o `bottle.json`, sem rodar o Wine.
    public func prepare(name: String, config: BottleConfig) throws -> Bottle {
        let id = try NameSanitizer.identifier(from: name)
        let url = paths.bottles.appendingPathComponent(id, isDirectory: true)
        guard !fileManager.fileExists(atPath: url.path) else { throw AdegaError.bottleAlreadyExists(id) }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        var config = config
        config.displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let bottle = Bottle(id: id, url: url, config: config)
        try save(bottle)
        return bottle
    }

    /// Cria a bottle e inicializa o prefixo do Wine. Se o Wine falhar, a pasta é removida.
    public func create(name: String, config: BottleConfig, runtime: InstalledRuntime) async throws -> Bottle {
        try paths.ensureDirectories(fileManager: fileManager)
        let bottle = try prepare(name: name, config: config)
        do {
            let wine = Wine(runtime: runtime, runner: runner)
            try await wine.initializePrefix(bottle)
            try await wine.setWindowsVersion(bottle.config.windowsVersion, in: bottle)
            if bottle.config.retinaMode {
                try await wine.setRetinaMode(true, in: bottle)
            }
            try await wine.waitForServer(bottle)
            return bottle
        } catch {
            try? fileManager.removeItem(at: bottle.url)
            throw error
        }
    }

    /// Aplica no prefixo o que mudou entre `previous` e a config atual, e salva.
    /// (Backend gráfico é tratado pelo `ComponentManager`.)
    public func applyChanges(to bottle: Bottle, previous: BottleConfig, runtime: InstalledRuntime) async throws {
        try save(bottle)
        let wine = Wine(runtime: runtime, runner: runner)
        var touched = false
        if bottle.config.windowsVersion != previous.windowsVersion {
            try await wine.setWindowsVersion(bottle.config.windowsVersion, in: bottle)
            touched = true
        }
        if bottle.config.retinaMode != previous.retinaMode {
            try await wine.setRetinaMode(bottle.config.retinaMode, in: bottle)
            touched = true
        }
        if touched { try await wine.waitForServer(bottle) }
    }

    /// Move para a Lixeira (no macOS) — a bottle pode conter saves e dados do usuário.
    public func delete(_ bottle: Bottle) throws {
        #if os(macOS)
        try fileManager.trashItem(at: bottle.url, resultingItemURL: nil)
        #else
        try fileManager.removeItem(at: bottle.url)
        #endif
    }

    public func bottles(using runtimeID: String) -> [Bottle] {
        bottles().filter { $0.config.runtimeID == runtimeID }
    }
}
