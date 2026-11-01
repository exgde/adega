import Foundation

public enum ComponentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case dxvk, dxmt, moltenvk, d3dmetal

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dxvk: return "DXVK"
        case .dxmt: return "DXMT"
        case .moltenvk: return "MoltenVK"
        case .d3dmetal: return "D3DMetal (GPTK)"
        }
    }
}

/// Onde um arquivo do componente é instalado.
public enum InstallScope: String, Codable, Sendable {
    /// Dentro do runtime do Wine (ex.: `lib/wine/x86_64-unix/winemetal.so`). Afeta todas as bottles que usam o runtime.
    case runtime
    /// Dentro da bottle (ex.: `drive_c/windows/system32/d3d11.dll`).
    case bottle
}

/// Mapeia um arquivo/pasta do pacote do componente para o destino.
/// Se a origem for uma pasta, o conteúdo é mesclado no destino.
public struct FileMapping: Codable, Equatable, Sendable {
    /// Relativo à raiz do pacote extraído ("" = a própria raiz).
    public var source: String
    /// Relativo à raiz do runtime (pasta com `bin/`) ou da bottle.
    public var destination: String
    public var scope: InstallScope

    public init(source: String, destination: String, scope: InstallScope) {
        self.source = source
        self.destination = destination
        self.scope = scope
    }
}

/// Um componente gráfico descrito no manifesto. O layout de cada pacote fica nos dados,
/// não no código: quando o DXMT/DXVK mudar a estrutura, basta atualizar o manifesto.
public struct ComponentDescriptor: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: ComponentKind
    public var version: String
    public var url: URL?
    public var sha256: String?
    /// Pasta dentro do arquivo extraído que serve de raiz para `files` (opcional).
    public var root: String?
    public var files: [FileMapping]
    public var license: String?
    public var notes: String?

    public init(id: String, kind: ComponentKind, version: String, url: URL? = nil, sha256: String? = nil, root: String? = nil, files: [FileMapping], license: String? = nil, notes: String? = nil) {
        self.id = id
        self.kind = kind
        self.version = version
        self.url = url
        self.sha256 = sha256
        self.root = root
        self.files = files
        self.license = license
        self.notes = notes
    }

    public var hasRuntimeFiles: Bool { files.contains { $0.scope == .runtime } }
    public var hasBottleFiles: Bool { files.contains { $0.scope == .bottle } }

    /// D3DMetal: o usuário aponta para a própria cópia do Game Porting Toolkit
    /// (pasta `redist/lib` do DMG da Apple). O Adega nunca redistribui esses arquivos.
    /// O conteúdo de `redist/lib` é mesclado no `lib/` do runtime, como o GPTK documenta.
    public static func d3dMetal(version: String) -> ComponentDescriptor {
        ComponentDescriptor(
            id: "d3dmetal-\(version)",
            kind: .d3dmetal,
            version: version,
            files: [FileMapping(source: "", destination: "lib", scope: .runtime)],
            license: "Apple (proprietária) — cópia local do usuário",
            notes: "Importado do Game Porting Toolkit do próprio usuário."
        )
    }
}

/// Um componente baixado/importado. Persistido em `Components/<id>/component.json`;
/// os arquivos ficam em `Components/<id>/files/`.
public struct InstalledComponent: Codable, Identifiable, Equatable, Sendable {
    public var descriptor: ComponentDescriptor
    public var filesPath: String
    public var installedAt: Date

    public init(descriptor: ComponentDescriptor, filesPath: String, installedAt: Date = Date()) {
        self.descriptor = descriptor
        self.filesPath = filesPath
        self.installedAt = installedAt.truncatedToSeconds
    }

    public var id: String { descriptor.id }
    public var kind: ComponentKind { descriptor.kind }

    /// Raiz efetiva para resolver `FileMapping.source`.
    public var sourceRoot: URL {
        let files = URL(fileURLWithPath: filesPath, isDirectory: true)
        guard let root = descriptor.root, !root.isEmpty else { return files }
        return files.appendingPathComponent(root, isDirectory: true)
    }
}
