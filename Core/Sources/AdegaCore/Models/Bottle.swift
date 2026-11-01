import Foundation

public struct PinnedProgram: Codable, Hashable, Identifiable, Sendable {
    public var name: String
    /// Caminho Unix do .exe/.lnk dentro (ou fora) da bottle.
    public var path: String
    public var arguments: [String]

    public var id: String { path }

    public init(name: String, path: String, arguments: [String] = []) {
        self.name = name
        self.path = path
        self.arguments = arguments
    }
}

/// Configuração persistida em `bottle.json` na raiz da bottle.
public struct BottleConfig: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var displayName: String
    public var runtimeID: String
    public var windowsVersion: WindowsVersion
    public var graphicsBackend: GraphicsBackend
    /// Sincronização via Mach semaphores (msync), suportada pelos builds CrossOver/Gcenx.
    public var msync: Bool
    /// Renderização em resolução nativa Retina (registro do Mac Driver do Wine).
    public var retinaMode: Bool
    /// HUD de desempenho (Metal HUD ou DXVK HUD).
    public var performanceHUD: Bool
    /// Faz o Rosetta anunciar AVX (macOS 15+; vários jogos modernos exigem).
    public var advertiseAVX: Bool
    /// Variáveis extras definidas pelo usuário (têm prioridade sobre tudo).
    public var environment: [String: String]
    /// Overrides extras de DLL definidos pelo usuário (têm prioridade sobre o backend).
    public var dllOverrides: [String: String]
    public var pinnedPrograms: [PinnedProgram]
    public var createdAt: Date

    public init(
        displayName: String,
        runtimeID: String,
        windowsVersion: WindowsVersion = .win10,
        graphicsBackend: GraphicsBackend = .wined3d,
        msync: Bool = true,
        retinaMode: Bool = false,
        performanceHUD: Bool = false,
        advertiseAVX: Bool = false,
        environment: [String: String] = [:],
        dllOverrides: [String: String] = [:],
        pinnedPrograms: [PinnedProgram] = [],
        createdAt: Date = Date()
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.displayName = displayName
        self.runtimeID = runtimeID
        self.windowsVersion = windowsVersion
        self.graphicsBackend = graphicsBackend
        self.msync = msync
        self.retinaMode = retinaMode
        self.performanceHUD = performanceHUD
        self.advertiseAVX = advertiseAVX
        self.environment = environment
        self.dllOverrides = dllOverrides
        self.pinnedPrograms = pinnedPrograms
        self.createdAt = createdAt.truncatedToSeconds
    }

    // Decodificação tolerante: campos novos ganham valor padrão, então bottle.json
    // de versões antigas continuam abrindo.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        displayName = try c.decode(String.self, forKey: .displayName)
        runtimeID = try c.decode(String.self, forKey: .runtimeID)
        windowsVersion = try c.decodeIfPresent(WindowsVersion.self, forKey: .windowsVersion) ?? .win10
        graphicsBackend = try c.decodeIfPresent(GraphicsBackend.self, forKey: .graphicsBackend) ?? .wined3d
        msync = try c.decodeIfPresent(Bool.self, forKey: .msync) ?? true
        retinaMode = try c.decodeIfPresent(Bool.self, forKey: .retinaMode) ?? false
        performanceHUD = try c.decodeIfPresent(Bool.self, forKey: .performanceHUD) ?? false
        advertiseAVX = try c.decodeIfPresent(Bool.self, forKey: .advertiseAVX) ?? false
        environment = try c.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
        dllOverrides = try c.decodeIfPresent([String: String].self, forKey: .dllOverrides) ?? [:]
        pinnedPrograms = try c.decodeIfPresent([PinnedProgram].self, forKey: .pinnedPrograms) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

/// Uma bottle é um WINEPREFIX (pasta com `drive_c`, registro etc.) + `bottle.json`.
public struct Bottle: Identifiable, Equatable, Hashable, Sendable {
    public static let configFileName = "bottle.json"

    /// Nome da pasta; estável e único.
    public let id: String
    public let url: URL
    public var config: BottleConfig

    public init(id: String, url: URL, config: BottleConfig) {
        self.id = id
        self.url = url
        self.config = config
    }

    public var configURL: URL { url.appendingPathComponent(Self.configFileName) }
    public var driveC: URL { url.appendingPathComponent("drive_c", isDirectory: true) }
    public var system32: URL { driveC.appendingPathComponent("windows/system32", isDirectory: true) }
    public var syswow64: URL { driveC.appendingPathComponent("windows/syswow64", isDirectory: true) }

    public func isInitialized(fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: system32.path)
    }

    public static func == (lhs: Bottle, rhs: Bottle) -> Bool {
        lhs.id == rhs.id && lhs.url == rhs.url && lhs.config == rhs.config
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
