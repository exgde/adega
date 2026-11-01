import Foundation

/// "Receita" de configuração por programa/jogo. É aqui que fica o valor do produto:
/// um catálogo curado e testado do que funciona.
public struct Preset: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// Nomes de executáveis que disparam esta receita (comparação sem diferenciar maiúsculas).
    public var executables: [String]
    public var graphicsBackend: GraphicsBackend?
    public var windowsVersion: WindowsVersion?
    public var msync: Bool?
    public var advertiseAVX: Bool?
    public var retinaMode: Bool?
    public var winetricks: [String]
    public var environment: [String: String]
    public var dllOverrides: [String: String]
    public var notes: String?

    public init(id: String, name: String, executables: [String], graphicsBackend: GraphicsBackend? = nil, windowsVersion: WindowsVersion? = nil, msync: Bool? = nil, advertiseAVX: Bool? = nil, retinaMode: Bool? = nil, winetricks: [String] = [], environment: [String: String] = [:], dllOverrides: [String: String] = [:], notes: String? = nil) {
        self.id = id
        self.name = name
        self.executables = executables
        self.graphicsBackend = graphicsBackend
        self.windowsVersion = windowsVersion
        self.msync = msync
        self.advertiseAVX = advertiseAVX
        self.retinaMode = retinaMode
        self.winetricks = winetricks
        self.environment = environment
        self.dllOverrides = dllOverrides
        self.notes = notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        executables = try c.decodeIfPresent([String].self, forKey: .executables) ?? []
        graphicsBackend = try c.decodeIfPresent(GraphicsBackend.self, forKey: .graphicsBackend)
        windowsVersion = try c.decodeIfPresent(WindowsVersion.self, forKey: .windowsVersion)
        msync = try c.decodeIfPresent(Bool.self, forKey: .msync)
        advertiseAVX = try c.decodeIfPresent(Bool.self, forKey: .advertiseAVX)
        retinaMode = try c.decodeIfPresent(Bool.self, forKey: .retinaMode)
        winetricks = try c.decodeIfPresent([String].self, forKey: .winetricks) ?? []
        environment = try c.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
        dllOverrides = try c.decodeIfPresent([String: String].self, forKey: .dllOverrides) ?? [:]
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }

    /// Aplica a receita sobre a configuração atual (valores da receita vencem).
    public func applied(to config: BottleConfig) -> BottleConfig {
        var result = config
        if let graphicsBackend { result.graphicsBackend = graphicsBackend }
        if let windowsVersion { result.windowsVersion = windowsVersion }
        if let msync { result.msync = msync }
        if let advertiseAVX { result.advertiseAVX = advertiseAVX }
        if let retinaMode { result.retinaMode = retinaMode }
        result.environment.merge(environment) { _, new in new }
        result.dllOverrides.merge(dllOverrides) { _, new in new }
        return result
    }
}

public struct PresetCatalog: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var presets: [Preset]

    public init(schemaVersion: Int = 1, presets: [Preset] = []) {
        self.schemaVersion = schemaVersion
        self.presets = presets
    }

    public static func decode(from data: Data) throws -> PresetCatalog {
        try JSONDecoder().decode(PresetCatalog.self, from: data)
    }

    public func match(executable: URL) -> Preset? {
        let name = executable.lastPathComponent.lowercased()
        return presets.first { preset in
            preset.executables.contains { $0.lowercased() == name }
        }
    }
}

/// Configurações globais do app (`settings.json`).
public struct AppSettings: Codable, Equatable, Sendable {
    /// URL (https ou file) do `runtimes.json`.
    public var manifestURL: String
    /// URL (https ou file) do catálogo de receitas.
    public var presetsURL: String

    public init(manifestURL: String = "", presetsURL: String = "") {
        self.manifestURL = manifestURL
        self.presetsURL = presetsURL
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        manifestURL = try c.decodeIfPresent(String.self, forKey: .manifestURL) ?? ""
        presetsURL = try c.decodeIfPresent(String.self, forKey: .presetsURL) ?? ""
    }

    public static func load(paths: AdegaPaths) -> AppSettings {
        (try? JSONStore.read(AppSettings.self, from: paths.settingsFile)) ?? AppSettings()
    }

    public func save(paths: AdegaPaths) throws {
        try JSONStore.write(self, to: paths.settingsFile)
    }
}
