import Foundation

/// Catálogo publicado (ex.: `runtimes.json` num repositório/GitHub Pages).
public struct RuntimeManifest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var runtimes: [RuntimeDescriptor]
    public var components: [ComponentDescriptor]

    public init(schemaVersion: Int = 1, runtimes: [RuntimeDescriptor] = [], components: [ComponentDescriptor] = []) {
        self.schemaVersion = schemaVersion
        self.runtimes = runtimes
        self.components = components
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        runtimes = try c.decodeIfPresent([RuntimeDescriptor].self, forKey: .runtimes) ?? []
        components = try c.decodeIfPresent([ComponentDescriptor].self, forKey: .components) ?? []
    }
}

/// Um build do Wine disponível para download.
public struct RuntimeDescriptor: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var version: String
    public var url: URL
    public var sha256: String
    public var size: Int64?
    /// Caminho, dentro do arquivo extraído, da pasta que contém `bin/` e `lib/`.
    /// Ex.: "Wine Crossover.app/Contents/Resources/wine".
    public var wineRoot: String
    public var notes: String?

    public init(id: String, displayName: String, version: String, url: URL, sha256: String, size: Int64? = nil, wineRoot: String, notes: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.url = url
        self.sha256 = sha256
        self.size = size
        self.wineRoot = wineRoot
        self.notes = notes
    }
}

/// Um runtime instalado. Persistido em `Runtimes/<id>/runtime.json`.
public struct InstalledRuntime: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var version: String
    /// Caminho absoluto da pasta que contém `bin/` e `lib/`.
    public var wineRootPath: String
    /// true = aponta para uma instalação fora do Adega (não é modificada nem apagada).
    public var isExternal: Bool
    public var installedAt: Date
    /// Componentes com arquivos instalados dentro do runtime (kind → id do componente).
    public var runtimeComponents: [String: String]

    public init(id: String, displayName: String, version: String, wineRootPath: String, isExternal: Bool, installedAt: Date = Date(), runtimeComponents: [String: String] = [:]) {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.wineRootPath = wineRootPath
        self.isExternal = isExternal
        self.installedAt = installedAt.truncatedToSeconds
        self.runtimeComponents = runtimeComponents
    }

    public var wineRoot: URL { URL(fileURLWithPath: wineRootPath, isDirectory: true) }
    public var binDirectory: URL { wineRoot.appendingPathComponent("bin", isDirectory: true) }
    public var wineserver: URL { binDirectory.appendingPathComponent("wineserver") }

    /// `wine64` em builds antigos (pré-WoW64); `wine` nos atuais (Wine 9+ no macOS).
    public func wineBinary(fileManager: FileManager = .default) throws -> URL {
        try Self.locateWineBinary(in: binDirectory, fileManager: fileManager)
    }

    static func locateWineBinary(in bin: URL, fileManager: FileManager = .default) throws -> URL {
        for name in ["wine64", "wine"] {
            let candidate = bin.appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        throw AdegaError.wineBinaryNotFound(bin.deletingLastPathComponent().path)
    }

    /// Aceita a pasta raiz do Wine, a pasta `bin`, ou um `.app` (ex.: "Wine Crossover.app").
    public static func normalizeWineRoot(_ url: URL, fileManager: FileManager = .default) -> URL {
        var candidate = url.standardizedFileURL
        if candidate.pathExtension == "app" {
            candidate = candidate.appendingPathComponent("Contents/Resources/wine", isDirectory: true)
        } else if candidate.lastPathComponent == "bin" {
            candidate = candidate.deletingLastPathComponent()
        }
        return candidate
    }
}
